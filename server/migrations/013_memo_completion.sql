-- 메모 완료: any memo can be checked off (not only 할일 ones). NULL = not done.
alter table memos add column completed_at timestamptz;

-- 하루 요약 → 미완료된 업무, 주간 요약 → 오늘 해야할 일. Both now go out daily at
-- the member's chosen time, which defaults to 08:30 KST. (digest_settings keeps
-- its column names: daily_* = 미완료된 업무, weekly_enabled/last_weekly_on = 오늘 해야할 일.)
alter table digest_settings alter column daily_time set default '08:30';
update digest_settings set daily_time = '08:30' where daily_time = '16:00';
