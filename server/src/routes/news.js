import { Router } from 'express';

import { requireAuth } from '../auth.js';
import { query } from '../db.js';
import { NEWS_CATEGORIES } from '../lib/news/classify.js';

// 수산 뉴스 — 서버가 미리 수집해 둔 소식을 읽기만 합니다(외부 사이트는 건드리지 않음).
// 숨김 처리된 소식은 목록·상세 어디에도 나오지 않습니다.
export const newsRouter = Router();
newsRouter.use(requireAuth);

const MAX_PAGE_SIZE = 30;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const SOURCE_NAMES = { mof_press: '해양수산부', nifs_press: '국립수산과학원' };

export function toNewsJson(row) {
  return {
    id: row.id,
    source: row.source,
    sourceName: SOURCE_NAMES[row.source] ?? row.source,
    title: row.title,
    url: row.url,
    publishedAt: row.published_at, // 원문 게시일 — 모르면 null
    category: row.category,
    summary: row.summary,
    regions: row.regions ?? [],
    species: row.species ?? [],
  };
}

// 최신순은 원문 게시일 기준(게시일을 모르는 소식은 맨 뒤).
newsRouter.get('/', async (req, res) => {
  const category = typeof req.query.category === 'string' ? req.query.category : null;
  if (category && category !== 'all' && !NEWS_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: '분류 값이 올바르지 않습니다.' });
  }
  const page = Math.max(1, Number.parseInt(req.query.page, 10) || 1);
  const pageSize = Math.min(MAX_PAGE_SIZE, Math.max(1, Number.parseInt(req.query.pageSize, 10) || 20));

  const { rows } = await query(
    `select * from news_items
     where is_published and ($1::text is null or category = $1)
     order by published_at desc nulls last, id
     limit $2 offset $3`,
    [category && category !== 'all' ? category : null, pageSize + 1, (page - 1) * pageSize],
  );
  res.json({ items: rows.slice(0, pageSize).map(toNewsJson), page, pageSize, hasMore: rows.length > pageSize });
});

newsRouter.get('/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: '소식을 찾을 수 없습니다.' });
  const { rows } = await query('select * from news_items where id = $1 and is_published', [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: '소식을 찾을 수 없습니다.' });
  res.json(toNewsJson(rows[0]));
});
