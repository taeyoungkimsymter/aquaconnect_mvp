import { Router } from 'express';

import { requireAuth } from '../auth.js';
import { pool, query } from '../db.js';
import { orgIdForMember } from '../lib/orgScope.js';
import { notifyMembers } from '../lib/notify.js';
import { refreshReportQuietly } from './reports.js';

export const memosRouter = Router();
memosRouter.use(requireAuth);

const MAX_PHOTOS = 5;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const ALLOWED_PHOTO_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

// [withEdits] — only owners/directors see the 수정 이력 contents; everyone
// else just gets the count (for the "수정됨" label).
function toMemoJson(row, { withEdits = false } = {}) {
  return {
    id: row.id,
    orgId: row.org_id,
    farmId: row.farm_id,
    farmName: row.farm_name,
    authorType: row.author_type,
    authorName: row.author_name,
    content: row.content,
    tags: row.tags ?? [],
    photoCount: row.photo_count,
    photoIds: row.photo_ids ?? [],
    authorMemberId: row.author_member_id ?? null,
    createdAt: row.created_at,
    completedAt: row.completed_at ?? null,
    editCount: row.edit_count ?? 0,
    edits: withEdits ? (row.edits ?? []) : [],
    commentCount: row.comment_count ?? 0,
    // Members other than the author who have seen it.
    readCount: row.read_count ?? 0,
    readByMe: row.read_by_me ?? false,
  };
}

const PHOTO_IDS_SQL = `coalesce(
  (select array_agg(p.id::text order by p.created_at) from memo_photos p where p.memo_id = mm.id),
  '{}'
) as photo_ids`;

const EDITS_SQL = `(select count(*)::int from memo_edits e where e.memo_id = mm.id) as edit_count,
coalesce(
  (select json_agg(json_build_object('editorName', e.editor_name, 'editedAt', e.edited_at, 'previousContent', e.previous_content)
                   order by e.edited_at)
   from memo_edits e where e.memo_id = mm.id),
  '[]'::json
) as edits`;

const SOCIAL_SQL = `(select count(*)::int from memo_comments c where c.memo_id = mm.id) as comment_count,
(select count(*)::int from memo_reads r
  where r.memo_id = mm.id and r.member_id is distinct from mm.author_member_id) as read_count`;

// [meParam] is the placeholder number holding the requesting member's id
// (for read_by_me).
const memoSelectSql = (meParam) => `select mm.*, f.name as farm_name, ${PHOTO_IDS_SQL}, ${EDITS_SQL}, ${SOCIAL_SQL},
    exists (select 1 from memo_reads r where r.memo_id = mm.id and r.member_id = $${meParam}) as read_by_me
  from memos mm left join farms f on f.id = mm.farm_id`;

async function currentMember(memberId) {
  const { rows } = await query('select id, name, role from members where id = $1', [memberId]);
  return rows[0] ?? null;
}

const isManager = (me) => ['owner', 'director'].includes(me?.role);

// Memos record their author's member id; older ones (and any whose author
// name was ambiguous) fall back to the "수산질병관리원 · <name>" signature.
const isAuthor = (memo, me) => {
  if (memo.author_type !== 'institute' || !me) return false;
  if (memo.author_member_id) return memo.author_member_id === me.id;
  return memo.author_name.endsWith(` · ${me.name}`);
};

async function loadMemoJson(memoId, me) {
  const { rows } = await query(`${memoSelectSql(2)} where mm.id = $1`, [memoId, me?.id ?? null]);
  return rows[0] ? toMemoJson(rows[0], { withEdits: isManager(me) }) : null;
}

async function markRead(memoIds, memberId) {
  if (memoIds.length === 0) return;
  await query(
    `insert into memo_reads (memo_id, member_id)
     select id, $2 from memos where id = any($1::uuid[]) and org_id = (select org_id from members where id = $2)
     on conflict do nothing`,
    [memoIds, memberId],
  );
}

