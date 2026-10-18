-- 수산 뉴스: 공식 기관(해양수산부·국립수산과학원) 소식을 서버가 정해진 시각에 수집해 저장합니다.
-- 앱은 이 표만 읽고, 외부 사이트는 앱에서 직접 부르지 않습니다.
create table news_items (
  id uuid primary key default gen_random_uuid(),
  source text not null,                -- 'mof_press' | 'nifs_press'
  source_item_id text,                 -- 출처 측 게시물 ID(제공되는 경우)
  title text not null,
  url text not null,                   -- 공식 원문 주소
  url_key text not null unique,        -- 정규화한 원문 주소 — 중복 방지
  published_at timestamptz,            -- 원문 게시일. 확인할 수 없으면 NULL (오늘 날짜로 채우지 않음)
  fetched_at timestamptz not null default now(),  -- 마지막으로 수집된 시각
  category text not null check (category in ('disease', 'environment', 'support', 'policy')),
  summary text,                        -- 짧은 소개(있는 경우)
  regions text[] not null default '{}',
  species text[] not null default '{}',
  is_published boolean not null default true,     -- 관리자가 숨기면 false — 재수집해도 되살리지 않음
  edited_by_admin boolean not null default false  -- true면 재수집이 분류·소개를 덮어쓰지 않음
);
create unique index news_items_source_item_idx on news_items (source, source_item_id) where source_item_id is not null;
create index news_items_list_idx on news_items (published_at desc nulls last, id);

-- 출처별 마지막 수집 결과(운영자 확인용). 실패해도 기존 뉴스는 그대로 보입니다.
create table news_sources (
  source text primary key,
  name text not null,
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  last_error text,
  last_fetched_count integer,   -- 마지막 성공 수집에서 본 게시물 수
  last_saved_count integer      -- 그중 관련 소식으로 저장·갱신된 수
);
