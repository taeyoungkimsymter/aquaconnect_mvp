// 양식장 AI 관리 리포트 — symterAI 의 관리 리포트(메모 선택 → 구조화 입력 → AI 초안 → 근거 검증) 이식.
// 숫자(폐사 집계·건수)는 모두 여기서 코드로 계산해 입력에 넣고, AI 는 그 값을 옮겨 쓰기만 한다.
// 메모 uuid 는 AI 에게 보이지 않고 [#1], [#2] 같은 순번으로 바꿔 보낸다(근거 번호 검증도 이 순번으로 한다).

import { fetchRealtimeObservations, pickPreferredObservation } from '../nifs.js';
import { fetchRedTide } from '../redtide.js';
import { parseDraft, renderDraft, verifyDraft } from './draft.js';
import { analyzeMemos, formatCount, summarizeFarm } from './memoAnalysis.js';
import { AiError, chat } from './model.js';
import { FARM_REPORT_PROMPT, FARM_PROMPT_VERSION } from './prompts.js';

const NL = '\n';
const KST = 9 * 3600_000;

/** timestamptz → 한국 날짜(YYYY-MM-DD) */
export const kstDate = (d) => new Date(new Date(d).getTime() + KST).toISOString().slice(0, 10);

/** 메모 태그 → 기록 종류(폐사·접종·방문 등). 분석 규칙이 종류를 단서로 쓴다. */
const KIND_TAGS = ['폐사', '접종', '방문', '배달', '문의', '할일'];
const kindOf = (tags) => KIND_TAGS.find((t) => tags.includes(t)) ?? '메모';
const authorLabel = (type) => (type === 'farm' ? '어가 작성' : '관리원 작성');
const day = (date) => `${Number(date.slice(5, 7))}월 ${Number(date.slice(8))}일`;

/** 메모 옆에 붙이는 분석 표시: [폐사 30마리] [검사 대기] */
function tags(m) {
  const out = [];
  const d = m.a.deaths;
  if (d) {
    const amount = d.min !== null && d.max !== null ? formatCount(d.min, d.max, d.approx) : d.qualitative ? `수량 미기재(${d.qualitative})` : '수량 미기재';
    out.push(`폐사 ${amount}${d.cumulative ? ` / 누적 ${formatCount(d.cumulative.min, d.cumulative.max)}` : ''}${d.rate !== null ? ` / 폐사율 ${d.rate}%` : ''}`);
  }
  if (m.a.status) out.push(m.a.status);
  return out.map((t) => `[${t}]`).join(' ');
}

/** 코드가 계산한 집계. AI 는 이 숫자를 그대로 쓴다. */
function tally(an) {
  const d = an.deaths;
  const lines = [`- 선택된 기록 ${an.total}건`];
  if (an.topics.length) lines.push(`- 대표 주제별 건수: ${an.topics.map((t) => `${t.topic} ${t.count}건`).join(', ')}`);
  if (d.events) {
    const parts = [`수량이 확정된 마리수 합계 ${d.max > 0 ? formatCount(d.min, d.max) : '없음'}`, `폐사가 적힌 기록 ${d.events}건`];
    if (d.unknown) parts.push(`수량 미기재 ${d.unknown}건(합계에 포함하지 않음)`);
    if (d.cumulative.length) parts.push(`누적치로만 적힌 값 ${d.cumulative.map((c) => `${day(c.date)} ${formatCount(c.min, c.max)}`).join(', ')}(합계에 포함하지 않음)`);
    if (d.rates.length) parts.push(`폐사율 ${d.rates.map((r) => `${day(r.date)} ${r.rate}%`).join(', ')}`);
    lines.push(`- 폐사: ${parts.join(' / ')}`);
    const days = d.byDay.filter((x) => x.max > 0);
    if (days.length) lines.push(`- 날짜별 확정 폐사: ${days.map((x) => `${day(x.date)} ${formatCount(x.min, x.max)}`).join(', ')}`);
  } else lines.push('- 폐사: 폐사가 적힌 기록 없음');
  lines.push(`- 후속 확인이 필요한 기록(검사 대기·관찰 필요·의심): ${an.open.length}건`);
  return lines;
}