memosRouter.get('/', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const farmId = req.query.farmId ?? null;
  const me = await currentMember(req.memberId);
  const { rows } = await query(
    `${memoSelectSql(3)}
     where mm.org_id = $1 and ($2::uuid is null or mm.farm_id = $2)
     order by mm.created_at desc`,
    [orgId, farmId, req.memberId],
  );
  res.json(rows.map((row) => toMemoJson(row, { withEdits: isManager(me) })));
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// 읽음 표시: the app reports the memos the member has seen on screen.
memosRouter.post('/read', async (req, res) => {
  const ids = Array.isArray(req.body?.ids) ? req.body.ids.filter((id) => typeof id === 'string' && UUID_RE.test(id)) : [];
  await markRead(ids.slice(0, 500), req.memberId);
  res.status(204).end();
});

memosRouter.get('/photos/:photoId', async (req, res) => {
  if (!UUID_RE.test(req.params.photoId)) return res.status(404).json({ error: '사진을 찾을 수 없습니다.' });
  const orgId = await orgIdForMember(req.memberId);
  const { rows } = await query(
    `select p.content_type, p.data
     from memo_photos p join memos mm on mm.id = p.memo_id
     where p.id = $1 and mm.org_id = $2`,
    [req.params.photoId, orgId],
  );
  if (!rows[0]) return res.status(404).json({ error: '사진을 찾을 수 없습니다.' });
  res.set('Content-Type', rows[0].content_type);
  res.set('Cache-Control', 'private, max-age=31536000, immutable');
  res.send(rows[0].data);
});

function decodePhotos(photos) {
  if (!Array.isArray(photos)) return { decoded: [] };
  if (photos.length > MAX_PHOTOS) return { error: `사진은 최대 ${MAX_PHOTOS}장까지 첨부할 수 있습니다.` };
  const decoded = [];
  for (const photo of photos) {
    const contentType = photo?.contentType;
    if (!ALLOWED_PHOTO_TYPES.has(contentType)) return { error: '지원하지 않는 사진 형식입니다.' };
    const data = Buffer.from(String(photo?.dataBase64 ?? ''), 'base64');
    if (data.length === 0) return { error: '사진 데이터가 비어 있습니다.' };
    if (data.length > MAX_PHOTO_BYTES) return { error: '사진 한 장은 5MB 이하여야 합니다.' };
    decoded.push({ contentType, data });
  }
  return { decoded };
}

memosRouter.post('/', async (req, res) => {
  const orgId = await orgIdForMember(req.memberId);
  const { farmId = null, content, tags = [], photos = [] } = req.body ?? {};
  if (!content || !content.trim()) {
    return res.status(400).json({ error: '메모 내용을 입력해주세요.' });
  }
  const { decoded, error } = decodePhotos(photos);
  if (error) return res.status(400).json({ error });
  if (farmId) {
    const { rows: farmRows } = await query('select id from farms where org_id = $1 and id = $2', [orgId, farmId]);
    if (!farmRows[0]) return res.status(404).json({ error: '양식장을 찾을 수 없습니다.' });
  }

  const { rows: memberRows } = await query('select name from members where id = $1', [req.memberId]);
  const authorName = `수산질병관리원 · ${memberRows[0]?.name ?? ''}`;

  const client = await pool.connect();
  let memoRow;
  const photoIds = [];
  try {
    await client.query('begin');
    const { rows } = await client.query(
      `insert into memos (org_id, farm_id, author_type, author_name, author_member_id, content, tags, photo_count)
       values ($1, $2, 'institute', $3, $4, $5, $6, $7)
       returning *`,
      [orgId, farmId, authorName, req.memberId, content, tags, decoded.length],
    );
    memoRow = rows[0];
    for (const photo of decoded) {
      const { rows: photoRows } = await client.query(
        'insert into memo_photos (memo_id, content_type, data) values ($1, $2, $3) returning id',
        [memoRow.id, photo.contentType, photo.data],
      );
      photoIds.push(photoRows[0].id);
    }
    await client.query('commit');
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }

  let farmName = null;
  if (memoRow.farm_id) {
    const { rows: farmRows } = await query('select name from farms where id = $1', [memoRow.farm_id]);
    farmName = farmRows[0]?.name ?? null;
    // A new 폐사 count / visit changes the farm's risk and 최근 방문.
    await refreshReportQuietly(memoRow.farm_id);
  }

  const preview = content.trim().replace(/\s+/g, ' ');
  await notifyMembers({
    orgId,
    excludeMemberId: req.memberId,
    type: 'memo',
    title: `새 메모 · ${farmName ?? '미지정'}`,
    body: `${memberRows[0]?.name ?? ''}: ${preview.length > 80 ? `${preview.slice(0, 80)}…` : preview}`,
    link: `/memos/${memoRow.id}`,
  });

  res.status(201).json(toMemoJson({ ...memoRow, farm_name: farmName, photo_ids: photoIds }));
});

// One memo by id (opened from a 새 메모 / 새 댓글 notification). Scoped to the
// caller's org like the list, so another org's memo is indistinguishable from
// a deleted one.
memosRouter.get('/:id', async (req, res) => {
  const memo = await loadOrgMemo(req.params.id, req.memberId);
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });
  res.json(await loadMemoJson(memo.id, await currentMember(req.memberId)));
});

