import { query } from '../db.js';
import { notifyMembers } from './notify.js';

// 오늘의 업무 notification: once a day at each member's chosen time (default
// 08:00), their open work — 할일 assigned to / written by them and memos
// that call (@) them — plus the org's 위험·주의 farms. It replaced the old
// 하루 요약 / 주간 요약 (weekly_enabled is kept but no longer sends).
// Times are Korean time (KST, UTC+9) — the server itself runs in UTC.
const CHECK_EVERY_MS = 60 * 1000;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

export const DIGEST_DEFAULTS = { dailyEnabled: true, dailyTime: '08:00', weeklyEnabled: true };
export const DAILY_TIME_RE = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;

/** Current KST date ("2026-10-06"), time ("16:00") and weekday (0 = Sunday). */
export function kstNow(now = new Date()) {
  const k = new Date(now.getTime() + KST_OFFSET_MS);
  return { date: k.toISOString().slice(0, 10), time: k.toISOString().slice(11, 16), weekday: k.getUTCDay() };
}

const label = (date) => `${Number(date.slice(5, 7))}/${Number(date.slice(8, 10))}`;

async function orgRisk(orgId) {
  const { rows } = await query(
    'select risk_level, count(*)::int as c from farms where org_id = $1 group by risk_level',
    [orgId],
  );
  const risk = Object.fromEntries(rows.map((r) => [r.risk_level, r.c]));
  return { farmCount: rows.reduce((sum, r) => sum + r.c, 0), danger: risk.danger ?? 0, warning: risk.warning ?? 0 };
}

// A member's open 업무 — must match Memo.isOpenTaskFor in the app
// (lib/data/models/memo.dart): not done, and either it calls them (@), it
// is assigned to them ('담당:<이름>' tag), or it is an unassigned task
// (할일 tag / '할일:' in the text) they wrote.
export async function memberOpenTasks(memberId) {
  const { rows } = await query(
    `with t as (
       select
         exists (select 1 from memo_comment_mentions x join memo_comments c on c.id = x.comment_id
                 where c.memo_id = mm.id and x.member_id = me.id) as mentioned,
         ('담당:' || me.name) = any(mm.tags) as assigned_to_me,
         exists (select 1 from unnest(mm.tags) t where t like '담당:%') as assigned,
         ('할일' = any(mm.tags) or mm.content like '%할일:%') as todo,
         mm.author_member_id = me.id as mine
       from memos mm join members me on me.id = $1
       where mm.org_id = me.org_id and mm.done_at is null
     )
     select count(*) filter (where mentioned or assigned_to_me or (todo and not assigned and mine))::int as open,
            count(*) filter (where mentioned)::int as mentioned
     from t`,
    [memberId],
  );
  return rows[0];
}

function tasksBody(tasks, risk) {
  const parts = [];
  if (tasks.open) {
    parts.push(`남은 업무 ${tasks.open}건`);
    if (tasks.mentioned) parts.push(`나를 호출 ${tasks.mentioned}건`);
  } else {
    parts.push('남은 업무가 없어요');
  }
  if (risk.farmCount) parts.push(`위험 ${risk.danger}곳 · 주의 ${risk.warning}곳`);
  return parts.join(' · ');
}

// Claims (marks as sent) and returns the members due now. The conditional
// update is the claim, so two server instances can't both send one summary.
async function claimDaily(now) {
  const { rows } = await query(
    `update digest_settings d set last_daily_on = $1::date
     from members m
     where m.id = d.member_id and m.status = 'active'
       and d.daily_enabled and d.daily_time <= $2
       and (d.last_daily_on is null or d.last_daily_on < $1::date)
     returning d.member_id, m.org_id`,
    [now.date, now.time],
  );
  return rows;
}

async function sendDailyTasks(claimed, now) {
  const risks = new Map();
  for (const { member_id: memberId, org_id: orgId } of claimed) {
    if (!risks.has(orgId)) risks.set(orgId, await orgRisk(orgId));
    await notifyMembers({
      orgId,
      memberIds: [memberId],
      type: 'digest',
      title: `오늘의 업무 (${label(now.date)})`,
      body: tasksBody(await memberOpenTasks(memberId), risks.get(orgId)),
      link: '/memo?view=today',
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
    await sendDailyTasks(await claimDaily(now), now);
  } catch (err) {
    console.error('digest run failed', err);
  } finally {
    running = false;
  }
}

export function scheduleDigests() {
  setInterval(runDigests, CHECK_EVERY_MS).unref();
}
