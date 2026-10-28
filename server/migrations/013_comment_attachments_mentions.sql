-- 댓글 첨부: photos (downscaled JPEG from the app) and arbitrary files.
create table memo_comment_attachments (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references memo_comments(id) on delete cascade,
  kind text not null check (kind in ('photo', 'file')),
  file_name text not null default '',
  content_type text not null,
  size_bytes integer not null,
  data bytea not null,
  created_at timestamptz not null default now()
);
create index memo_comment_attachments_comment_id_idx on memo_comment_attachments(comment_id, created_at);

-- 댓글 호출(@): the members a comment calls in. Kept as rows (not just text)
-- so "나를 호출한 메모" can be looked up per member.
create table memo_comment_mentions (
  comment_id uuid not null references memo_comments(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  primary key (comment_id, member_id)
);
create index memo_comment_mentions_member_id_idx on memo_comment_mentions(member_id);

alter table notifications drop constraint notifications_type_check;
alter table notifications add constraint notifications_type_check
  check (type in ('risk', 'memo', 'test', 'inquiry', 'comment', 'digest', 'mention'));
