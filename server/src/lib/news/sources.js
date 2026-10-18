import * as cheerio from 'cheerio';

// 수산 뉴스 출처. 실제로 확인한 공식 제공 방식만 연결합니다.
//
//  · mof_press  해양수산부 보도자료 — 공식 RSS(https://www.mof.go.kr/doc/ko/rssFeed.do?bbsSeq=10, 최근 10건).
//               RSS가 닿지 않는 최근 30일은 공개 목록 페이지(robots.txt 허용)로 최초 1회 보충합니다.
//  · nifs_press 국립수산과학원 보도자료 — API·RSS 없음, 공개 목록 페이지(/news/actionNewsList.do)를 읽습니다.
//               robots.txt가 없고, 하루 3회·최소 요청으로 제한합니다.
//
// 가져온 내용은 전부 글자로만 다룹니다(HTML 태그 제거) — 앱은 이 글자만 표시합니다.

const USER_AGENT = process.env.NEWS_USER_AGENT || 'AquaConnectNewsBot/1.0 (+https://aquaconnect-mvp.vercel.app)';
const ALLOWED_HOSTS = ['www.mof.go.kr', 'www.nifs.go.kr'];
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_RETRIES = 2;
const MAX_BODY_BYTES = 5 * 1024 * 1024;
const REQUEST_GAP_MS = 1_000; // 같은 출처에 연달아 요청할 때의 간격
const BACKFILL_DAYS = 30;
const MAX_TITLE = 300;
const MAX_SUMMARY = 160;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** 제한 시간·제한된 재시도가 있는 GET. 허용된 공식 도메인만 받습니다. */
export async function fetchText(url, { fetchImpl = fetch } = {}) {
  const host = new URL(url).hostname;
  if (!ALLOWED_HOSTS.includes(host)) throw new Error(`허용되지 않은 출처: ${host}`);
  let lastError;
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    if (attempt > 0) await sleep(1000 * attempt);
    try {
      const res = await fetchImpl(url, {
        headers: { 'User-Agent': USER_AGENT, Accept: 'text/html,application/xml,application/rss+xml' },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
      if (res.status === 429 || res.status >= 500) throw new Error(`HTTP ${res.status}`);
      if (!res.ok) throw Object.assign(new Error(`HTTP ${res.status}`), { fatal: true });
      if (res.url && !ALLOWED_HOSTS.includes(new URL(res.url).hostname)) {
        throw Object.assign(new Error('허용되지 않은 주소로 이동했습니다.'), { fatal: true });
      }
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length > MAX_BODY_BYTES) throw Object.assign(new Error('응답이 너무 큽니다.'), { fatal: true });
      return buf.toString('utf8');
    } catch (err) {
      lastError = err;
      if (err.fatal) break;
    }
  }
  throw new Error(`${url} 수집 실패: ${lastError?.message ?? lastError}`);
}

// ── 공통 정리 ─────────────────────────────────────────────────────────

/** 태그·제어문자를 지우고 공백을 정리한 글자만 남깁니다. */
export function plainText(html) {
  const $ = cheerio.load(`<div>${html ?? ''}</div>`);
  $('script, style').remove();
  const text = $('div').text();
  // eslint-disable-next-line no-control-regex
  return text.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
}

const clip = (text, max) => (text.length > max ? `${text.slice(0, max - 1)}…` : text);

/** "2026.10.16." / "2026-10-16" → 그날 0시(한국 시간). 읽을 수 없으면 null — 오늘 날짜로 채우지 않습니다. */
export function parseKstDate(text) {
  const m = /(\d{4})[.\-/]\s*(\d{1,2})[.\-/]\s*(\d{1,2})/.exec(text ?? '');
  if (!m) return null;
  const [, y, mo, d] = m;
  const date = new Date(`${y}-${mo.padStart(2, '0')}-${d.padStart(2, '0')}T00:00:00+09:00`);
  return Number.isNaN(date.getTime()) ? null : date;
}

const mofUrl = (docSeq) => `https://www.mof.go.kr/doc/ko/selectDoc.do?menuSeq=971&bbsSeq=10&docSeq=${docSeq}`;
const nifsUrl = (seq) =>
  `https://www.nifs.go.kr/news/actionNewsView.do?MENU_ID=M0000307&NEWS_SEQ=${seq}&NEWS_D_DATE_BEGIN=2010-01-01&NEWS_D_DATE_END=2099-12-31`;

/** 중복 판정용 키: https로 통일, 호스트 소문자, 쿼리 정렬, 추적 파라미터·해시 제거. */
export function normalizeUrl(raw) {
  const u = new URL(raw);
  u.protocol = 'https:';
  u.hostname = u.hostname.toLowerCase();
  u.hash = '';
  for (const key of [...u.searchParams.keys()]) if (/^utm_/i.test(key)) u.searchParams.delete(key);
  u.searchParams.sort();
  return u.toString().replace(/\/$/, '');
}

// ── 해양수산부 ────────────────────────────────────────────────────────

