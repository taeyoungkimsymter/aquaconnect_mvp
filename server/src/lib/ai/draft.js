// 구조화된 리포트 초안의 형식 검사·근거 검증·본문 렌더링 — symterAI src/lib/report-draft.ts 이식.
// 항목마다 근거 메모 번호(evidence)를 단다. 근거는 코드가 다시 확인하고, 맞지 않으면 지우지 않고
// '확인 필요' flag 를 달아 전문가가 보게 한다.

import { FARM_SECTIONS } from './prompts.js';

/** memo: 메모 근거 / measure: 현장 실측 / public: 외부 관측·공공데이터 / suggestion: 제안 / note: 안내 */
export const ITEM_KINDS = ['memo', 'measure', 'public', 'suggestion', 'note'];

const PREFIX = {
  measure: '〔현장 실측〕 ',
  public: '〔외부 관측·공공데이터〕 ',
  suggestion: '〔제안·전문가 검토 필요〕 ',
};

/** 근거가 반드시 있어야 하는 섹션(메모에서 나온 사실을 쓰는 곳) */
const NEED_EVIDENCE = new Set([FARM_SECTIONS[0], FARM_SECTIONS[1], FARM_SECTIONS[2], FARM_SECTIONS[5]]);
/** "기록이 없습니다", "근거가 부족합니다" 같은 안내 문장은 근거가 없어도 된다 */
const ABSENCE = /없습니다|없음|부족|확인되지 않|비교할 수 없|연결되지 않|사용하지 않|미연동/;
/** 메모에 없으면 쓰면 안 되는 단정 표현(진단 확정·처치 지시) */
const DIAGNOSIS = /확진|진단(?:됨|되었|했|하였)|(?:으)?로\s*판명|감염(?:됨|되었|된\s*것)|투약하|투여하|처방하|치료(?:하세요|하십시오|해\s*주십시오|가\s*필요합니다)/g;

