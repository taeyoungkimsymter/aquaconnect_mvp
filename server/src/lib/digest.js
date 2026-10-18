import { query } from '../db.js';
import { notifyMembers } from './notify.js';

// 미완료된 업무 / 오늘 해야할 일 notifications (these replaced the old 하루 요약 /
// 주간 요약). Both go out daily at the member's chosen time (default 08:30).
// Times are Korean time (KST, UTC+9) — the server itself runs in UTC.
//
// A "업무" is a 할일 memo (tagged 할일 or containing "할일:") that hasn't been
// checked off. 미완료된 업무 = every open one in the org; 오늘 해야할 일 = the open
// ones on farms assigned to this member. Settings columns keep their old names:
// daily_* = 미완료된 업무, weekly_enabled / last_weekly_on = 오늘 해야할 일.
const CHECK_EVERY_MS = 60 * 1000;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const PREVIEW_COUNT = 3;

export const DIGEST_DEFAULTS = { dailyEnabled: true, dailyTime: '08:30', weeklyEnabled: true };
export const DAILY_TIME_RE = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;

/** Current KST date ("2026-10-06"), time ("16:00") and weekday (0 = Sunday). */
export function kstNow(now = new Date()) {
  const k = new Date(now.getTime() + KST_OFFSET_MS);
  return { date: k.toISOString().slice(0, 10), time: k.toISOString().slice(11, 16), weekday: k.getUTCDay() };
}

const label = (date) => `${Number(date.slice(5, 7))}/${Number(date.slice(8, 10))}`;

// [memberId] limits it to farms assigned to that member.
async function openTasks(orgId, memberId = null) {
  const { rows } = await query(
    `select mm.content, f.name as farm_name
     from memos mm left join farms f on f.id = mm.farm_id
     where mm.org_id = $1 and mm.completed_at is null
       and ('할일' = any(mm.tags) or mm.content like '%할일:%')
       and ($2::uuid is null or f.assigned_member_id = $2)
     order by mm.created_at`,
    [orgId, memberId],
  );
  return rows;
}

const oneLine = (text) => {
  const t = text.replace(/^.*?할일:s*/s, '').replace(/s+/g, ' ').trim();
  return t.length > 24 ? `${t.slice(0, 24)}…` : t;
};

function tasksBody(tasks, emptyText, countText) {
  if (tasks.length === 0) return emptyText;
  const preview = tasks.slice(0, PREVIEW_COUNT).map((t) => `${t.farm_name ?? '미지정'} ${oneLine(t.content)}`);
  const more = tasks.length > PREVIEW_COUNT ? ` 외 ${tasks.length - PREVIEW_COUNT}건` : '';
  return `${countText(tasks.length)} · ${preview.join(', ')}${more}`;
}

// Claims (marks as sent) and returns the members due now. The conditional
// update is the claim, so two server instances can't both send one summary.
async function claim(sentColumn, enabledColumn, now) {
  const { rows } = await query(
    `update digest_settings d set ${sentColumn} = $1::date
     from members m
     where m.id = d.member_id and m.status = 'active'
       and d.${enabledColumn} and d.daily_time <= $2
       and (d.${sentColumn} is null or d.${sentColumn} < $1::date)
     returning d.member_id, m.org_id`,
    [now.date, now.time],
  );
  return rows;
}

async function send(claimed, { title, memberOnly, emptyText, countText }) {
  const orgTasks = new Map();
  for (const { member_id: memberId, org_id: orgId } of claimed) {
    let tasks;
    if (memberOnly) tasks = await openTasks(orgId, memberId);
    else {
      if (!orgTasks.has(orgId)) orgTasks.set(orgId, await openTasks(orgId));
      tasks = orgTasks.get(orgId);
    }
    await notifyMembers({
      orgId,
      memberIds: [memberId],
      type: 'digest',
      title,
      body: tasksBody(tasks, emptyText, countText),
      link: '/memo',
    });
  }
}

let running = false;

export async function runDigests(at = new Date()) {
  if (running) return;
  running = true;
  try {
    const now = kstNow(at);
    // Members without a row get the defaults; the row is where last-sent is kept.
    await query('insert into digest_settings (member_id) select id from members on conflict do nothing');
    const date = label(now.date);
    await send(await claim('last_daily_on', 'daily_enabled', now), {
      title: `미완료된 업무 (${date})`,
      emptyText: '미완료된 업무가 없어요',
      countText: (n) => `미완료 ${n}건`,
    });
    await send(await claim('last_weekly_on', 'weekly_enabled', now), {
      title: `오늘 해야할 일 (${date})`,
      memberOnly: true,
      emptyText: '내 담당 양식장에 오늘 해야할 일이 없어요',
      countText: (n) => `할 일 ${n}건`,
    });
  } catch (err) {
    console.error('digest run failed', err);
  } finally {
    running = false;
  }
}

export function scheduleDigests() {
  setInterval(runDigests, CHECK_EVERY_MS).unref();
}
