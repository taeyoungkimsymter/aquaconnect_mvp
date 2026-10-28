-- AI 관리 리포트(symterAI 이식): 선택한 기간·메모로 AI 가 초안을 쓰고, 전문가가 고쳐 확정한다.
-- input_snapshot 은 생성 당시 AI 에게 보낸 입력(메모·댓글 원문 포함)을 그대로 남긴다 —
-- 나중에 메모가 수정·삭제돼도 리포트가 무엇을 근거로 썼는지 확인할 수 있다.
create table ai_reports (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  farm_id uuid not null references farms(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft', 'confirmed')),
  model text not null,
  prompt_version text not null,
  memo_count integer not null default 0,
  comment_count integer not null default 0,
  input_snapshot jsonb not null,
  raw_draft jsonb not null,
  draft jsonb not null,
  checks jsonb not null default '[]',
  ai_body text not null,
  body text not null,
  created_by uuid references members(id) on delete set null,
  created_by_name text not null default '',
  edited_by_name text,
  edited_at timestamptz,
  confirmed_by_name text,
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);
create index ai_reports_farm_id_created_at_idx on ai_reports(farm_id, created_at desc);