async function publicData(farm, from, to) {
  const lines = [];
  let temp = null;
  try {
    temp = pickPreferredObservation(await fetchRealtimeObservations({ station: farm.nearest_station_code }));
  } catch {
    temp = null;
  }
  lines.push(
    temp
      ? `- 관측소 수온: ${farm.nearest_station_name} 관측소 ${temp.layer} ${temp.waterTempC}℃ (관측 ${temp.observedDate} ${temp.observedTime}, 리포트 작성 시점의 실시간 값이며 기간 평균이 아님)`
      : `- 관측소 수온: 수온 자료 없음(${farm.nearest_station_name} 관측소 조회 실패)`,
  );
  let redTide = null;
  try {
    const data = await fetchRedTide();
    // 기간 시작 3일 전부터 기간 끝까지 발표된 속보만 같은 기간의 자료로 본다.
    const since = kstDate(new Date(new Date(`${from}T00:00:00+09:00`).getTime() - 3 * 86400_000));
    redTide = (data.recent ?? []).find((r) => r.reportDate >= since && r.reportDate <= to) ?? null;
  } catch {
    redTide = undefined;
  }
  if (redTide === undefined) lines.push('- 적조 속보(국립수산과학원): 조회 실패 — 자료 없음');
  else if (!redTide) lines.push('- 적조 속보(국립수산과학원): 기간 중 발표된 속보 없음');
  else {
    const occ = (redTide.occurrences ?? []).slice(0, 5).map((o) => [o.area, o.organism].filter(Boolean).join(' ')).filter(Boolean);
    lines.push(`- 적조 속보(국립수산과학원) ${redTide.reportDate} 발표: ${occ.join(', ') || '세부 해역 정보 없음'} (전국 해역 대상 속보이며 이 양식장 해역과 같다는 뜻이 아님)`);
  }
  return lines;
}

/**
 * memos: 선택된 기간 메모 [{ id, content, tags, author_type, author_name, created_at }]
 * comments: [{ memo_id, author_name, content, created_at }]
 * prevMemos: 직전 같은 길이 기간의 메모(비교용, 없으면 [])
 */
