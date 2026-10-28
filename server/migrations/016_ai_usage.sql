-- AI 모델 호출 기록 — 앱에서 모델별 "오늘 남은 횟수"를 보여 주는 데 쓴다.
-- Gemini API 는 남은 한도를 알려 주지 않으므로, 이 서버가 보낸 요청을 직접 센다.
-- outcome: ok(응답 받음) / quota(429 — 한도 소진) / error(그 밖의 오류 응답)
create table ai_usage (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id) on delete set null,
  member_id uuid references members(id) on delete set null,
  model text not null,
  outcome text not null check (outcome in ('ok', 'quota', 'error')),
  prompt_tokens integer,
  completion_tokens integer,
  created_at timestamptz not null default now()
);
create index ai_usage_model_created_at_idx on ai_usage(model, created_at desc);
