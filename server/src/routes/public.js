import { Router } from 'express';

import { query } from '../db.js';
import { toFarmJson } from './farms.js';
import { buildAndPersistReport, latestReportRow, toReportJson } from './reports.js';

// No requireAuth here on purpose: this is what a farm owner opens from a
// share link on their own phone, with no AquaConnect account.
export const publicRouter = Router();

const NOT_FOUND = { error: '링크가 만료되었거나 존재하지 않습니다.' };

async function activeLink(token) {
  const { rows } = await query('select * from share_links where token = $1', [token]);
  const link = rows[0];
  const isActive = link && !link.revoked_at && (!link.expires_at || new Date(link.expires_at) > new Date());
  return isActive ? link : null;
}

// Actions are created lazily from the report's follow-ups the first time a
// report is shared, so older reports keep working without a backfill.
async function ensureActions(reportRow) {
  const { rows } = await query('select * from report_actions where report_id = $1 order by position', [reportRow.id]);
  if (rows.length > 0) return rows;
  for (const [i, title] of (reportRow.follow_ups ?? []).entries()) {
    await query('insert into report_actions (report_id, position, title) values ($1, $2, $3)', [reportRow.id, i, title]);
  }
  const { rows: created } = await query('select * from report_actions where report_id = $1 order by position', [reportRow.id]);
  return created;
}

const LEVEL = { good: 'good', warning: 'watch', danger: 'urgent' };

publicRouter.get('/reports/:token', async (req, res) => {
  const link = await activeLink(req.params.token);
  if (!link) return res.status(404).json(NOT_FOUND);

  const { rows: farmRows } = await query(
    'select f.*, m.name as assigned_member_name from farms f left join members m on m.id = f.assigned_member_id where f.id = $1',
    [link.farm_id],
  );
  const farm = farmRows[0];
  if (!farm) return res.status(404).json(NOT_FOUND);

  let reportRow = await latestReportRow(farm.id);
  if (!reportRow) {
    await buildAndPersistReport(farm);
    reportRow = await latestReportRow(farm.id);
  }
  const report = toReportJson(reportRow);
  const actions = await ensureActions(reportRow);
  const { rows: orgRows } = await query('select name, phone from organizations where id = $1', [farm.org_id]);
  const org = orgRows[0] ?? {};

  // Shape consumed by the farm-side page (see SharedReportView in Flutter).
  const shared = {
    farmName: farm.name,
    species: reportRow.species ?? '',
    orgName: org.name ?? '',
    sharedAt: link.created_at,
    overallStatus: { level: LEVEL[report.riskLevel] ?? 'good', summary: report.headline },
    metrics: [
      { label: '주간 폐사', value: String(report.weeklyMortality), unit: '마리', note: '최근 7일 누적' },
      { label: '평균 수온', value: report.avgTemp.toFixed(1), unit: '℃', note: report.periodLabel },
      { label: '최근 방문', value: String(report.lastVisitDays), unit: '일 전', note: farm.assigned_member_name ?? '담당 관리사' },
      { label: '현재 수온', value: Number(farm.water_temp).toFixed(1), unit: '℃', note: farm.nearest_station_name },
    ],
    flaggedPhotos: reportRow.flagged_photos ?? [],
    diagnosis: reportRow.diagnosis || [report.summary, ...report.findings.map((f) => `• ${f}`)].join('\n'),
    actions: actions.map((a) => ({ id: a.id, title: a.title, sub: a.sub, done: a.done })),
    videoUrl: reportRow.video_url,
    videoDuration: reportRow.video_duration,
    contactPhone: org.phone ?? null,
  };

  res.json({
    farm: toFarmJson(farm),
    report,
    shared,
    link: { id: link.id, farmId: link.farm_id, token: link.token, createdAt: link.created_at, expiresAt: link.expires_at, revokedAt: link.revoked_at },
  });
});

// Farm checks/unchecks a recommended action. Scoped to the link's farm so a
// token can never touch another farm's report.
publicRouter.patch('/reports/:token/actions/:actionId', async (req, res) => {
  const link = await activeLink(req.params.token);
  if (!link) return res.status(404).json(NOT_FOUND);
  if (typeof req.body?.done !== 'boolean') return res.status(400).json({ error: 'done 값이 필요합니다.' });

  const { rows } = await query(
    `update report_actions a
        set done = $3, done_at = case when $3 then now() else null end
       from reports r
      where a.id = $2 and a.report_id = r.id and r.farm_id = $1
      returning a.id, a.done`,
    [link.farm_id, req.params.actionId, req.body.done],
  );
  if (!rows[0]) return res.status(404).json({ error: '조치사항을 찾을 수 없습니다.' });
  res.json(rows[0]);
});

// Memo left from the share page. Stored as an inquiry and mirrored into the
// institute's memo feed (author_type 'farm') so staff see it in the app.
publicRouter.post('/reports/:token/inquiries', async (req, res) => {
  const link = await activeLink(req.params.token);
  if (!link) return res.status(404).json(NOT_FOUND);

  const message = String(req.body?.message ?? '').trim();
  if (!message) return res.status(400).json({ error: '문의 내용을 입력해주세요.' });
  if (message.length > 500) return res.status(400).json({ error: '문의 내용은 500자 이내로 입력해주세요.' });

  const { rows: farmRows } = await query('select org_id, name from farms where id = $1', [link.farm_id]);
  const farm = farmRows[0];
  if (!farm) return res.status(404).json(NOT_FOUND);

  await query('insert into inquiries (share_link_id, farm_id, message) values ($1, $2, $3)', [link.id, link.farm_id, message]);
  await query(
    `insert into memos (org_id, farm_id, author_type, author_name, content, tags)
     values ($1, $2, 'farm', $3, $4, $5)`,
    [farm.org_id, link.farm_id, farm.name, message, ['문의']],
  );
  res.status(201).json({ ok: true });
});
