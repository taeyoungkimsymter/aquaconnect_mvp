import crypto from 'node:crypto';
import { Router } from 'express';

import { hashPassword } from '../auth.js';
import { query } from '../db.js';
import { diffFields, recordAudit } from '../lib/audit.js';
import { NEWS_CATEGORIES } from '../lib/news/classify.js';
import { runNewsCollection } from '../lib/news/collector.js';
import { digitsOnly, normalizeEmail, validateEmail, validatePassword, validatePhone } from '../lib/validators.js';
import { toNewsJson } from './news.js';
import { refreshReportQuietly } from './reports.js';

// 관리자 대시보드(admin/) 전용 API — 메모·댓글 관리와 계정 관리.
// Not tied to any member or organization: the dashboard's server side sends
// the shared secret ADMIN_API_KEY as X-Admin-Key. Without that env var the
// whole router is off.
export const adminRouter = Router();

const ADMIN_ACTOR = '시스템 관리자';

const digest = (value) => crypto.createHash('sha256').update(String(value)).digest();

adminRouter.use((req, res, next) => {
  const key = process.env.ADMIN_API_KEY;
  if (!key) return res.status(503).json({ error: '관리자 API가 비활성화되어 있습니다 (ADMIN_API_KEY 미설정).' });
  if (!crypto.timingSafeEqual(digest(req.get('X-Admin-Key') ?? ''), digest(key))) {
    return res.status(401).json({ error: '관리자 인증에 실패했습니다.' });
  }
  next();
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const optionalUuid = (value) => (typeof value === 'string' && UUID_RE.test(value) ? value : null);
const notFound = (res, what) => res.status(404).json({ error: `${what}을(를) 찾을 수 없습니다.` });

// ── 대시보드 ────────────────────────────────────────────────────────

adminRouter.get('/stats', async (req, res) => {
  const { rows } = await query(`select
      (select count(*)::int from organizations) as organizations,
      (select count(*)::int from members) as members,
      (select count(*)::int from members where status = 'inactive') as inactive_members,
      (select count(*)::int from memos) as memos,
      (select count(*)::int from memos where created_at > now() - interval '7 days') as memos_this_week,
      (select count(*)::int from memo_comments) as comments,
      (select count(*)::int from memo_comments where created_at > now() - interval '7 days') as comments_this_week`);
  const s = rows[0];
  res.json({
    organizations: s.organizations,
    members: s.members,
    activeMembers: s.members - s.inactive_members,
    inactiveMembers: s.inactive_members,
    memos: s.memos,
    memosThisWeek: s.memos_this_week,
    comments: s.comments,
    commentsThisWeek: s.comments_this_week,
  });
});

adminRouter.get('/organizations', async (req, res) => {
  const { rows } = await query(
    `select o.id, o.name, o.created_at, (select count(*)::int from members m where m.org_id = o.id) as member_count
     from organizations o order by o.name`,
  );
  res.json(rows.map((r) => ({ id: r.id, name: r.name, memberCount: r.member_count, createdAt: r.created_at })));
});

// ── 계정 관리 ───────────────────────────────────────────────────────

const MEMBER_SELECT = `select m.*, o.name as org_name,
    (select count(*)::int from memos mm where mm.author_member_id = m.id) as memo_count,
    (select count(*)::int from memo_comments c where c.author_member_id = m.id) as comment_count
  from members m join organizations o on o.id = m.org_id`;

function toMemberJson(row) {
  return {
    id: row.id,
    orgId: row.org_id,
    orgName: row.org_name,
    name: row.name,
    email: row.email,
    phone: row.phone,
    role: row.role,
    status: row.status,
    memoCount: row.memo_count ?? 0,
    commentCount: row.comment_count ?? 0,
    marketingAgreed: row.marketing_agreed ?? false,
    termsAgreedAt: row.terms_agreed_at ?? null,
    createdAt: row.created_at,
  };
}

async function loadMember(id) {
  if (!UUID_RE.test(id)) return null;
  const { rows } = await query(`${MEMBER_SELECT} where m.id = $1`, [id]);
  return rows[0] ?? null;
}

adminRouter.get('/members', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const status = ['active', 'inactive'].includes(req.query.status) ? req.query.status : null;
  const { rows } = await query(
    `${MEMBER_SELECT}
     where ($1::uuid is null or m.org_id = $1)
       and ($2::text is null or m.status = $2)
       and ($3 = '' or m.name ilike '%' || $3 || '%' or m.email ilike '%' || $3 || '%'
            or coalesce(m.phone, '') like '%' || $3 || '%' or o.name ilike '%' || $3 || '%')
     order by o.name, case m.role when 'owner' then 0 when 'director' then 1 when 'staff' then 2 else 3 end, m.created_at`,
    [optionalUuid(req.query.orgId), status, q],
  );
  res.json(rows.map(toMemberJson));
});

adminRouter.get('/members/:id', async (req, res) => {
  const member = await loadMember(req.params.id);
  if (!member) return notFound(res, '계정');
  res.json(toMemberJson(member));
});

const MEMBER_FIELDS = [
  ['name', '이름'],
  ['email', '이메일'],
  ['phone', '연락처'],
];

adminRouter.patch('/members/:id', async (req, res) => {
  const member = await loadMember(req.params.id);
  if (!member) return notFound(res, '계정');

  const body = req.body ?? {};
  const name = body.name === undefined ? member.name : String(body.name).trim();
  const email = body.email === undefined ? member.email : normalizeEmail(body.email);
  const phone = body.phone === undefined ? member.phone : digitsOnly(body.phone) || null;
  if (!name) return res.status(400).json({ error: '이름을 입력해 주세요.' });
  const invalid = (body.email !== undefined && validateEmail(email)) || (phone && validatePhone(phone));
  if (invalid) return res.status(400).json({ error: invalid });
  if (email !== member.email) {
    const { rows } = await query('select 1 from members where lower(email) = $1 and id <> $2', [email, member.id]);
    if (rows[0]) return res.status(409).json({ error: '이미 사용 중인 이메일입니다.' });
  }

  const after = { name, email, phone };
  const changes = diffFields(member, after, MEMBER_FIELDS);
  if (changes.length === 0) return res.json(toMemberJson(member));

  await query('update members set name = $2, email = $3, phone = $4 where id = $1', [member.id, name, email, phone]);
  await recordAudit({ orgId: member.org_id, actorName: ADMIN_ACTOR, entityType: 'member', entityId: member.id, entityName: name, action: 'update', changes });
  res.json(toMemberJson(await loadMember(member.id)));
});

adminRouter.post('/members/:id/password', async (req, res) => {
  const member = await loadMember(req.params.id);
  if (!member) return notFound(res, '계정');
  const password = req.body?.password;
  const invalid = validatePassword(password);
  if (invalid) return res.status(400).json({ error: invalid });

  await query('update members set password_hash = $2 where id = $1', [member.id, await hashPassword(password)]);
  await recordAudit({
    orgId: member.org_id,
    actorName: ADMIN_ACTOR,
    entityType: 'member',
    entityId: member.id,
    entityName: member.name,
    action: 'password_reset',
    changes: [{ field: 'password', label: '비밀번호', from: '', to: '재설정됨' }],
  });
  res.status(204).end();
});

// Unlike the institute-side 구성원 관리, owners can be deactivated here too
// (e.g. a lost or abused account); requireAuth rejects them right away.
adminRouter.post('/members/:id/status', async (req, res) => {
  const member = await loadMember(req.params.id);
  if (!member) return notFound(res, '계정');
  const status = req.body?.status;
  if (!['active', 'inactive'].includes(status)) return res.status(400).json({ error: '상태 값이 올바르지 않습니다.' });
  if (member.status === status) return res.json(toMemberJson(member));

  await query('update members set status = $2 where id = $1', [member.id, status]);
  await recordAudit({
    orgId: member.org_id,
    actorName: ADMIN_ACTOR,
    entityType: 'member',
    entityId: member.id,
    entityName: member.name,
    action: status === 'inactive' ? 'deactivate' : 'reactivate',
    changes: [{ field: 'status', label: '상태', from: member.status === 'active' ? '활성' : '비활성', to: status === 'active' ? '활성' : '비활성' }],
  });
  res.json(toMemberJson(await loadMember(member.id)));
});

// ── 커뮤니티(메모·댓글) 관리 ────────────────────────────────────────

const MEMO_SELECT = `select mm.id, mm.org_id, o.name as org_name, mm.farm_id, f.name as farm_name,
    mm.author_type, mm.author_name, mm.author_member_id, mm.content, mm.tags, mm.created_at,
    (select count(*)::int from memo_photos p where p.memo_id = mm.id) as photo_count,
    (select count(*)::int from memo_comments c where c.memo_id = mm.id) as comment_count,
    (select count(*)::int from memo_edits e where e.memo_id = mm.id) as edit_count
  from memos mm
  join organizations o on o.id = mm.org_id
  left join farms f on f.id = mm.farm_id`;

function toMemoJson(row) {
  return {
    id: row.id,
    orgId: row.org_id,
    orgName: row.org_name,
    farmId: row.farm_id,
    farmName: row.farm_name,
    authorType: row.author_type,
    authorName: row.author_name,
    authorMemberId: row.author_member_id,
    content: row.content,
    tags: row.tags ?? [],
    photoCount: row.photo_count ?? 0,
    commentCount: row.comment_count ?? 0,
    editCount: row.edit_count ?? 0,
    createdAt: row.created_at,
  };
}

const PAGE_SIZE_MAX = 100;

// ?q= matches memo text, author, farm, institute, or any comment's text.
adminRouter.get('/memos', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const pageSize = Math.min(Math.max(parseInt(req.query.pageSize, 10) || 30, 1), PAGE_SIZE_MAX);
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const where = `where ($1::uuid is null or mm.org_id = $1)
      and ($2::uuid is null or mm.author_member_id = $2)
      and ($3 = '' or mm.content ilike '%' || $3 || '%' or mm.author_name ilike '%' || $3 || '%'
           or coalesce(f.name, '') ilike '%' || $3 || '%' or o.name ilike '%' || $3 || '%'
           or exists (select 1 from memo_comments c where c.memo_id = mm.id and c.content ilike '%' || $3 || '%'))`;
  const params = [optionalUuid(req.query.orgId), optionalUuid(req.query.authorId), q];
  const [{ rows }, { rows: countRows }] = await Promise.all([
    query(`${MEMO_SELECT} ${where} order by mm.created_at desc limit ${pageSize} offset ${(page - 1) * pageSize}`, params),
    query(`select count(*)::int as total from memos mm join organizations o on o.id = mm.org_id left join farms f on f.id = mm.farm_id ${where}`, params),
  ]);
  res.json({ items: rows.map(toMemoJson), total: countRows[0].total, page, pageSize });
});