// 완료 / 완료 취소: any member of the org can check a memo off (any memo, not
// only 할일 ones) — it's a shared to-do state, not an edit of the memo.
memosRouter.put('/:id/completion', async (req, res) => {
  if (typeof req.body?.completed !== 'boolean') return res.status(400).json({ error: '완료 여부가 올바르지 않습니다.' });
  const memo = await loadOrgMemo(req.params.id, req.memberId);
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });
  await query('update memos set completed_at = case when $2 then coalesce(completed_at, now()) end where id = $1', [
    memo.id,
    req.body.completed,
  ]);
  res.json(await loadMemoJson(memo.id, await currentMember(req.memberId)));
});

// 메모 수정: institute memos only (a farm's 문의 stays as the farm sent it),
// by the author or an owner/director. The old content goes to memo_edits.
memosRouter.patch('/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });
  const content = typeof req.body?.content === 'string' ? req.body.content.trim() : '';
  if (!content) return res.status(400).json({ error: '메모 내용을 입력해주세요.' });

  const orgId = await orgIdForMember(req.memberId);
  const { rows: memoRows } = await query(
    'select id, farm_id, author_type, author_name, author_member_id, content from memos where id = $1 and org_id = $2',
    [req.params.id, orgId],
  );
  const memo = memoRows[0];
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });

  const me = await currentMember(req.memberId);
  if (memo.author_type !== 'institute') return res.status(403).json({ error: '어가가 보낸 메모는 수정할 수 없습니다.' });
  if (!isManager(me) && !isAuthor(memo, me)) {
    return res.status(403).json({ error: '작성자 또는 소유자·원장만 수정할 수 있습니다.' });
  }

  if (content !== memo.content) {
    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(
        'insert into memo_edits (memo_id, editor_member_id, editor_name, previous_content) values ($1, $2, $3, $4)',
        [memo.id, req.memberId, me?.name ?? '', memo.content],
      );
      await client.query('update memos set content = $2 where id = $1', [memo.id, content]);
      await client.query('commit');
    } catch (err) {
      await client.query('rollback');
      throw err;
    } finally {
      client.release();
    }
    // An edited 폐사 count changes the farm's risk.
    if (memo.farm_id) await refreshReportQuietly(memo.farm_id);
  }

  res.json(await loadMemoJson(memo.id, me));
});

// 메모 삭제: the author or an owner/director. Photos, edits, comments and
// reads go with it (FK cascade).
memosRouter.delete('/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });
  const orgId = await orgIdForMember(req.memberId);
  const { rows: memoRows } = await query('select id, farm_id, author_type, author_name, author_member_id from memos where id = $1 and org_id = $2', [
    req.params.id,
    orgId,
  ]);
  const memo = memoRows[0];
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });

  const me = await currentMember(req.memberId);
  if (!isManager(me) && !isAuthor(memo, me)) {
    return res.status(403).json({ error: '작성자 또는 소유자·원장만 삭제할 수 있습니다.' });
  }

  await query('delete from memos where id = $1', [memo.id]);
  // A removed 폐사 memo changes the farm's risk and 최근 방문.
  if (memo.farm_id) await refreshReportQuietly(memo.farm_id);
  res.status(204).end();
});

// ── 댓글 ──────────────────────────────────────────────────────────────
const MAX_COMMENT_LENGTH = 1000;

const MAX_COMMENT_PHOTOS = 5;
const MAX_COMMENT_FILES = 3;
const MAX_COMMENT_FILE_BYTES = 10 * 1024 * 1024;
const MAX_COMMENT_TOTAL_BYTES = 24 * 1024 * 1024; // keeps the base64 JSON under the 40mb body limit
const MAX_MENTIONS = 10;
// Documents only — anything a browser could run (html, svg, js, exe…) is refused.
const ALLOWED_FILE_EXTENSIONS = new Set([
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'hwp', 'hwpx', 'txt', 'csv', 'zip',
]);

const ATTACHMENTS_SQL = `coalesce(
  (select json_agg(json_build_object('id', a.id, 'kind', a.kind, 'fileName', a.file_name,
                                     'contentType', a.content_type, 'size', a.size) order by a.created_at)
   from memo_comment_attachments a where a.comment_id = c.id),
  '[]'::json
) as attachments`;

function toCommentJson(row) {
  return {
    id: row.id,
    memoId: row.memo_id,
    authorMemberId: row.author_member_id ?? null,
    authorName: row.author_name,
    content: row.content,
    createdAt: row.created_at,
    mentions: row.mentions ?? [],
    attachments: row.attachments ?? [],
  };
}

