import { Router } from 'express';

import { requireAuth } from '../auth.js';
import { query } from '../db.js';
import { DAILY_TIME_RE, DIGEST_DEFAULTS, kstNow } from '../lib/digest.js';
import { notifyMembers, toNotificationJson, vapidKeys } from '../lib/notify.js';

export const notificationsRouter = Router();
notificationsRouter.use(requireAuth);

notificationsRouter.get('/', async (req, res) => {
  const { rows } = await query(
    'select * from notifications where member_id = $1 order by created_at desc limit 100',
    [req.memberId],
  );
  const { rows: countRows } = await query(
    'select count(*)::int as c from notifications where member_id = $1 and read_at is null',
    [req.memberId],
  );
  res.json({ items: rows.map(toNotificationJson), unreadCount: countRows[0].c });
});

notificationsRouter.post('/read-all', async (req, res) => {
  await query('update notifications set read_at = now() where member_id = $1 and read_at is null', [req.memberId]);
  res.status(204).end();
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

notificationsRouter.post('/:id/read', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: '알림을 찾을 수 없습니다.' });
  const { rows } = await query(
    'update notifications set read_at = coalesce(read_at, now()) where id = $1 and member_id = $2 returning id',
    [req.params.id, req.memberId],
  );
  if (!rows[0]) return res.status(404).json({ error: '알림을 찾을 수 없습니다.' });
  res.status(204).end();
});

function toSettingsJson(row) {
  return { riskAlerts: row?.risk_alerts ?? true, memoAlerts: row?.memo_alerts ?? true };
}

notificationsRouter.get('/settings', async (req, res) => {
  const { rows } = await query('select * from notification_settings where member_id = $1', [req.memberId]);
  res.json(toSettingsJson(rows[0]));
});

notificationsRouter.put('/settings', async (req, res) => {
  const { riskAlerts, memoAlerts } = req.body ?? {};
  if (typeof riskAlerts !== 'boolean' || typeof memoAlerts !== 'boolean') {
    return res.status(400).json({ error: '알림 설정 값이 올바르지 않습니다.' });
  }
  const { rows } = await query(
    `insert into notification_settings (member_id, risk_alerts, memo_alerts) values ($1, $2, $3)
     on conflict (member_id) do update set risk_alerts = excluded.risk_alerts, memo_alerts = excluded.memo_alerts
     returning *`,
    [req.memberId, riskAlerts, memoAlerts],
  );
  res.json(toSettingsJson(rows[0]));
});

// 요약 알림 설정 (sent by lib/digest.js): dailyEnabled = 미완료된 업무, weeklyEnabled =
// 오늘 해야할 일 (names kept from when these were the 하루/주간 요약); dailyTime is shared.
function toDigestJson(row) {
  return {
    dailyEnabled: row?.daily_enabled ?? DIGEST_DEFAULTS.dailyEnabled,
    dailyTime: row?.daily_time ?? DIGEST_DEFAULTS.dailyTime,
    weeklyEnabled: row?.weekly_enabled ?? DIGEST_DEFAULTS.weeklyEnabled,
  };
}

notificationsRouter.get('/digest', async (req, res) => {
  const { rows } = await query('select * from digest_settings where member_id = $1', [req.memberId]);
  res.json(toDigestJson(rows[0]));
});

notificationsRouter.put('/digest', async (req, res) => {
  const { dailyEnabled, dailyTime, weeklyEnabled } = req.body ?? {};
  if (typeof dailyEnabled !== 'boolean' || typeof weeklyEnabled !== 'boolean' || !DAILY_TIME_RE.test(dailyTime ?? '')) {
    return res.status(400).json({ error: '업무 알림 설정 값이 올바르지 않습니다.' });
  }
  // Moving the time to one that has already passed today starts tomorrow,
  // instead of firing the moment the setting is saved.
  const now = kstNow();
  const { rows } = await query(
    `insert into digest_settings (member_id, daily_enabled, daily_time, weekly_enabled, last_daily_on, last_weekly_on)
     values ($1, $2, $3, $4, case when $3 <= $5 then $6::date end, case when $3 <= $5 then $6::date end)
     on conflict (member_id) do update set
       daily_enabled = excluded.daily_enabled,
       daily_time = excluded.daily_time,
       weekly_enabled = excluded.weekly_enabled,
       last_daily_on = case
         when excluded.daily_time <= $5 and coalesce(digest_settings.last_daily_on, '-infinity') < $6::date then $6::date
         else digest_settings.last_daily_on
       end,
       last_weekly_on = case
         when excluded.daily_time <= $5 and coalesce(digest_settings.last_weekly_on, '-infinity') < $6::date then $6::date
         else digest_settings.last_weekly_on
       end
     returning *`,
    [req.memberId, dailyEnabled, dailyTime, weeklyEnabled, now.time, now.date],
  );
  res.json(toDigestJson(rows[0]));
});

notificationsRouter.get('/push/public-key', async (req, res) => {
  const { publicKey } = await vapidKeys();
  res.json({ publicKey });
});

notificationsRouter.post('/push/subscriptions', async (req, res) => {
  const { endpoint, p256dh, auth } = req.body ?? {};
  if (typeof endpoint !== 'string' || !endpoint.startsWith('https://') || !p256dh || !auth) {
    return res.status(400).json({ error: '푸시 구독 정보가 올바르지 않습니다.' });
  }
  // The same browser re-subscribing (or a different member signing in on
  // it) takes the endpoint over rather than duplicating it.
  await query(
    `insert into push_subscriptions (member_id, endpoint, p256dh, auth, user_agent) values ($1, $2, $3, $4, $5)
     on conflict (endpoint) do update
       set member_id = excluded.member_id, p256dh = excluded.p256dh, auth = excluded.auth, user_agent = excluded.user_agent`,
    [req.memberId, endpoint, p256dh, auth, req.get('user-agent') ?? null],
  );
  res.status(201).json({ ok: true });
});

notificationsRouter.delete('/push/subscriptions', async (req, res) => {
  const endpoint = req.body?.endpoint;
  if (typeof endpoint !== 'string') return res.status(400).json({ error: '구독 정보가 없습니다.' });
  await query('delete from push_subscriptions where endpoint = $1 and member_id = $2', [endpoint, req.memberId]);
  res.status(204).end();
});

notificationsRouter.post('/test', async (req, res) => {
  await notifyMembers({
    memberIds: [req.memberId],
    type: 'test',
    title: 'AquaConnect 테스트 알림',
    body: '알림이 정상적으로 도착했어요.',
    link: '/notifications',
  });
  res.status(201).json({ ok: true });
});