/** 개체 수량 표현("6마리", "1,200미"). 양식장명·수조 번호·날짜 속 숫자는 단위가 없으므로 수량이 아니다. */
const QTY = /(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(만|천|백)?\s*(마리|미(?![가-힣])|개체)/g;
const MULT = { 만: 10000, 천: 1000, 백: 100 };
const qtyOf = (n, mult) => Number(n.replace(/,/g, '')) * (mult ? MULT[mult] : 1);
const quantitiesIn = (s) => new Set([...s.matchAll(QTY)].map((m) => qtyOf(m[1], m[2])));

/** 메모에 '조치 없음'이라고 직접 적혀 있지 않은데 "조치는 없으며"라고 쓴 문장 */
const NO_ACTION = /(조치|처치|대응)(?:는|가|를|도)?\s*(?:전혀\s*)?(?:없|(?:취하|취해|하|수행하|수행되|이루어지|시행되|실시되|진행되|이행되)지\s*(?:않|못))((?:았|었)?(?:습니다|다)|(?:았|었)?(?:으며|고)|음|았|었)?/;
const NO_ACTION_IN_MEMO = /(?:조치|처치|대응)(?:는|가|를|도)?\s*(?:전혀\s*)?(?:없|취하지|하지\s*않|안\s*함|무)|무\s*조치/;
/** 비교할 이전 기간 자료가 없을 때 쓰면 안 되는 변화 단정 표현 */
const CHANGE = /증가|감소|호전|악화|개선|늘었|줄었|나아졌|나빠졌/g;

const numbersIn = (s) => new Set((s.match(/\d+(?:\.\d+)?/g) ?? []).map(Number));

/** 모델 답변(JSON 문자열) → 초안. 형식이 맞지 않으면 null */
export function parseDraft(text) {
  const body = text.replace(/^```\w*\n|\n```$/g, '');
  let parsed;
  try {
    parsed = JSON.parse(body.slice(body.indexOf('{'), body.lastIndexOf('}') + 1));
  } catch {
    return null;
  }
  if (!parsed || !Array.isArray(parsed.sections)) return null;
  const sections = [];
  for (const s of parsed.sections) {
    if (!s || !FARM_SECTIONS.includes(s.title) || !Array.isArray(s.items)) continue;
    const items = s.items
      .filter((it) => it && typeof it.text === 'string' && it.text.trim())
      .map((it) => ({
        text: it.text.trim(),
        evidence: (Array.isArray(it.evidence) ? it.evidence : []).map((n) => Number(String(n).replace('#', ''))).filter(Number.isInteger),
        kind: ITEM_KINDS.includes(it.kind) ? it.kind : 'note',
        ...(Array.isArray(it.comment_refs) && it.comment_refs.length ? { comment_refs: it.comment_refs.map(String) } : {}),
      }));
    sections.push({ title: s.title, items });
  }
  if (!FARM_SECTIONS.every((t) => sections.some((s) => s.title === t))) return null;
  return { sections };
}

/**
 * 초안 검증: ① 입력에 없는 메모 번호 ② 근거 없는 사실 ③ 입력 자료에 없는 숫자 ④ 메모에 없는 진단·처치 표현.
 * source = { memos: [{ n, date, kind, body }], prev: [...] | null, comments: [{ key, date, late }] }
 */
export function verifyDraft(draft, source, input) {
  const commentKeys = new Set(source.comments.map((c) => c.key));
  const known = new Map([...source.memos, ...(source.prev ?? [])].map((m) => [m.n, m.body]));
  const allowed = numbersIn(input);
  const allowedQty = quantitiesIn(input);
  const memoText = [...known.values()].join('\n');
  const checks = [];
  const sections = FARM_SECTIONS.map((title) => {
    const items = (draft.sections.find((s) => s.title === title)?.items ?? []).map((it) => {
      const problems = [];
      const bad = it.evidence.filter((id) => !known.has(id));
      if (bad.length) problems.push(`입력에 없는 메모 번호(${bad.join(', ')})`);
      const evidence = it.evidence.filter((id) => known.has(id));
      const badComments = (it.comment_refs ?? []).filter((k) => !commentKeys.has(k));
      if (badComments.length) problems.push(`입력에 없는 댓글 번호(${badComments.join(', ')})`);
      const commentRefs = (it.comment_refs ?? []).filter((k) => commentKeys.has(k));
      if (NEED_EVIDENCE.has(title) && (it.kind === 'memo' || it.kind === 'measure') && !evidence.length && !commentRefs.length && !ABSENCE.test(it.text)) {
        problems.push('근거 메모 없음');
      }
      // 마리수는 원문(메모·댓글·코드 집계)에 '숫자+마리' 로 적힌 것만 쓴다.
      const badQty = [...new Set([...it.text.matchAll(QTY)].filter((m) => !allowedQty.has(qtyOf(m[1], m[2]))).map((m) => m[0].trim()))];
      let text = it.text;
      if (badQty.length) {
        text = text.replace(QTY, (m, n, mult) => (allowedQty.has(qtyOf(n, mult)) ? m : '〔수량 확인 필요〕'));
        problems.push(`원문에 마릿수로 적히지 않은 수량(${badQty.join(', ')}) → 수량 확인 필요로 바꿈`);
      }
      // 조치가 기록되지 않은 것을 '조치가 없었다'고 단정하지 않는다.
      if (!NO_ACTION_IN_MEMO.test(memoText) && NO_ACTION.test(text)) {
        text = text.replace(new RegExp(NO_ACTION.source, 'g'), (_m, noun, tail) =>
          tail && /(?:습니다|다)$/.test(tail)
            ? `${noun} 기록이 없습니다`
            : `${noun} 기록 없음${tail && /으며$/.test(tail) ? '이며' : tail && /고$/.test(tail) ? '이고' : ''}`,
        );
        problems.push("조치가 없었다고 단정함 → '조치 기록 없음'으로 바꿈(메모에 없다고 적히지 않음)");
      }
      if (!source.prev) {
        const change = [...new Set(text.match(CHANGE) ?? [])].filter((t) => !memoText.includes(t));
        if (change.length) problems.push(`비교할 이전 기간 자료 없이 변화 표현 사용(${change.join(', ')})`);
      }
      const extra = [...numbersIn(it.text)].filter((n) => !allowed.has(n));
      if (extra.length) problems.push(`입력 자료에 없는 수치(${extra.join(', ')})`);
      const terms = [...new Set(text.match(DIAGNOSIS) ?? [])].filter((t) => !memoText.includes(t));
      if (terms.length) problems.push(`메모에 없는 진단·처치 표현(${terms.join(', ')})`);
      if (problems.length) checks.push({ section: title, text: it.text, problem: problems.join(' / ') });
      return {
        text,
        kind: it.kind,
        evidence,
        ...(commentRefs.length ? { comment_refs: commentRefs } : {}),
        ...(problems.length ? { flag: problems.join(' / ') } : {}),
      };
    });
    return { title, items };
  });
  return { draft: { sections }, checks };
}

const day = (date) => `${Number(date.slice(5, 7))}월 ${Number(date.slice(8))}일`;

/** 구조화된 초안 → 본문("## 제목" + "- 항목"). 근거 메모는 날짜·종류로 표시한다(메모 번호는 화면에서 의미가 없으므로). */
export function renderDraft(draft, source) {
  const memo = new Map([...source.memos, ...(source.prev ?? [])].map((m) => [m.n, m]));
  const cite = (ids) => {
    const labels = [...new Set(ids.map((id) => memo.get(id)).filter(Boolean).map((m) => (m.kind === '메모' ? day(m.date) : `${day(m.date)} ${m.kind}`)))];
    if (!labels.length) return '';
    const shown = labels.length > 4 ? `${labels.slice(0, 3).join('·')} 외 ${labels.length - 3}건` : labels.join('·');
    return ` 〔근거: ${shown} 메모〕`;
  };
  const comment = new Map(source.comments.map((c) => [c.key, c]));
  const citeComments = (keys = []) => {
    const labels = [...new Set(keys.map((k) => comment.get(k)).filter(Boolean).map((c) => `${day(c.date)} 댓글${c.late ? '(기간 이후 추가 기록)' : ''}`))];
    return labels.length ? ` 〔근거 댓글: ${labels.join('·')}〕` : '';
  };
  return draft.sections
    .map((s) => {
      const lines = s.items.length
        ? s.items.map((it) => `- ${PREFIX[it.kind] ?? ''}${it.text}${cite(it.evidence)}${citeComments(it.comment_refs)}${it.flag ? ` 〔확인 필요: ${it.flag}〕` : ''}`)
        : ['- 이 항목에 해당하는 기록이 없습니다.'];
      return `## ${s.title}\n${lines.join('\n')}`;
    })
    .join('\n\n');
}
