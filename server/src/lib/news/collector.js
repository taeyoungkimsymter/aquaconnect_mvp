import { pool, query } from '../../db.js';
import { classifyNews } from './classify.js';
import { currentSlot } from './schedule.js';
import { BACKFILL_WINDOW_MS, NEWS_SOURCES, normalizeUrl } from './sources.js';

// 수산 뉴스 수집 작업. 앱을 열 때가 아니라, 서버가 정해진 시각에만 외부 사이트를 읽습니다.
//
//  · 매일 한국 시간 08:00 · 14:00 · 20:00 (scheduleNewsCollection)
//  · 같은 시각에 여러 서버가 떠 있어도 한 곳만 실행 (app_config 슬롯 선점 + DB advisory lock)
//  · 한 출처가 실패해도 다른 출처는 계속 — 실패해도 기존 뉴스는 그대로 보입니다.

const CHECK_EVERY_MS = 60 * 1000;
const LOCK_KEY = 5_150_001; // pg_try_advisory_lock 키(임의의 고정값)
const SLOT_CONFIG_KEY = 'news_last_slot';

let runningHere = false;

/**
 * 이 서버가 [slot]을 맡습니다 — 이미 누가 맡았거나 더 늦은 슬롯이 처리됐다면 false.
 * 조건부 upsert 자체가 선점이라 두 서버가 동시에 보내도 한 곳만 true입니다.
 */
export async function claimSlot(slot) {
  const { rows } = await query(
    `insert into app_config (key, value) values ($1, $2)
     on conflict (key) do update set value = excluded.value where app_config.value < excluded.value
     returning value`,
    [SLOT_CONFIG_KEY, slot],
  );
  return rows.length === 1;
}

/** 출처 하나의 게시물들을 저장합니다. 관련 없는 소식은 거르고, 이미 있는 소식은 갱신합니다. */
export async function saveItems(source, items, { now = new Date(), refresh = true } = {}) {
  const cutoff = now.getTime() - BACKFILL_WINDOW_MS;
  let saved = 0;
  for (const item of items) {
    // 게시일을 아는데 30일보다 오래됐으면 새로 들이지 않습니다. 모르면(null) 임의로 판단하지 않고 분류만 봅니다.
    if (item.publishedAt && item.publishedAt.getTime() < cutoff) continue;
    const c = classifyNews(item);
    if (!c.relevant) continue;

    // 숨긴 소식(is_published)과 관리자가 고친 분류·소개(edited_by_admin)는 건드리지 않습니다.
    const { rowCount } = await query(
      `insert into news_items (source, source_item_id, title, url, url_key, published_at, fetched_at, category, summary, regions, species)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       on conflict (url_key) do ${
         refresh
           ? `update set
         source_item_id = coalesce(excluded.source_item_id, news_items.source_item_id),
         title = excluded.title,
         url = excluded.url,
         published_at = coalesce(excluded.published_at, news_items.published_at),
         fetched_at = excluded.fetched_at,
         category = case when news_items.edited_by_admin then news_items.category else excluded.category end,
         summary = case when news_items.edited_by_admin then news_items.summary else coalesce(excluded.summary, news_items.summary) end,
         regions = excluded.regions,
         species = excluded.species`
           : 'nothing'
       }`,
      [
        source,
        item.sourceItemId ?? null,
        item.title,
        item.url,
        normalizeUrl(item.url),
        item.publishedAt ?? null,
        now,
        c.category,
        item.summary ?? null,
        c.regions,
        c.species,
      ],
    );
    saved += rowCount;
  }
  return saved;
}

async function recordResult(source, { ok, error = null, fetched = null, saved = null }) {
  await query(
    `insert into news_sources (source, name, last_attempt_at, last_success_at, last_error, last_fetched_count, last_saved_count)
     values ($1, $2, now(), case when $3 then now() end, $4, $5, $6)
     on conflict (source) do update set
       name = excluded.name,
       last_attempt_at = now(),
       last_success_at = case when $3 then now() else news_sources.last_success_at end,
       last_error = $4,
       last_fetched_count = case when $3 then $5 else news_sources.last_fetched_count end,
       last_saved_count = case when $3 then $6 else news_sources.last_saved_count end`,
    [source.id, source.name, ok, error, fetched, saved],
  );
}

/**
 * 모든 출처를 한 번 수집합니다. 던지지 않고 출처별 결과를 돌려줍니다.
 * @param {{backfill?: boolean, sources?: typeof NEWS_SOURCES, fetchImpl?: typeof fetch}} options
 *   backfill: 최근 30일치를 목록 페이지에서 보충. 생략하면 "이 출처를 아직 성공한 적 없을 때"만 자동으로 켭니다.
 */
export async function runNewsCollection({ backfill, sources = NEWS_SOURCES, fetchImpl } = {}) {
  if (runningHere) return { skipped: '이미 수집 중입니다.', results: [] };
  runningHere = true;
  const lockClient = await pool.connect();
  try {
    const { rows } = await lockClient.query('select pg_try_advisory_lock($1) as ok', [LOCK_KEY]);
    if (!rows[0].ok) return { skipped: '다른 서버가 수집 중입니다.', results: [] };

    const results = [];
    for (const source of sources) {
      try {
        const { rows: status } = await query('select last_success_at from news_sources where source = $1', [source.id]);
        const firstTime = !status[0]?.last_success_at;
        const doBackfill = backfill ?? firstTime;
        const items = await source.fetchItems({ backfill: doBackfill, fetchImpl });
        const saved = await saveItems(source.id, items);
        await recordResult(source, { ok: true, fetched: items.length, saved });
        results.push({ source: source.id, ok: true, fetched: items.length, saved, backfill: doBackfill });
      } catch (err) {
        const message = String(err?.message ?? err).slice(0, 500);
        console.error(`news collection failed (${source.id})`, message);
        try {
          await recordResult(source, { ok: false, error: message });
        } catch (dbErr) {
          console.error('news status write failed', dbErr);
        }
        results.push({ source: source.id, ok: false, error: message });
      }
    }
    return { results };
  } finally {
    try {
      await lockClient.query('select pg_advisory_unlock($1)', [LOCK_KEY]);
    } finally {
      lockClient.release();
      runningHere = false;
    }
  }
}

/** 1분마다 확인해서, 새 슬롯이 오면 한 번 수집합니다. NEWS_COLLECTION_ENABLED=false 이면 끕니다. */
export function scheduleNewsCollection() {
  if (process.env.NEWS_COLLECTION_ENABLED === 'false') {
    console.log('news collection disabled (NEWS_COLLECTION_ENABLED=false)');
    return;
  }
  const tick = async () => {
    try {
      if (await claimSlot(currentSlot())) await runNewsCollection();
    } catch (err) {
      console.error('news schedule tick failed', err);
    }
  };
  tick();
  setInterval(tick, CHECK_EVERY_MS).unref();
}
