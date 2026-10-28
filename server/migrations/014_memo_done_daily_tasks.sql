-- 메모 완료: a task memo (할일 / 담당 / 호출) marked done, and by whom.
alter table memos add column done_at timestamptz;
alter table memos add column done_by_member_id uuid references members(id) on delete set null;
alter table memos add column done_by_name text;

-- 하루 요약 / 주간 요약 → 오늘의 업무: a morning "what do I do today" reminder,
-- so the default moves from 16:00 to 08:00 (rows still on the old default
-- move with it).
alter table digest_settings alter column daily_time set default '08:00';
update digest_settings set daily_time = '08:00' where daily_time = '16:00';