// Validates and decodes a comment's attachments: [{kind, fileName, contentType, dataBase64}].
function decodeAttachments(list) {
  if (list == null) return { decoded: [] };
  if (!Array.isArray(list)) return { error: '첨부 형식이 올바르지 않습니다.' };
  const decoded = [];
  let photos = 0;
  let files = 0;
  let total = 0;
  for (const item of list) {
    const kind = item?.kind;
    const data = Buffer.from(String(item?.dataBase64 ?? ''), 'base64');
    if (data.length === 0) return { error: '첨부 데이터가 비어 있습니다.' };
    total += data.length;
    if (kind === 'photo') {
      if (!ALLOWED_PHOTO_TYPES.has(item.contentType)) return { error: '지원하지 않는 사진 형식입니다.' };
      if (data.length > MAX_PHOTO_BYTES) return { error: '사진 한 장은 5MB 이하여야 합니다.' };
      if (++photos > MAX_COMMENT_PHOTOS) return { error: `사진은 최대 ${MAX_COMMENT_PHOTOS}장까지 첨부할 수 있습니다.` };
      decoded.push({ kind, fileName: String(item.fileName || 'photo.jpg').slice(0, 200), contentType: item.contentType, data });
    } else if (kind === 'file') {
      const fileName = String(item.fileName ?? '').trim().slice(0, 200);
      const ext = fileName.includes('.') ? fileName.split('.').pop().toLowerCase() : '';
      if (!ALLOWED_FILE_EXTENSIONS.has(ext)) {
        return { error: `첨부할 수 없는 파일 형식입니다. (${[...ALLOWED_FILE_EXTENSIONS].join(', ')})` };
      }
      if (data.length > MAX_COMMENT_FILE_BYTES) return { error: '파일 하나는 10MB 이하여야 합니다.' };
      if (++files > MAX_COMMENT_FILES) return { error: `파일은 최대 ${MAX_COMMENT_FILES}개까지 첨부할 수 있습니다.` };
      decoded.push({ kind, fileName, contentType: 'application/octet-stream', data });
    } else {
      return { error: '첨부 형식이 올바르지 않습니다.' };
    }
  }
  if (total > MAX_COMMENT_TOTAL_BYTES) return { error: '첨부 용량이 너무 큽니다. (합계 24MB 이하)' };
  return { decoded };
}

async function loadOrgMemo(memoId, memberId) {
  if (!UUID_RE.test(memoId)) return null;
  const orgId = await orgIdForMember(memberId);
  const { rows } = await query(
    `select mm.id, mm.org_id, mm.author_member_id, f.name as farm_name
     from memos mm left join farms f on f.id = mm.farm_id
     where mm.id = $1 and mm.org_id = $2`,
    [memoId, orgId],
  );
  return rows[0] ?? null;
}

memosRouter.get('/:id/comments', async (req, res) => {
  const memo = await loadOrgMemo(req.params.id, req.memberId);
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });
  const { rows } = await query(
    `select c.*, ${ATTACHMENTS_SQL} from memo_comments c where c.memo_id = $1 order by c.created_at`,
    [memo.id],
  );
  res.json(rows.map(toCommentJson));
});

