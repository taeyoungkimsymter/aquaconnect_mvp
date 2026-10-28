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
    editCount: row.edit_count ?? 0,
    edits: withEdits ? (row.edits ?? []) : [],
    commentCount: row.comment_count ?? 0,
    // Members other than the author who have seen it.
    readCount: row.read_count ?? 0,
    readByMe: row.read_by_me ?? false,
    // A 댓글 on it calls (@) the requesting member.
    mentionedMe: row.mentioned_me ?? false,
    // 완료: set when someone marks the task memo done.
    doneAt: row.done_at ?? null,
    doneByMemberId: row.done_by_member_id ?? null,
    doneByName: row.done_by_name ?? null,
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
    exists (select 1 from memo_reads r where r.memo_id = mm.id and r.member_id = $${meParam}) as read_by_me,
    exists (select 1 from memo_comment_mentions x join memo_comments c on c.id = x.comment_id
            where c.memo_id = mm.id and x.member_id = $${meParam}) as mentioned_me
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
    link: `/memo?memo=${memoRow.id}`,
  });

  res.status(201).json(toMemoJson({ ...memoRow, farm_name: farmName, photo_ids: photoIds }));
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

// 메모 완료 / 완료 취소: any member of the org (a handed-over job is finished
// by whoever took it). Body: { done: boolean }. The author hears about it.
memosRouter.put('/:id/done', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });
  const done = req.body?.done;
  if (typeof done !== 'boolean') return res.status(400).json({ error: '완료 여부가 올바르지 않습니다.' });
  const orgId = await orgIdForMember(req.memberId);
  const me = await currentMember(req.memberId);
  const { rows } = await query(
    `update memos mm set
       done_at = case when $3 then coalesce(mm.done_at, now()) end,
       done_by_member_id = case when $3 then coalesce(mm.done_by_member_id, $4) end,
       done_by_name = case when $3 then coalesce(mm.done_by_name, $5) end
     from memos old
     where mm.id = $1 and mm.org_id = $2 and old.id = mm.id
     returning mm.id, mm.content, mm.author_member_id, old.done_at as was_done_at,
       (select name from farms f where f.id = mm.farm_id) as farm_name`,
    [req.params.id, orgId, done, req.memberId, me?.name ?? ''],
  );
  const memo = rows[0];
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });

  if (done && !memo.was_done_at && memo.author_member_id && memo.author_member_id !== req.memberId) {
    const flat = memo.content.trim().replace(/\s+/g, ' ');
    await notifyMembers({
      memberIds: [memo.author_member_id],
      type: 'comment',
      title: `업무 완료 · ${memo.farm_name ?? '미지정'}`,
      body: `${me?.name ?? ''}님이 완료했어요: ${flat.length > 60 ? `${flat.slice(0, 60)}…` : flat}`,
      link: `/memo?memo=${memo.id}`,
    });
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
const MAX_COMMENT_ATTACHMENTS = 5;
const MAX_COMMENT_FILE_BYTES = 10 * 1024 * 1024;
// Keeps one comment's base64 body well under express.json's 40mb limit.
const MAX_COMMENT_TOTAL_BYTES = 20 * 1024 * 1024;
const MAX_MENTIONS = 20;
const CONTENT_TYPE_RE = /^[\w.+-]+\/[\w.+-]+$/;

function toCommentJson(row) {
  return {
    id: row.id,
    memoId: row.memo_id,
    authorMemberId: row.author_member_id ?? null,
    authorName: row.author_name,
    content: row.content,
    createdAt: row.created_at,
    attachments: row.attachments ?? [],
    mentions: row.mentions ?? [],
  };
}

// Attachment metadata only — bytes come from GET /comment-attachments/:id.
const COMMENT_SELECT_SQL = `select c.*,
  coalesce(
    (select json_agg(json_build_object('id', a.id, 'kind', a.kind, 'fileName', a.file_name,
                                       'contentType', a.content_type, 'size', a.size_bytes) order by a.created_at)
     from memo_comment_attachments a where a.comment_id = c.id),
    '[]'::json
  ) as attachments,
  coalesce(
    (select json_agg(json_build_object('memberId', m.id, 'name', m.name) order by m.name)
     from memo_comment_mentions x join members m on m.id = x.member_id where x.comment_id = c.id),
    '[]'::json
  ) as mentions
from memo_comments c`;

function decodeCommentAttachments(attachments) {
  if (!Array.isArray(attachments)) return { decoded: [] };
  if (attachments.length > MAX_COMMENT_ATTACHMENTS) {
    return { error: `첨부는 최대 ${MAX_COMMENT_ATTACHMENTS}개까지 가능합니다.` };
  }
  const decoded = [];
  let total = 0;
  for (const item of attachments) {
    const kind = item?.kind === 'photo' ? 'photo' : 'file';
    const contentType = String(item?.contentType ?? '').toLowerCase();
    if (kind === 'photo' && !ALLOWED_PHOTO_TYPES.has(contentType)) return { error: '지원하지 않는 사진 형식입니다.' };
    const data = Buffer.from(String(item?.dataBase64 ?? ''), 'base64');
    if (data.length === 0) return { error: '첨부 파일이 비어 있습니다.' };
    const limit = kind === 'photo' ? MAX_PHOTO_BYTES : MAX_COMMENT_FILE_BYTES;
    if (data.length > limit) return { error: `${kind === 'photo' ? '사진' : '파일'} 하나는 ${limit / 1024 / 1024}MB 이하여야 합니다.` };
    total += data.length;
    if (total > MAX_COMMENT_TOTAL_BYTES) return { error: '첨부 파일은 합쳐서 20MB 이하여야 합니다.' };
    const fileName = String(item?.fileName ?? '').replace(/[\\/\r\n"]/g, '_').trim().slice(0, 200) || (kind === 'photo' ? 'photo.jpg' : 'file');
    decoded.push({
      kind,
      fileName,
      contentType: CONTENT_TYPE_RE.test(contentType) ? contentType : 'application/octet-stream',
      data,
    });
  }
  return { decoded };
}

async function loadCommentJson(commentId) {
  const { rows } = await query(`${COMMENT_SELECT_SQL} where c.id = $1`, [commentId]);
  return rows[0] ? toCommentJson(rows[0]) : null;
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
  const { rows } = await query(`${COMMENT_SELECT_SQL} where c.memo_id = $1 order by c.created_at`, [memo.id]);
  res.json(rows.map(toCommentJson));
});

// 댓글 첨부 다운로드. Files are always sent as an attachment download
// (never rendered on the API origin).
memosRouter.get('/comment-attachments/:attachmentId', async (req, res) => {
  if (!UUID_RE.test(req.params.attachmentId)) return res.status(404).json({ error: '첨부 파일을 찾을 수 없습니다.' });
  const orgId = await orgIdForMember(req.memberId);
  const { rows } = await query(
    `select a.kind, a.file_name, a.content_type, a.data
     from memo_comment_attachments a
     join memo_comments c on c.id = a.comment_id
     join memos mm on mm.id = c.memo_id
     where a.id = $1 and mm.org_id = $2`,
    [req.params.attachmentId, orgId],
  );
  const row = rows[0];
  if (!row) return res.status(404).json({ error: '첨부 파일을 찾을 수 없습니다.' });
  res.set('Content-Type', row.kind === 'photo' ? row.content_type : 'application/octet-stream');
  res.set('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(row.file_name)}`);
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Cache-Control', 'private, max-age=31536000, immutable');
  res.send(row.data);
});

// Body: { content, mentionMemberIds?: [uuid], attachments?: [{kind, fileName, contentType, dataBase64}] }.
// Text may be empty when the comment carries attachments or a 호출.
memosRouter.post('/:id/comments', async (req, res) => {
  const content = typeof req.body?.content === 'string' ? req.body.content.trim() : '';
  if (content.length > MAX_COMMENT_LENGTH) {
    return res.status(400).json({ error: `댓글은 ${MAX_COMMENT_LENGTH}자 이내로 입력해주세요.` });
  }
  const { decoded: attachments, error } = decodeCommentAttachments(req.body?.attachments);
  if (error) return res.status(400).json({ error });
  const requestedMentions = Array.isArray(req.body?.mentionMemberIds)
    ? [...new Set(req.body.mentionMemberIds.filter((id) => typeof id === 'string' && UUID_RE.test(id) && id !== req.memberId))]
    : [];
  if (requestedMentions.length > MAX_MENTIONS) {
    return res.status(400).json({ error: `한 번에 최대 ${MAX_MENTIONS}명까지 호출할 수 있습니다.` });
  }
  if (!content && attachments.length === 0 && requestedMentions.length === 0) {
    return res.status(400).json({ error: '댓글 내용을 입력해주세요.' });
  }
  const memo = await loadOrgMemo(req.params.id, req.memberId);
  if (!memo) return res.status(404).json({ error: '메모를 찾을 수 없습니다.' });

  // Only active members of the memo's org can be called.
  const { rows: mentionRows } = requestedMentions.length
    ? await query(`select id from members where id = any($1::uuid[]) and org_id = $2 and status = 'active'`, [
        requestedMentions,
        memo.org_id,
      ])
    : { rows: [] };
  const mentionIds = mentionRows.map((r) => r.id);

  const me = await currentMember(req.memberId);
  const client = await pool.connect();
  let commentId;
  try {
    await client.query('begin');
    const { rows } = await client.query(
      'insert into memo_comments (memo_id, author_member_id, author_name, content) values ($1, $2, $3, $4) returning id',
      [memo.id, req.memberId, me?.name ?? '', content],
    );
    commentId = rows[0].id;
    for (const a of attachments) {
      await client.query(
        `insert into memo_comment_attachments (comment_id, kind, file_name, content_type, size_bytes, data)
         values ($1, $2, $3, $4, $5, $6)`,
        [commentId, a.kind, a.fileName, a.contentType, a.data.length, a.data],
      );
    }
    for (const memberId of mentionIds) {
      await client.query('insert into memo_comment_mentions (comment_id, member_id) values ($1, $2)', [commentId, memberId]);
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

  const farmLabel = memo.farm_name ?? '미지정';
  const link = `/memo?memo=${memo.id}&comments=1`;
  const flat = content.replace(/\s+/g, ' ');
  const preview =
    (flat.length > 80 ? `${flat.slice(0, 80)}…` : flat) ||
    (attachments.length ? `${attachments.some((a) => a.kind === 'file') ? '파일' : '사진'}을 첨부했어요.` : '');

  // 호출: always delivered, so a handed-over job can't be missed.
  if (mentionIds.length) {
    await notifyMembers({
      memberIds: mentionIds,
      type: 'mention',
      title: `${me?.name ?? ''}님이 호출했어요 · ${farmLabel}`,
      body: preview || '메모 댓글에서 호출했어요.',
      link,
    });
  }

  // Tell the memo's author and everyone else already in the thread (except
  // those just called, who already got the 호출).
  const { rows: threadRows } = await query(
    'select distinct author_member_id as id from memo_comments where memo_id = $1 and author_member_id is not null',
    [memo.id],
  );
  const recipients = [...new Set([memo.author_member_id, ...threadRows.map((r) => r.id)])].filter(
    (id) => id && id !== req.memberId && !mentionIds.includes(id),
  );
  if (recipients.length) {
    await notifyMembers({
      memberIds: recipients,
      type: 'comment',
      title: `새 댓글 · ${farmLabel}`,
      body: `${me?.name ?? ''}: ${preview}`,
      link,
    });
  }
  res.status(201).json(await loadCommentJson(commentId));
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
