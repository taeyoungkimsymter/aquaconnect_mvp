// 메모 자동 분류·폐사 수치 추출 — symterAI src/lib/memo-analysis.ts 이식.
// 외부 호출 없이 메모 원문에서 매번 계산한다. 확신할 수 없는 수치는 추측하지 않는다:
// 폐사 마리수는 문장에서 폐사와 가까운 숫자 한 개가 분명할 때만 뽑고, 그렇지 않으면
// '수량 미기재'로 따로 센다(합계에 넣지 않는다).

/** 표시 순서이자 대표 주제를 고르는 우선순위(앞이 우선) */
export const TOPICS = [
  '폐사',
  '질병 의심·검사',
  '접종',
  '섭식·활력 이상',
  '수질·수온',
  '방역·소독',
  '시설·장비',
  '사료·급이',
  '입식·출하',
  '점검·방문',
  '기타',
];

const TOPIC_RULES = [
  ['질병 의심·검사', /의심|병성감정|검사|진단|증상|감염|병변|궤양|출혈|기생충|바이러스|세균|백점|복수|부종|검체|PCR|패혈/],
  ['접종', /접종|백신/],
  [
    '섭식·활력 이상',
    /섭식\s*(?:저하|감소|부진|불량|이상|없)|식욕\s*(?:저하|감소|부진|없)|(?:사료|먹이)\s*(?:섭취|반응)\s*(?:저하|감소|부진|불량)|안\s*먹|활력\s*(?:저하|감소|부족)|유영\s*(?:이상|불량|저하)|무기력|가라앉|수면\s*부유|쏠림|행동\s*이상/,
  ],
  ['수질·수온', /수온|수질|용존산소|\bDO\b|염분|\bpH\b|암모니아|적조|녹조|산소\s*부족|탁도|해황/],
  ['방역·소독', /소독|방역|약욕|살균/],
  ['시설·장비', /청소|세척|수리|파손|고장|보수|정비|교체|설치/],
  ['사료·급이', /사료|급이|먹이\s*공급|배합/],
  ['입식·출하', /입식|출하|종자|치어|이송|선별|분양|방류|반입/],
  ['점검·방문', /점검|순회|방문|현장|상담/],
];

const NORMAL = /특이\s*사항\s*(?:은\s*)?없|이상\s*(?:은\s*)?없|이상\s*무|양호|정상/;

// ───────── 폐사 수치 ─────────

const DEATH_WORD = /폐사|사망|죽었|죽은|죽어|폐어|떼죽음/;
/** '폐사 없음', '폐사는 없', '폐사 0마리', '폐사 확인되지 않' */
const NO_DEATH = /(?:폐사|사망)\s*(?:개체|어)?\s*(?:은|는|이|가)?\s*(?:없|무(?![가-힣])|0\s*(?:마리|미|건|수)?(?![\d])|X\b|확인되지\s*않)/;
const CUMULATIVE = /누적|지금까지|현재까지|합계|총계/;
const APPROX = /약\s*\d|대략|정도|가량|쯤|내외/;
const QUALITATIVE = /소량|소수|일부|다수|대량|상당수|많은\s*(?:수|개체)|수십|수백|수천|집단|떼죽음/;

const UNIT = '(?:마리|미(?![가-힣])|개체|수(?![가-힣]))';
const QTY = new RegExp(`(\\d{1,3}(?:,\\d{3})+|\\d+(?:\\.\\d+)?)\\s*(만|천|백)?\\s*${UNIT}`, 'g');
const RANGE = new RegExp(`(\\d+(?:\\.\\d+)?)\\s*[~∼\\-–]\\s*(\\d{1,3}(?:,\\d{3})+|\\d+(?:\\.\\d+)?)\\s*(만|천|백)?\\s*${UNIT}`, 'g');
const RATE = /(?:폐사율|사망률)\s*(?:은|는)?\s*(?:약\s*)?(\d+(?:\.\d+)?)\s*%|(\d+(?:\.\d+)?)\s*%\s*(?:가\s*|의\s*)?(?:폐사|사망)/;
/** 숫자 뒤에 이런 말이 오면 폐사 수가 아니라 전체 사육 수 등이다: "500마리 중 30마리 폐사" */
const POPULATION_AFTER = /^\s*(?:중|중에서|가운데|입식|사육|보유|수용|투입|출하|이송|접종|선별)/;
const POPULATION_BEFORE = /(?:입식|사육|보유|수용|투입|출하|이송|접종|선별|총|전체)\s*(?:수량|개체|어)?\s*[:\s]*$/;
const MULT = { 만: 10000, 천: 1000, 백: 100 };
const MAX_DISTANCE = 14;

const toNumber = (s, mult) => Number(s.replace(/,/g, '')) * (mult ? MULT[mult] : 1);

