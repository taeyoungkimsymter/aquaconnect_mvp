// 수산 뉴스 분류: 공식 보도자료 중 양식장 업무와 관련된 것만 골라 4개 분류로 나눕니다.
// 키워드 기준이라 완벽하지 않습니다 — 틀린 분류는 관리자 화면에서 고칠 수 있습니다.

export const NEWS_CATEGORIES = ['disease', 'environment', 'support', 'policy'];

// 관련 없는 소식(인사·조달·행사 등)은 분류 이전에 거릅니다.
const EXCLUDE = /(인사|발령|임명|입찰|조달|채용|부고|시상식|축제|전시|공연|캠페인|기념식|\(동정\)|홍보대사|K-?팝)/;

// 기관 이름("해양수산부" 등)은 모든 소식에 들어 있어서 판단에서 뺍니다.
const ORG_NAMES = /(해양수산부|해양수산|국립수산과학원|수산과학원|수산과학기술|수과원)/g;

// 수산·양식 소식이라는 최소한의 근거 — 제목에 있어야 합니다.
const ANCHOR = /(양식|수산|어업|어류|어촌|어가|어장|어민|어획|해조|패류|해파리|적조|고수온|저수온|수온|넙치|광어|우럭|조피볼락|참돔|감성돔|숭어|연어|뱀장어|전복|새우|해삼|바지락|꼬막|미역|다시마)/;

// 우선순위: 질병·방역 > 해양환경 > 지원사업 > 양식·정책. 어획·원양 같은 일반 어업 소식은 제외합니다.
const DISEASE = /(질병|방역|전염병|바이러스|폐사|감염|병원체|어병|백신|진단|역학|검역|기생충|세균)/;
const ENVIRONMENT = /(수온|적조|해파리|유해\s?(생물|조류|해양생물)|빈산소|수질|냉수대|이상조류|해양환경|해양\s?오염|염분|용존산소)/;
const SUPPORT = /(지원\s?사업|보조금|융자|모집|재해\s?보험|재난\s?지원|지원금|보상|신청\s?접수|공모)/;
const POLICY = /(양식|수산업|수산물|종자|사료|스마트|어촌|자원\s?관리|수산식품|수산\s?정책|수산\s?기술|산업화|육성|기술\s?(개발|보급))/;

const SPECIES = [
  ['넙치', /넙치|광어/],
  ['조피볼락', /조피볼락|우럭/],
  ['참돔', /참돔/],
  ['감성돔', /감성돔/],
  ['농어', /농어(?!촌|업|민|가)/],
  ['숭어', /숭어/],
  ['방어', /방어/],
  ['연어', /연어/],
  ['뱀장어', /뱀장어/],
  ['전복', /전복/],
  ['새우', /새우/],
  ['해삼', /해삼/],
  ['김', /김\s?양식|참?김\s?(생산|종자)/],
  ['미역', /미역/],
  ['다시마', /다시마/],
  ['바지락', /바지락/],
  ['굴', /굴\s?양식|(^|[^가-힣])굴([^가-힣]|$)/],
  ['꼬막', /꼬막/],
];

const REGIONS = [
  '부산', '인천', '울산', '제주', '경기', '강원', '충남', '전남', '전북', '경남', '경북',
  '완도', '통영', '거제', '여수', '고흥', '신안', '진도', '목포',
  '서해안', '남해안', '동해안', '서해', '남해', '동해',
];

/**
 * @returns {{relevant: boolean, category: string|null, regions: string[], species: string[]}}
 */
export function classifyNews({ title, summary = '' }) {
  const none = { relevant: false, category: null, regions: [], species: [] };
  if (!title || EXCLUDE.test(title)) return none;
  const t = title.replace(ORG_NAMES, ' ');
  const sm = (summary ?? '').replace(ORG_NAMES, ' ');
  if (!ANCHOR.test(t)) return none;

  // 제목에서 먼저 찾고, 없을 때만 짧은 소개를 참고합니다.
  const pick = (text) =>
    DISEASE.test(text) ? 'disease'
      : ENVIRONMENT.test(text) ? 'environment'
      : SUPPORT.test(text) ? 'support'
      : POLICY.test(text) ? 'policy'
      : null;
  const category = pick(t) ?? pick(sm);
  if (!category) return none;

  const text = `${t} ${sm}`;
  return {
    relevant: true,
    category,
    // '서해'는 '서해안'이 함께 있으면 따로 넣지 않습니다.
    regions: REGIONS.filter((r) => text.includes(r)).filter((r) => !REGIONS.some((o) => o !== r && o.includes(r) && text.includes(o))),
    species: SPECIES.filter(([, re]) => re.test(text)).map(([name]) => name),
  };
}
