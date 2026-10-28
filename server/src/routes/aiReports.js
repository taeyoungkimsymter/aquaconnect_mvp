import { Router } from 'express';

import { requireAuth } from '../auth.js';
import { query } from '../db.js';
import { orgIdForMember } from '../lib/orgScope.js';
import { draftFarmReport } from '../lib/ai/farmReport.js';
import { AiError, MODEL_CATALOG, modelStatus } from '../lib/ai/model.js';
import { modelsWithUsage, recordUsage } from '../lib/ai/usage.js';

export const aiReportsRouter = Router();
aiReportsRouter.use(requireAuth);

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_PERIOD_DAYS = 92;
const MAX_MEMOS = 300;

function toAiReportJson(row, { full = true } = {}) {
  return {
    id: row.id,
    farmId: row.farm_id,
    periodStart: kstDateOnly(row.period_start),
    periodEnd: kstDateOnly(row.period_end),
    status: row.status,
    model: row.model,
    memoCount: row.memo_count,
    commentCount: row.comment_count,
    checkCount: Array.isArray(row.checks) ? row.checks.length : 0,
    edited: row.body !== row.ai_body,
    createdByName: row.created_by_name,
    createdAt: row.created_at,
    editedByName: row.edited_by_name,
    editedAt: row.edited_at,
    confirmedByName: row.confirmed_by_name,
    confirmedAt: row.confirmed_at,
    ...(full
      ? {
          body: row.body,
          aiBody: row.ai_body,
          checks: row.checks ?? [],
          memos: (row.input_snapshot?.memos ?? []).map((m) => ({ id: m.id, date: m.date, kind: m.kind, author: m.author, body: m.body })),
        }
      : {}),
  };
}

// pg returns `date` columns as local-midnight Date objects; format them back
// to the plain YYYY-MM-DD that was stored.
function kstDateOnly(value) {
  if (typeof value === 'string') return value.slice(0, 10);
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

const kstStart = (date) => new Date(`${date}T00:00:00+09:00`);

async function loadFarm(orgId, farmId) {
  const { rows } = await query('select * from farms where org_id = $1 and id = $2', [orgId, farmId]);
  return rows[0] ?? null;
}

async function loadReport(orgId, id) {
  const { rows } = await query('select * from ai_reports where org_id = $1 and id = $2', [orgId, id]);
  return rows[0] ?? null;
}

async function memberName(memberId) {
  const { rows } = await query('select name from members where id = $1', [memberId]);
  return rows[0]?.name ?? '';
}

// 연결 상태 + 고를 수 있는 모델과 모델별 오늘 사용량(이 서버가 보낸 요청 기준).
aiReportsRouter.get('/status', async (req, res) => {
  const { configured, model, note } = modelStatus();
  const usage = await modelsWithUsage();
  res.json({ configured, model, note, ...usage });
});

aiReportsRouter.get('/farm/:farmId', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const farm = await loadFarm(orgId, req.params.farmId);
  if (!farm) return res.status(404).json({ error: '양식장을 찾을 수 없습니다.' });
  const { rows } = await query('select * from ai_reports where farm_id = $1 order by created_at desc limit 50', [farm.id]);
  res.json(rows.map((r) => toAiReportJson(r, { full: false })));
});

aiReportsRouter.get('/:id', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const row = await loadReport(orgId, req.params.id);
  if (!row) return res.status(404).json({ error: 'AI 리포트를 찾을 수 없습니다.' });
  res.json(toAiReportJson(row));
});

