-- Farm-side shared report page: org contact, richer report content,
-- per-report action checklist, and inquiries sent from the share link.

alter table organizations add column phone text;

alter table reports
  add column species text not null default '',
  add column diagnosis text not null default '',
  add column flagged_photos jsonb not null default '[]',  -- [{url,label,needsAttention}]
  add column video_url text,
  add column video_duration text;

create table report_actions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references reports(id) on delete cascade,
  position integer not null default 0,
  title text not null,
  sub text not null default '',
  done boolean not null default false,
  done_at timestamptz
);
create index report_actions_report_id_idx on report_actions(report_id, position);

create table inquiries (
  id uuid primary key default gen_random_uuid(),
  share_link_id uuid not null references share_links(id) on delete cascade,
  farm_id uuid not null references farms(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now()
);