adminRouter.get('/memos/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return notFound(res, '메모');
  const { rows } = await query(`${MEMO_SELECT} where mm.id = $1`, [req.params.id]);
  if (!rows[0]) return notFound(res, '메모');
  const [{ rows: photos }, { rows: comments }, { rows: edits }] = await Promise.all([
    query('select id from memo_photos where memo_id = $1 order by created_at', [req.params.id]),
    query('select id, author_member_id, author_name, content, created_at from memo_comments where memo_id = $1 order by created_at', [req.params.id]),
    query('select editor_name, previous_content, edited_at from memo_edits where memo_id = $1 order by edited_at', [req.params.id]),
  ]);
  res.json({
    ...toMemoJson(rows[0]),
    photoIds: photos.map((p) => p.id),
    comments: comments.map((c) => ({
      id: c.id,
      authorMemberId: c.author_member_id,
      authorName: c.author_name,
      content: c.content,
      createdAt: c.created_at,
    })),
    edits: edits.map((e) => ({ editorName: e.editor_name, previousContent: e.previous_content, editedAt: e.edited_at })),
  });
});

adminRouter.delete('/memos/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return notFound(res, '메모');
  const { rows } = await query('delete from memos where id = $1 returning farm_id', [req.params.id]);
  if (!rows[0]) return notFound(res, '메모');
  // Same as the app's own delete: a removed 폐사 memo changes the farm's risk.
  if (rows[0].farm_id) await refreshReportQuietly(rows[0].farm_id);
  res.status(204).end();
});