/** 문장 하나에서 수량 후보(범위 포함)를 모은다. */
function candidates(sentence) {
  const out = [];
  const taken = [];
  for (const m of sentence.matchAll(RANGE)) {
    const hi = toNumber(m[2], m[3]);
    const lo = toNumber(m[1], m[3]);
    const start = m.index;
    const end = start + m[0].length;
    taken.push([start, end]);
    if (lo <= hi) out.push({ min: lo, max: hi, start, end, atLeast: false });
  }
  for (const m of sentence.matchAll(QTY)) {
    const start = m.index;
    const end = start + m[0].length;
    if (taken.some(([a, b]) => start < b && end > a)) continue;
    const n = toNumber(m[1], m[2]);
    out.push({ min: n, max: n, start, end, atLeast: /^\s*(?:이상|넘)/.test(sentence.slice(end)) });
  }
  return out.filter(
    (c) => !POPULATION_AFTER.test(sentence.slice(c.end)) && !POPULATION_BEFORE.test(sentence.slice(Math.max(0, c.start - 12), c.start)),
  );
}

/** 숫자 바로 앞뒤에 '누적' 같은 말이 붙어 있으면 누적치다(같은 문장의 다른 숫자는 영향받지 않는다). */
const isCumulative = (s, c) => CUMULATIVE.test(s.slice(Math.max(0, c.start - 8), c.start)) || /^\s*(?:누적|합계)/.test(s.slice(c.end));

function pick(list) {
  if (!list.length) return { reason: null, values: [] };
  const [best, second] = list;
  if (second && second.d - best.d <= 2 && (second.c.min !== best.c.min || second.c.max !== best.c.max)) {
    return { reason: `수치가 여러 개(${best.c.min}, ${second.c.min})라 확정하지 못함`, values: [best.c.min, second.c.min] };
  }
  return { best: best.c, reason: null, values: [] };
}

function parseSentence(s, anchor) {
  const rateM = RATE.exec(s);
  const rate = rateM ? Number(rateM[1] ?? rateM[2]) : null;
  const qualitative = QUALITATIVE.exec(s)?.[0] ?? null;
  const near = candidates(s)
    .map((c) => ({ c, d: Math.min(...anchor.map((x) => (x >= c.start && x <= c.end ? 0 : Math.min(Math.abs(x - c.start), Math.abs(x - c.end))))) }))
    .filter(({ d }) => d <= MAX_DISTANCE)
    .sort((x, y) => x.d - y.d);
  const normal = pick(near.filter(({ c }) => !isCumulative(s, c)));
  const cumulative = pick(near.filter(({ c }) => isCumulative(s, c)));
  return {
    min: normal.best?.min ?? null,
    max: normal.best?.max ?? null,
    approx: APPROX.test(s),
    atLeast: normal.best?.atLeast ?? false,
    cum: cumulative.best ? { min: cumulative.best.min, max: cumulative.best.max } : null,
    qualitative,
    rate,
    reason: normal.reason,
    values: normal.values,
  };
}

/** "폐사율 변화 없음"처럼 숫자(%) 없이 말만 나온 '폐사율'은 폐사가 있었다는 뜻이 아니다. */
const withoutBareRate = (s) => (RATE.test(s) ? s : s.replace(/폐사율|사망률/g, ''));

/** 메모 한 건의 폐사 정보. 폐사 표현이 없고 종류도 폐사가 아니면 null */
export function parseDeaths(body, kind) {
  const sentences = body.split(/(?<=[.。!?])\s+|\n|;/).map((s) => s.trim()).filter(Boolean);
  const hits = sentences.filter((s) => DEATH_WORD.test(withoutBareRate(s)) && !NO_DEATH.test(s));

  if (!hits.length) {
    if (kind !== '폐사') return null;
    // 종류가 폐사인데 '폐사' 표현이 없는 메모(예: "B구역 30마리 수거"): 숫자가 하나뿐일 때만 인정
    const all = sentences.flatMap((s) => candidates(s));
    const only = all.length === 1 ? all[0] : null;
    return {
      min: only?.min ?? null,
      max: only?.max ?? null,
      approx: false,
      qualitative: null,
      cumulative: null,
      rate: null,
      reason: only ? null : '종류는 폐사이나 수량을 찾지 못함',
      candidates: all.map((c) => c.min),
    };
  }

  const results = hits.map((s) => parseSentence(s, [...s.matchAll(new RegExp(DEATH_WORD, 'g'))].map((m) => m.index)));
  const rate = results.find((r) => r.rate !== null)?.rate ?? null;
  const qualitative = results.find((r) => r.qualitative)?.qualitative ?? null;
  const approx = results.some((r) => r.approx);
  const cumulative = results.find((r) => r.cum)?.cum ?? null;

  // 같은 숫자가 여러 번 나오면 같은 이야기를 반복한 것으로 보고 한 번만 센다. 서로 다른 숫자가 여러 개면 확정하지 않는다.
  const distinct = new Map(results.filter((r) => r.min !== null).map((r) => [`${r.min}-${r.max}`, r]));
  const ambiguous = results.find((r) => r.reason);
  if (distinct.size > 1 || (ambiguous && !distinct.size)) {
    const vals = distinct.size > 1 ? [...distinct.values()].map((r) => r.min) : ambiguous.values;
    return {
      min: null,
      max: null,
      approx,
      qualitative,
      cumulative,
      rate,
      reason: distinct.size > 1 ? `수치가 여러 개(${vals.join(', ')})라 확정하지 못함` : ambiguous.reason,
      candidates: vals,
    };
  }
  const one = [...distinct.values()][0];
  return {
    min: one?.min ?? null,
    max: one?.max ?? null,
    approx,
    qualitative,
    cumulative,
    rate,
    reason: one?.atLeast ? `${one.min}마리 이상으로 적혀 있어 최소치로 집계` : null,
    candidates: [],
  };
}