export async function draftFarmReport({ farm, from, to, memos, comments, prevMemos, candidates, model, onResult }) {
  const sorted = [...memos].sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
  const numbered = sorted.map((m, i) => ({
    id: i + 1,
    n: i + 1,
    uuid: m.id,
    date: kstDate(m.created_at),
    kind: kindOf(m.tags ?? []),
    body: m.content,
    author: m.author_name,
    authorType: m.author_type,
  }));
  const prevSorted = [...prevMemos].sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
  const prevNumbered = prevSorted.map((m, i) => ({
    id: numbered.length + i + 1,
    n: numbered.length + i + 1,
    uuid: m.id,
    date: kstDate(m.created_at),
    kind: kindOf(m.tags ?? []),
    body: m.content,
  }));
  const byUuid = new Map(numbered.map((m) => [m.uuid, m]));
  const commentRows = [];
  const counter = new Map();
  for (const c of [...comments].sort((a, b) => new Date(a.created_at) - new Date(b.created_at))) {
    const memo = byUuid.get(c.memo_id);
    if (!memo) continue;
    const k = (counter.get(memo.n) ?? 0) + 1;
    counter.set(memo.n, k);
    const date = kstDate(c.created_at);
    commentRows.push({ key: `C${memo.n}-${k}`, memoN: memo.n, date, late: date > to, author: c.author_name, body: c.content });
  }

  const analyzed = analyzeMemos(numbered);
  const an = summarizeFarm(analyzed);
  const prevAn = prevNumbered.length ? summarizeFarm(analyzeMemos(prevNumbered)) : null;

  const memoLines = an.sorted.map((m) => `[#${m.n}] ${m.date} (${m.kind}) [${authorLabel(m.authorType)} · ${m.author}] ${m.body.replace(/\s+/g, ' ')} ${tags(m)}`.trimEnd());
  const commentBlock = commentRows.length
    ? [
        '[선택한 메모에 달린 댓글 — 메모가 아닌 별도 자료. 폐사 건수·마리수 집계에 넣지 않는다. 같은 사건을 다시 말한 것일 수 있다]',
        ...commentRows.map((c) => `- ${c.key} (메모 [#${c.memoN}]에 달림) ${c.date} ${c.author}: ${c.body.replace(/\s+/g, ' ')}${c.late ? ' 〔기간 이후 추가 기록〕' : ''}`),
      ].join(NL)
    : '';
  const prevBlock = prevAn
    ? [
        `[이전 기간] 직전 같은 길이 기간: 현장 메모 ${prevAn.total}건, 폐사 기록 ${prevAn.deaths.events}건`,
        `- 이전 기간 주제: ${prevAn.topics.map((t) => `${t.topic} ${t.count}건`).join(', ') || '없음'}`,
        `- 이전 기간 후속 확인 필요: ${prevAn.open.length ? prevAn.open.map((o) => `[#${o.n}] ${o.date} ${o.a.primary}(${o.a.status})`).join(', ') : '없음'}`,
        '- 이전 기간 메모 원문:',
        ...prevAn.sorted.map((m) => `  - [#${m.n}] ${m.date} (${m.kind}) ${m.body.replace(/\s+/g, ' ')}`),
      ].join(NL)
    : '[이전 기간] 자료 없음 — 이전 기간 대비 비교 불가';
  const openLines = an.open.length
    ? an.open.map((o) => `- [#${o.n}] ${o.date} ${o.a.primary}: 상태 ${o.a.status}`).join(NL)
    : '(없음)';

  const input = [
    `기간: ${from} ~ ${to} (한국 시간)${NL}양식장: ${farm.name} / 지역: ${farm.region || '미입력'} / 주소: ${farm.address || '미입력'}`,
    [
      '[선택 범위 — 사용자가 고른 기록만 입력되었다]',
      `- 기간 내 메모 ${candidates}건 중 ${numbered.length}건 선택. 연결 댓글: ${commentRows.length ? `${commentRows.length}개 포함` : '포함하지 않음'}.`,
      "- 선택하지 않은 기록과 기록이 없는 날은 '문제 없음'이 아니라 '기록 없음'이다.",
      `- 작성 주체: 관리원 작성 ${numbered.filter((m) => m.authorType !== 'farm').length}건, 어가 작성 ${numbered.filter((m) => m.authorType === 'farm').length}건`,
    ].join(NL),
    `[집계 — 코드가 계산한 값. 그대로 쓰고 직접 계산하지 않는다]${NL}${tally(an).join(NL)}`,
    `[후속 확인 필요]${NL}${openLines}`,
    `[이번 기간 현장 메모 — 1순위 근거]${NL}${memoLines.length ? memoLines.join(NL) : '(메모 없음)'}`,
    commentBlock,
    prevBlock,
    `[공공데이터 — 외부 관측(보조 자료). 양식장 수조 실측값이 아님]${NL}${(await publicData(farm, from, to)).join(NL)}`,
  ]
    .filter(Boolean)
    .join(NL + NL);

  const { text, model: usedModel } = await chat(FARM_REPORT_PROMPT, input, { model, maxTokens: 16000, json: true, onResult });
  const raw = parseDraft(text);
  if (!raw) throw new AiError('AI가 정해진 형식(JSON)으로 작성하지 못했습니다. 다시 만들어 주세요.');
  const source = {
    memos: numbered,
    prev: prevNumbered.length ? prevNumbered : null,
    comments: commentRows,
  };
  const checked = verifyDraft(raw, source, input);
  const body = renderDraft(checked.draft, source);

  return {
    model: usedModel,
    promptVersion: FARM_PROMPT_VERSION,
    raw,
    draft: checked.draft,
    checks: checked.checks,
    body,
    snapshot: {
      input,
      memos: numbered.map((m) => ({ n: m.n, id: m.uuid, date: m.date, kind: m.kind, author: m.author, authorType: m.authorType, body: m.body })),
      prevMemos: prevNumbered.map((m) => ({ n: m.n, id: m.uuid, date: m.date, kind: m.kind, body: m.body })),
      comments: commentRows,
    },
  };
}