// Body: { from: 'YYYY-MM-DD', to: 'YYYY-MM-DD', memoIds?: string[], includeComments?: boolean }
// memoIds omitted → every memo of the farm in the period.
aiReportsRouter.post('/farm/:farmId', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const farm = await loadFarm(orgId, req.params.farmId);
  if (!farm) return res.status(404).json({ error: '양식장을 찾을 수 없습니다.' });

  const { from, to, memoIds, includeComments = true, model } = req.body ?? {};
  if (model != null && !MODEL_CATALOG.some((m) => m.id === model)) return res.status(400).json({ error: '고를 수 없는 AI 모델입니다.' });
  if (!DATE_RE.test(from ?? '') || !DATE_RE.test(to ?? '') || from > to) {
    return res.status(400).json({ error: '기간(from, to)을 YYYY-MM-DD 형식으로 올바르게 지정해 주세요.' });
  }
  const start = kstStart(from);
  const endExclusive = new Date(kstStart(to).getTime() + 86400_000);
  const days = Math.round((endExclusive - start) / 86400_000);
  if (days > MAX_PERIOD_DAYS) return res.status(400).json({ error: `기간은 최대 ${MAX_PERIOD_DAYS}일까지 고를 수 있습니다.` });
  if (!modelStatus().configured) return res.status(503).json({ error: 'AI가 연결되지 않았습니다. 서버에 MODEL_API_KEY 를 설정해 주세요.' });

  const { rows: periodMemos } = await query(
    `select id, content, tags, author_type, author_name, created_at from memos
      where farm_id = $1 and created_at >= $2 and created_at < $3 order by created_at`,
    [farm.id, start, endExclusive],
  );
  let selected = periodMemos;
  if (Array.isArray(memoIds)) {
    const wanted = new Set(memoIds.map(String));
    selected = periodMemos.filter((m) => wanted.has(m.id));
  }
  if (selected.length === 0) return res.status(400).json({ error: '선택한 기간에 리포트에 넣을 메모가 없습니다.' });
  if (selected.length > MAX_MEMOS) return res.status(400).json({ error: `메모는 한 번에 ${MAX_MEMOS}건까지 넣을 수 있습니다. 기간을 줄여 주세요.` });

  let comments = [];
  if (includeComments) {
    const ids = new Set(selected.map((m) => m.id));
    const { rows } = await query(
      `select c.memo_id, c.author_name, c.content, c.created_at from memo_comments c
         join memos mm on mm.id = c.memo_id
        where mm.farm_id = $1 and mm.created_at >= $2 and mm.created_at < $3 order by c.created_at`,
      [farm.id, start, endExclusive],
    );
    comments = rows.filter((c) => ids.has(c.memo_id));
  }

  const prevStart = new Date(start.getTime() - days * 86400_000);
  const { rows: prevMemos } = await query(
    `select id, content, tags, author_type, author_name, created_at from memos
      where farm_id = $1 and created_at >= $2 and created_at < $3 order by created_at limit $4`,
    [farm.id, prevStart, start, MAX_MEMOS],
  );

  let result;
  try {
    result = await draftFarmReport({
      farm,
      from,
      to,
      memos: selected,
      comments,
      prevMemos,
      candidates: periodMemos.length,
      model: model ?? undefined,
      onResult: (r) => recordUsage({ orgId, memberId: req.memberId, ...r }),
    });
  } catch (err) {
    if (err instanceof AiError) return res.status(err.status).json({ error: err.message });
    throw err;
  }

  const name = await memberName(req.memberId);
  const { rows } = await query(
    `insert into ai_reports
       (org_id, farm_id, period_start, period_end, model, prompt_version, memo_count, comment_count,
        input_snapshot, raw_draft, draft, checks, ai_body, body, created_by, created_by_name)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13,$14,$15)
     returning *`,
    [
      orgId,
      farm.id,
      from,
      to,
      result.model,
      result.promptVersion,
      selected.length,
      result.snapshot.comments.length,
      JSON.stringify(result.snapshot),
      JSON.stringify(result.raw),
      JSON.stringify(result.draft),
      JSON.stringify(result.checks),
      result.body,
      req.memberId,
      name,
    ],
  );
  res.status(201).json(toAiReportJson(rows[0]));
});

// 전문가 수정. 확정된 리포트는 확정을 취소한 뒤에만 고칠 수 있다.
aiReportsRouter.put('/:id', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const row = await loadReport(orgId, req.params.id);
  if (!row) return res.status(404).json({ error: 'AI 리포트를 찾을 수 없습니다.' });
  if (row.status === 'confirmed') return res.status(409).json({ error: '확정된 리포트입니다. 확정을 취소한 뒤 수정해 주세요.' });
  const body = String(req.body?.body ?? '').trim();
  if (!body) return res.status(400).json({ error: '리포트 내용이 비어 있습니다.' });
  const { rows } = await query(
    'update ai_reports set body = $2, edited_by_name = $3, edited_at = now() where id = $1 returning *',
    [row.id, body, await memberName(req.memberId)],
  );
  res.json(toAiReportJson(rows[0]));
});

aiReportsRouter.post('/:id/confirm', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const row = await loadReport(orgId, req.params.id);
  if (!row) return res.status(404).json({ error: 'AI 리포트를 찾을 수 없습니다.' });
  const { rows } = await query(
    `update ai_reports set status = 'confirmed', confirmed_by_name = $2, confirmed_at = now() where id = $1 returning *`,
    [row.id, await memberName(req.memberId)],
  );
  res.json(toAiReportJson(rows[0]));
});

aiReportsRouter.post('/:id/unconfirm', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const row = await loadReport(orgId, req.params.id);
  if (!row) return res.status(404).json({ error: 'AI 리포트를 찾을 수 없습니다.' });
  const { rows } = await query(
    `update ai_reports set status = 'draft', confirmed_by_name = null, confirmed_at = null where id = $1 returning *`,
    [row.id],
  );
  res.json(toAiReportJson(rows[0]));
});

aiReportsRouter.delete('/:id', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const row = await loadReport(orgId, req.params.id);
  if (!row) return res.status(404).json({ error: 'AI 리포트를 찾을 수 없습니다.' });
  await query('delete from ai_reports where id = $1', [row.id]);
  res.status(204).end();
});