adminRouter.delete('/comments/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return notFound(res, '댓글');
  const { rowCount } = await query('delete from memo_comments where id = $1', [req.params.id]);
  if (!rowCount) return notFound(res, '댓글');
  res.status(204).end();
});

adminRouter.get('/photos/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return notFound(res, '사진');
  const { rows } = await query('select content_type, data from memo_photos where id = $1', [req.params.id]);
  if (!rows[0]) return notFound(res, '사진');
  res.set('Content-Type', rows[0].content_type);
  res.set('Cache-Control', 'private, max-age=31536000, immutable');
  res.send(rows[0].data);
});

// ── 수산 뉴스 ───────────────────────────────────────────────────────
// 앱 사용자용 /api/news 와 달리 숨긴 소식도 보이고, 수집을 직접 돌릴 수 있습니다.
// 위의 X-Admin-Key 확인이 이 라우터 전체를 막고 있어, 일반 사용자 토큰으로는 들어올 수 없습니다.

adminRouter.get('/news', async (req, res) => {
  const page = Math.max(1, Number.parseInt(req.query.page, 10) || 1);
  const pageSize = Math.min(100, Math.max(1, Number.parseInt(req.query.pageSize, 10) || 30));
  const category = NEWS_CATEGORIES.includes(req.query.category) ? req.query.category : null;
  const published = req.query.published === 'true' ? true : req.query.published === 'false' ? false : null;
  const q = typeof req.query.q === 'string' && req.query.q.trim() ? req.query.q.trim() : null;
  const { rows } = await query(
    `select * from news_items
     where ($1::text is null or category = $1)
       and ($2::boolean is null or is_published = $2)
       and ($3::text is null or title ilike '%' || $3 || '%')
     order by published_at desc nulls last, id
     limit $4 offset $5`,
    [category, published, q, pageSize + 1, (page - 1) * pageSize],
  );
  res.json({
    items: rows.slice(0, pageSize).map((r) => ({
      ...toNewsJson(r),
      isPublished: r.is_published,
      editedByAdmin: r.edited_by_admin,
      fetchedAt: r.fetched_at,
    })),
    page,
    pageSize,
    hasMore: rows.length > pageSize,
  });
});

