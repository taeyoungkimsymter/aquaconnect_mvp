import webpush from 'web-push';

import { query } from '../db.js';

// Web Push (VAPID) keys: taken from env when set, otherwise generated once
// and kept in `app_config` so every restart/deploy signs with the same pair
// (a new pair would silently invalidate every existing browser subscription).
let vapidPromise = null;

export function vapidKeys() {
  vapidPromise ??= loadVapidKeys().catch((err) => {
    vapidPromise = null;
    throw err;
  });
  return vapidPromise;
}

async function loadVapidKeys() {
  let publicKey = process.env.VAPID_PUBLIC_KEY;
  let privateKey = process.env.VAPID_PRIVATE_KEY;
  if (!publicKey || !privateKey) {
    const { rows } = await query("select key, value from app_config where key in ('vapid_public_key', 'vapid_private_key')");
    const stored = Object.fromEntries(rows.map((r) => [r.key, r.value]));
    if (stored.vapid_public_key && stored.vapid_private_key) {
      publicKey = stored.vapid_public_key;
      privateKey = stored.vapid_private_key;
    } else {
      const generated = webpush.generateVAPIDKeys();
      // `on conflict do nothing` + re-read: if two instances race, both end
      // up using whichever pair was written first.
      await query(
        "insert into app_config (key, value) values ('vapid_public_key', $1), ('vapid_private_key', $2) on conflict (key) do nothing",
        [generated.publicKey, generated.privateKey],
      );
      const { rows: again } = await query(
        "select key, value from app_config where key in ('vapid_public_key', 'vapid_private_key')",
      );
      const saved = Object.fromEntries(again.map((r) => [r.key, r.value]));
      publicKey = saved.vapid_public_key;
      privateKey = saved.vapid_private_key;
    }
  }
  const subject = process.env.VAPID_SUBJECT || 'https://aquaconnect-mvp.vercel.app';
  return { publicKey, privateKey, subject };
}

// 'inquiry' (a farm's 문의) and 'mention' (호출 in a 댓글) have no setting:
// they're always delivered. 'comment' follows the memo setting; 'digest' is
// governed by digest_settings instead.
export const NOTIFICATION_TYPES = ['risk', 'memo', 'test', 'inquiry', 'comment', 'digest', 'mention'];

const SETTING_COLUMN = { risk: 'risk_alerts', memo: 'memo_alerts', comment: 'memo_alerts' };

export function toNotificationJson(row) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    link: row.link,
    createdAt: row.created_at,
    readAt: row.read_at,
  };
}

// Stores an inbox notification for each recipient and pushes it to every
// device they've subscribed. Never throws — a notification failing must not
// fail the memo/report write that triggered it.
export async function notifyMembers({ orgId, memberIds, excludeMemberId = null, type, title, body, link = null }) {
  try {
    const settingColumn = SETTING_COLUMN[type];
    const { rows: recipients } = await query(
      `select m.id from members m
       left join notification_settings s on s.member_id = m.id
       where ${memberIds ? 'm.id = any($1::uuid[])' : 'm.org_id = $1'}
         and ($2::uuid is null or m.id <> $2)
         ${settingColumn ? `and coalesce(s.${settingColumn}, true)` : ''}`,
      [memberIds ?? orgId, excludeMemberId],
    );

    for (const { id: memberId } of recipients) {
      const { rows } = await query(
        `insert into notifications (member_id, type, title, body, link) values ($1, $2, $3, $4, $5) returning *`,
        [memberId, type, title, body, link],
      );
      await pushToMember(memberId, toNotificationJson(rows[0]));
    }
  } catch (err) {
    console.error('notifyMembers failed', err);
  }
}

async function pushToMember(memberId, notification) {
  const { rows: subs } = await query('select * from push_subscriptions where member_id = $1', [memberId]);
  if (subs.length === 0) return;
  const { publicKey, privateKey, subject } = await vapidKeys();
  const payload = JSON.stringify({
    id: notification.id,
    title: notification.title,
    body: notification.body,
    link: notification.link,
  });

  await Promise.all(
    subs.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          payload,
          { vapidDetails: { subject, publicKey, privateKey }, TTL: 60 * 60 * 24 },
        );
      } catch (err) {
        // 404/410: the browser dropped this subscription (permission revoked,
        // app data cleared) — forget it so we stop trying.
        if (err.statusCode === 404 || err.statusCode === 410) {
          await query('delete from push_subscriptions where id = $1', [sub.id]);
        } else {
          console.error('web push failed', err.statusCode ?? '', err.body ?? err.message);
        }
      }
    }),
  );
}
