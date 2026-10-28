// 모델별 하루 사용량. Gemini 의 하루 한도(RPD)는 미국 태평양 시간 자정에 초기화되므로
// 같은 기준으로 센다. 한 API 키를 모든 기관이 함께 쓰므로 기관 구분 없이 합산한다.

import { query } from '../../db.js';
import { modelOptions } from './model.js';

const PT = 'America/Los_Angeles';

/** 지금 시각 기준 가장 최근의 태평양 시간 자정(UTC Date)과 다음 자정. */
export function quotaWindow(now = new Date()) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', { timeZone: PT, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
      .formatToParts(now)
      .map((p) => [p.type, p.value]),
  );
  const sinceMidnightMs = ((Number(parts.hour) * 60 + Number(parts.minute)) * 60 + Number(parts.second)) * 1000 + now.getMilliseconds();
  const start = new Date(now.getTime() - sinceMidnightMs);
  // DST 전환일에도 다음 날 같은 시각이 대략 맞도록 24시간 뒤를 쓴다(±1시간 오차 허용).
  return { start, end: new Date(start.getTime() + 86400_000) };
}

export async function recordUsage({ orgId, memberId, model, outcome, usage }) {
  await query(
    `insert into ai_usage (org_id, member_id, model, outcome, prompt_tokens, completion_tokens)
     values ($1, $2, $3, $4, $5, $6)`,
    [orgId ?? null, memberId ?? null, model, outcome, usage?.prompt_tokens ?? null, usage?.completion_tokens ?? null],
  );
}

/**
 * 모델 목록 + 오늘 사용량. 429 는 분당 한도일 수도 있어 하루 소진으로 단정하지 않고,
 * 그 모델의 마지막 호출이 429 였을 때만 limited 로 알린다(다음 성공 호출이 오면 풀린다).
 */
export async function modelsWithUsage(now = new Date()) {
  const { start, end } = quotaWindow(now);
  const { rows } = await query(
    `select model,
            count(*) filter (where outcome <> 'quota')::int as used,
            max(created_at) filter (where outcome = 'quota') as quota_at,
            max(created_at) filter (where outcome <> 'quota') as last_ok_at,
            (coalesce(sum(prompt_tokens), 0) + coalesce(sum(completion_tokens), 0))::int as tokens
       from ai_usage where created_at >= $1 group by model`,
    [start],
  );
  const byModel = new Map(rows.map((r) => [r.model, r]));
  return {
    resetsAt: end.toISOString(),
    models: modelOptions().map((m) => {
      const u = byModel.get(m.id);
      const used = u?.used ?? 0;
      const limited = Boolean(u?.quota_at) && (!u.last_ok_at || new Date(u.quota_at) > new Date(u.last_ok_at));
      return {
        id: m.id,
        label: m.label,
        description: m.description,
        dailyLimit: m.dailyLimit,
        usedToday: used,
        tokensToday: u?.tokens ?? 0,
        limited,
        remaining: Math.max(0, m.dailyLimit - used),
      };
    }),
  };
}