// ───────── 한 건 분석 ─────────

function statusOf(body) {
  if (/대기|의뢰(?:함|했|중|하였)|결과\s*(?:나오|전|미확인)/.test(body)) return '검사 대기';
  if (/관찰\s*필요|추가\s*관찰|지켜|모니터링\s*필요|확인\s*필요|추가\s*확인\s*(?:필요|요망|예정)/.test(body)) return '관찰 필요';
  if (/의심/.test(body)) return '의심';
  if (/완료|조치함|처치함|해결|회복|호전|정상화|음성/.test(body)) return '해소·양호';
  return null;
}

export function analyzeMemo(m) {
  const body = m.body;
  const deaths = parseDeaths(body, m.kind);
  const found = new Set();
  if (deaths || m.kind === '폐사') found.add('폐사');
  if (m.kind === '접종') found.add('접종');
  if (m.kind === '방문') found.add('점검·방문');
  // 폐사가 없다고 쓴 문장("폐사 없음")이 다른 주제를 만들지 않도록 규칙은 원문 전체에 적용한다.
  for (const [topic, re] of TOPIC_RULES) if (re.test(body)) found.add(topic);
  if (!found.size) found.add('기타');
  const topics = TOPICS.filter((t) => found.has(t));
  const primary = topics[0];

  const uncertain = [];
  if (deaths?.reason) uncertain.push(deaths.reason);
  else if (deaths && deaths.min === null && deaths.cumulative === null) uncertain.push(deaths.qualitative ? `폐사 수량 미기재("${deaths.qualitative}")` : '폐사 수량 미기재');
  if (deaths && deaths.min === null && deaths.cumulative !== null) uncertain.push('누적 수치만 적혀 있어 이번 기간 폐사 마리수로 집계하지 못함');
  if (primary === '기타') uncertain.push('분류하지 못한 메모');
  return { topics, primary, deaths, status: statusOf(body), normal: NORMAL.test(body) && !deaths, uncertain };
}

export const analyzeMemos = (memos) => memos.map((m) => ({ ...m, a: analyzeMemo(m) }));

// ───────── 양식장 집계 ─────────

const OPEN = ['검사 대기', '관찰 필요', '의심'];

export function summarizeFarm(items) {
  const sorted = [...items].sort((a, b) => a.date.localeCompare(b.date) || a.id - b.id);
  const topics = TOPICS.map((topic) => ({ topic, count: sorted.filter((m) => m.a.primary === topic).length })).filter((t) => t.count > 0);

  const day = new Map();
  const cumulative = [];
  const rates = [];
  let min = 0, max = 0, unknown = 0, events = 0;
  for (const m of sorted) {
    const d = m.a.deaths;
    if (!d) continue;
    events++;
    const row = day.get(m.date) ?? { date: m.date, min: 0, max: 0, unknown: 0 };
    if (d.min !== null && d.max !== null) {
      min += d.min;
      max += d.max;
      row.min += d.min;
      row.max += d.max;
    } else if (d.cumulative === null) {
      unknown++;
      row.unknown++;
    }
    if (d.cumulative) cumulative.push({ date: m.date, ...d.cumulative });
    if (d.rate !== null) rates.push({ date: m.date, rate: d.rate });
    day.set(m.date, row);
  }
  return {
    total: sorted.length,
    topics,
    sorted,
    deaths: { events, min, max, unknown, byDay: [...day.values()], cumulative, rates },
    open: sorted.filter((m) => m.a.status && OPEN.includes(m.a.status)),
  };
}

/** "30마리" / "약 3~5마리" 같은 표시 */
export function formatCount(min, max, approx = false) {
  const body = min === max ? `${min.toLocaleString('ko-KR')}마리` : `${min.toLocaleString('ko-KR')}~${max.toLocaleString('ko-KR')}마리`;
  return approx ? `약 ${body}` : body;
}
