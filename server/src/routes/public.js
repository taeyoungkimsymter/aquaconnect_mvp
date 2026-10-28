import { Router } from 'express';

import { query } from '../db.js';
import { notifyMembers } from '../lib/notify.js';
import { loadFarmRows, toFarmJson } from './farms.js';
import { buildAndPersistReport, latestReportRow, toReportJson } from './reports.js';

// No requireAuth here on purpose: this is what a farm owner opens from a
// share link on their own phone, with no AquaConnect account.
export const publicRouter = Router();

publicRouter.get('/reports/:token', async (req, res) => {
  const { rows } = await query('select * from share_links where token = $1', [req.params.token]);
  const link = rows[0];

  const isActive = link && !link.revoked_at && (!link.expires_at || new Date(link.expires_at) > new Date());
  if (!isActive) return res.status(404).json({ error: '링크가 만료되었거나 존재하지 않습니다.' });

  const [farm] = await loadFarmRows('f.id = $1', [link.farm_id]);
  if (!farm) return res.status(404).json({ error: '링크가 만료되었거나 존재하지 않습니다.' });

  let reportRow = await latestReportRow(farm.id);
  const report = reportRow ? toReportJson(reportRow) : await buildAndPersistReport(farm);

  const { rows: extraRows } = await query(
    `select o.name as organization_name, m.phone as assigned_member_phone
     from organizations o left join members m on m.id = $2
     where o.id = $1`,
    [farm.org_id, farm.assigned_member_id],
  );

  res.json({
    organizationName: extraRows[0]?.organization_name ?? null,
    assignedMemberPhone: extraRows[0]?.assigned_member_phone ?? null,
    farm: toFarmJson(farm),
    report,
    link: { id: link.id, farmId: link.farm_id, token: link.token, createdAt: link.created_at, expiresAt: link.expires_at, revokedAt: link.revoked_at },
  });
});

const INQUIRY_MAX_LENGTH = 500;
// No login on this route, so cap how fast one link can post.
const INQUIRIES_PER_LINK_PER_HOUR = 10;

// 문의 from the farm's shared report page. Stored, mirrored into the memo
// feed (author_type 'farm', tag 문의) and pushed to the institute.
publicRouter.post('/reports/:token/inquiries', async (req, res) => {
  const { rows } = await query('select * from share_links where token = $1', [req.params.token]);
  const link = rows[0];
  const isActive = link && !link.revoked_at && (!link.expires_at || new Date(link.expires_at) > new Date());
  if (!isActive) return res.status(404).json({ error: '링크가 만료되었거나 존재하지 않습니다.' });

  const message = typeof req.body?.message === 'string' ? req.body.message.trim() : '';
  if (!message) return res.status(400).json({ error: '문의 내용을 입력해주세요.' });
  if (message.length > INQUIRY_MAX_LENGTH) {
    return res.status(400).json({ error: `문의 내용은 ${INQUIRY_MAX_LENGTH}자 이내로 입력해주세요.` });
  }

  const { rows: recent } = await query(
    "select count(*)::int as c from inquiries where share_link_id = $1 and created_at > now() - interval '1 hour'",
    [link.id],
  );
  if (recent[0].c >= INQUIRIES_PER_LINK_PER_HOUR) {
    return res.status(429).json({ error: '문의가 너무 많습니다. 잠시 후 다시 시도해주세요.' });
  }

  const { rows: farmRows } = await query('select id, org_id, name from farms where id = $1', [link.farm_id]);
  const farm = farmRows[0];
  if (!farm) return res.status(404).json({ error: '링크가 만료되었거나 존재하지 않습니다.' });

  await query('insert into inquiries (share_link_id, farm_id, message) values ($1, $2, $3)', [link.id, farm.id, message]);
  const { rows: memoRows } = await query(
    `insert into memos (org_id, farm_id, author_type, author_name, content, tags)
     values ($1, $2, 'farm', $3, $4, $5) returning id`,
    [farm.org_id, farm.id, `어가 · ${farm.name}`, message, ['문의']],
  );

  const preview = message.replace(/\s+/g, ' ');
  await notifyMembers({
    orgId: farm.org_id,
    type: 'inquiry',
    title: `어가 문의 · ${farm.name}`,
    body: preview.length > 80 ? `${preview.slice(0, 80)}…` : preview,
    link: `/memo?memo=${memoRows[0].id}`,
  });

  res.status(201).json({ ok: true });
});