memosRouter.post('/:id/comments', async (req, res) => {
  const content = typeof req.body?.content === 'string' ? req.body.content.trim() : '';
  if (content.length > MAX_COMMENT_LENGTH) {
    return res.status(400).json({ error: `댓글은 ${MAX_COMMENT_LENGTH}자 이내로 입력해주세요.` });
  }
  const { decoded, error } = decodeAttachments(req.body?.attachments);
  if (error) return res.status(400).json({ error });
  if (!content && decoded.length === 0) return res.status(400).json({ error: '댓글 내용을 입력해주세요.' });
  const memo = await loadOrgMemo(req.params.id, req.memberId);
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });

  // 사람 호출: only active members of this org, never yourself.
  const wanted = Array.isArray(req.body?.mentionedMemberIds)
    ? [...new Set(req.body.mentionedMemberIds.filter((id) => typeof id === 'string' && UUID_RE.test(id)))]
    : [];
  if (wanted.length > MAX_MENTIONS) return res.status(400).json({ error: `한 번에 ${MAX_MENTIONS}명까지 호출할 수 있습니다.` });
  const { rows: mentioned } = wanted.length
    ? await query(
        `select id, name from members where id = any($1::uuid[]) and org_id = $2 and status = 'active' and id <> $3`,
        [wanted, memo.org_id, req.memberId],
      )
    : { rows: [] };

  const me = await currentMember(req.memberId);
  const client = await pool.connect();
  let commentRow;
  try {
    await client.query('begin');
    const { rows } = await client.query(
      `insert into memo_comments (memo_id, author_member_id, author_name, content, mentions)
       values ($1, $2, $3, $4, $5::jsonb) returning *`,
      [memo.id, req.memberId, me?.name ?? '', content, JSON.stringify(mentioned.map((m) => ({ id: m.id, name: m.name })))],
    );
    commentRow = rows[0];
    for (const att of decoded) {
      await client.query(
        `insert into memo_comment_attachments (comment_id, kind, file_name, content_type, size, data)
         values ($1, $2, $3, $4, $5, $6)`,
        [commentRow.id, att.kind, att.fileName, att.contentType, att.data.length, att.data],
      );
    }
    await client.query('commit');
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
  // Commenting on a memo means you've read it.
  await markRead([memo.id], req.memberId);

  const photoCount = decoded.filter((d) => d.kind === 'photo').length;
  const fileCount = decoded.length - photoCount;
  const preview = [content.replace(/s+/g, ' '), photoCount ? `사진 ${photoCount}장` : '', fileCount ? `파일 ${fileCount}개` : '']
    .filter(Boolean)
    .join(' ');
  const body = `${me?.name ?? ''}: ${preview.length > 80 ? `${preview.slice(0, 80)}…` : preview}`;
  const where = memo.farm_name ?? '미지정';

  // The people called get their own 호출 notification…
  const calledIds = mentioned.map((m) => m.id);
  if (calledIds.length) {
    await notifyMembers({
      memberIds: calledIds,
      type: 'comment',
      title: `${me?.name ?? ''}님이 회원님을 호출했어요 · ${where}`,
      body,
      link: `/memos/${memo.id}`,
    });
  }
  // …and the memo's author plus everyone else in the thread hear about the comment.
  const { rows: threadRows } = await query(
    'select distinct author_member_id as id from memo_comments where memo_id = $1 and author_member_id is not null',
    [memo.id],
  );
  const recipients = [...new Set([memo.author_member_id, ...threadRows.map((r) => r.id)])].filter(
    (id) => id && id !== req.memberId && !calledIds.includes(id),
  );
  if (recipients.length) {
    await notifyMembers({
      memberIds: recipients,
      type: 'comment',
      title: `새 댓글 · ${where}`,
      body,
      link: `/memos/${memo.id}`,
    });
  }
  const { rows: full } = await query(`select c.*, ${ATTACHMENTS_SQL} from memo_comments c where c.id = $1`, [commentRow.id]);
  res.status(201).json(toCommentJson(full[0]));
});

// 댓글 첨부 내려받기: photos are shown inline, files always download. Scoped to the org.
memosRouter.get('/:id/comments/:commentId/attachments/:attachmentId', async (req, res) => {
  const memo = await loadOrgMemo(req.params.id, req.memberId);
  if (!memo || !UUID_RE.test(req.params.commentId) || !UUID_RE.test(req.params.attachmentId)) {
    return res.status(404).json({ error: '첨부를 찾을 수 없습니다.' });
  }
  const { rows } = await query(
    `select a.kind, a.file_name, a.content_type, a.data
     from memo_comment_attachments a join memo_comments c on c.id = a.comment_id
     where a.id = $1 and c.id = $2 and c.memo_id = $3`,
    [req.params.attachmentId, req.params.commentId, memo.id],
  );
  const att = rows[0];
  if (!att) return res.status(404).json({ error: '첨부를 찾을 수 없습니다.' });
  res.set('Content-Type', att.content_type);
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Cache-Control', 'private, max-age=31536000, immutable');
  if (att.kind === 'file') {
    res.set('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(att.file_name)}`);
  }
  res.send(att.data);
});

// 댓글 삭제: its author or an owner/director.
memosRouter.delete('/:id/comments/:commentId', async (req, res) => {
  const memo = await loadOrgMemo(req.params.id, req.memberId);
  if (!memo || !UUID_RE.test(req.params.commentId)) return res.status(404).json({ error: '댓글을 찾을 수 없습니다.' });
  const { rows } = await query('select id, author_member_id from memo_comments where id = $1 and memo_id = $2', [
    req.params.commentId,
    memo.id,
  ]);
  const comment = rows[0];
  if (!comment) return res.status(404).json({ error: '댓글을 찾을 수 없습니다.' });
  const me = await currentMember(req.memberId);
  if (!isManager(me) && comment.author_member_id !== req.memberId) {
    return res.status(403).json({ error: '작성자 또는 소유자·원장만 삭제할 수 있습니다.' });
  }
  await query('delete from memo_comments where id = $1', [comment.id]);
  res.status(204).end();
});