/** RSS 본문(content:encoded)에서 첫 한두 줄만 짧은 소개로 씁니다 — 전문을 옮기지 않습니다. */
function introFromBody(contentHtml, title) {
  if (!contentHtml) return null;
  const $ = cheerio.load(contentHtml);
  const lines = $('p, li')
    .map((_, el) => plainText($(el).text()))
    .get()
    .map((t) => t.replace(/^[-○ㆍ·•\s]+/, ''))
    .filter((t) => t.length >= 8 && t !== title);
  const intro = lines.slice(0, 2).join(' / ');
  return intro ? clip(intro, MAX_SUMMARY) : null;
}

export function parseMofRss(xml) {
  const $ = cheerio.load(xml, { xmlMode: true });
  return $('item')
    .map((_, el) => {
      const item = $(el);
      const link = item.find('link').first().text().trim();
      const docSeq = new URL(link, 'https://www.mof.go.kr').searchParams.get('docSeq');
      if (!docSeq || !/^\d+$/.test(docSeq)) return null;
      const title = clip(plainText(item.find('title').first().text()), MAX_TITLE);
      const published = new Date(item.find('pubDate').first().text().trim());
      return {
        sourceItemId: docSeq,
        title,
        url: mofUrl(docSeq),
        publishedAt: Number.isNaN(published.getTime()) ? null : published,
        summary: introFromBody(item.find('content\\:encoded').first().text(), title),
      };
    })
    .get()
    .filter(Boolean);
}

export function parseMofList(html) {
  const $ = cheerio.load(html);
  return $('table.bod-table-list tbody tr')
    .map((_, el) => {
      const row = $(el);
      const link = row.find('td.tit a').first();
      const id = /fn_selectDoc\('(\d+)'\)/.exec(link.attr('onclick') ?? '')?.[1];
      const title = clip(plainText((link.attr('title') ?? link.text()).replace(/^\[게시글 바로가기\]\s*/, '')), MAX_TITLE);
      if (!id || !title) return null;
      return { sourceItemId: id, title, url: mofUrl(id), publishedAt: parseKstDate(row.find('td.t-date').text()), summary: null };
    })
    .get()
    .filter(Boolean);
}

// ── 국립수산과학원 ────────────────────────────────────────────────────

export function parseNifsList(html) {
  const $ = cheerio.load(html);
  return $('table tbody tr')
    .map((_, el) => {
      const row = $(el);
      const link = row.find('td.subject a').first();
      const seq = /NEWS_SEQ=(\d+)/.exec(link.attr('href') ?? '')?.[1];
      const title = clip(plainText(link.text()), MAX_TITLE);
      if (!seq || !title) return null;
      return { sourceItemId: seq, title, url: nifsUrl(seq), publishedAt: parseKstDate(row.find('td.date').text()), summary: null };
    })
    .get()
    .filter(Boolean);
}

// ── 출처 정의 ─────────────────────────────────────────────────────────

/** 목록을 1쪽부터 읽다가, 한 쪽 전부가 기준일보다 오래되면(또는 maxPages에서) 멈춥니다. */
async function pagedList({ pageUrl, parse, maxPages, fetchImpl }) {
  const cutoff = Date.now() - BACKFILL_DAYS * 24 * 60 * 60 * 1000;
  const all = [];
  for (let page = 1; page <= maxPages; page++) {
    if (page > 1) await sleep(REQUEST_GAP_MS);
    const items = parse(await fetchText(pageUrl(page), { fetchImpl }));
    if (items.length === 0) break;
    all.push(...items);
    const dated = items.filter((i) => i.publishedAt);
    if (dated.length && dated.every((i) => i.publishedAt.getTime() < cutoff)) break;
  }
  return all;
}

export const NEWS_SOURCES = [
  {
    id: 'mof_press',
    name: '해양수산부 보도자료',
    async fetchItems({ backfill = false, fetchImpl } = {}) {
      const items = parseMofRss(await fetchText('https://www.mof.go.kr/doc/ko/rssFeed.do?bbsSeq=10', { fetchImpl }));
      if (!backfill) return items;
      await sleep(REQUEST_GAP_MS);
      const listed = await pagedList({
        pageUrl: (p) => `https://www.mof.go.kr/doc/ko/selectDocList.do?paginationInfo.currentPageNo=${p}&menuSeq=971&bbsSeq=10`,
        parse: parseMofList,
        maxPages: 8,
        fetchImpl,
      });
      // RSS 쪽(정확한 게시 시각·소개 포함)을 우선합니다.
      const seen = new Set(items.map((i) => i.sourceItemId));
      return [...items, ...listed.filter((i) => !seen.has(i.sourceItemId))];
    },
  },
  {
    id: 'nifs_press',
    name: '국립수산과학원 보도자료',
    async fetchItems({ backfill = false, fetchImpl } = {}) {
      return pagedList({
        pageUrl: (p) => `https://www.nifs.go.kr/news/actionNewsList.do?selectPage=${p}`,
        parse: parseNifsList,
        maxPages: backfill ? 5 : 1,
        fetchImpl,
      });
    },
  },
];

export const BACKFILL_WINDOW_MS = BACKFILL_DAYS * 24 * 60 * 60 * 1000;