adminRouter.get('/news/sources', async (req, res) => {
  const { rows } = await query('select * from news_sources order by source');
  res.json(
    rows.map((r) => ({
      source: r.source,
      name: r.name,
      lastAttemptAt: r.last_attempt_at,
      lastSuccessAt: r.last_success_at,
      lastError: r.last_error,
      lastFetchedCount: r.last_fetched_count,
      lastSavedCount: r.last_saved_count,
    })),
  );
});

// 분류·소개 수정, 게시/숨김. 분류나 소개를 고치면 재수집이 덮어쓰지 않도록 표시합니다.
adminRouter.patch('/news/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return notFound(res, '소식');
  const { category, summary, isPublished } = req.body ?? {};
  if (category !== undefined && !NEWS_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: '분류 값이 올바르지 않습니다.' });
  }
  if (summary !== undefined && summary !== null && (typeof summary !== 'string' || summary.length > 300)) {
    return res.status(400).json({ error: '소개는 300자 이내의 글자여야 합니다.' });
  }
  if (isPublished !== undefined && typeof isPublished !== 'boolean') {
    return res.status(400).json({ error: '게시 여부 값이 올바르지 않습니다.' });
  }
  const textEdit = category !== undefined || summary !== undefined;
  const { rows } = await query(
    `update news_items set
       category = coalesce($2, category),
       summary = case when $3::boolean then nullif(trim($4), '') else summary end,
       is_published = coalesce($5, is_published),
       edited_by_admin = edited_by_admin or $6
     where id = $1 returning *`,
    [req.params.id, category ?? null, summary !== undefined, summary ?? null, isPublished ?? null, textEdit],
  );
  if (!rows[0]) return notFound(res, '소식');
  res.json({ ...toNewsJson(rows[0]), isPublished: rows[0].is_published, editedByAdmin: rows[0].edited_by_admin });
});

// 수동 수집. 정해진 시각의 자동 수집과 같은 코드를 쓰고, 동시에 두 번 돌지 않습니다.
adminRouter.post('/news/collect', async (req, res) => {
  const outcome = await runNewsCollection({ backfill: req.body?.backfill === true ? true : undefined });
  res.json(outcome);
});
