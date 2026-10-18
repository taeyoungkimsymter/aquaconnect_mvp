-- 댓글 첨부(사진·파일)와 사람 호출(@멘션).
-- mentions: [{id, name}] — who the comment called, as written (names are a snapshot).
alter table memo_comments add column mentions jsonb not null default '[]'::jsonb;

create table memo_comment_attachments (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references memo_comments(id) on delete cascade,
  kind text not null check (kind in ('photo', 'file')),
  file_name text not null,
  content_type text not null,
  size integer not null,
  data bytea not null,
  created_at timestamptz not null default now()
);
create index memo_comment_attachments_comment_idx on memo_comment_attachments(comment_id, created_at);
