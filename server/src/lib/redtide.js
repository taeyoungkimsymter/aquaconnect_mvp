// NIFS 적조 정보 (`redtideList` / `redtideDetail` OpenAPI). Reports come out
// daily while a red tide is under way and not at all otherwise, so callers
// get the newest report (with its full 속보 text) plus a short list of the
// recent ones, and decide from its date whether it's still current.
//
// The live feed's field names differ from NIFS's PDF spec: list items carry
// cod_news / day_report, occurrences nam_biology / txt_seas / min_density /
// max_density / min_watertemp / max_watertemp, and the detail call takes
// `cod_news=` (not `srcode=`) and returns txt_progress / txt_breaking /
// txt_afterview / txt_request / txt_reference.

const API_URL = 'https://www.nifs.go.kr/api/OpenAPI_json';
const DEFAULT_API_KEY = 'qPwOeIrU-2610-IYTMOQ-2232';

const CACHE_TTL_MS = 30 * 60 * 1000;
const MIN_REFRESH_INTERVAL_MS = 60 * 1000;
const RECENT_COUNT = 10;

let cache = null; // { fetchedAt: number, data }
let inFlight = null;

async function callApi(params) {
  const query = new URLSearchParams({ key: process.env.NIFS_REDTIDE_API_KEY || DEFAULT_API_KEY, ...params });
  let lastError;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetch(`${API_URL}?${query}`, { headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error(`NIFS 적조 API HTTP 오류 ${response.status}`);
      const payload = await response.json();
      const header = payload?.header ?? {};
      if (header.resultCode !== '00') {
        throw new Error(`NIFS 적조 API 오류 [${header.resultCode}] ${header.resultMsg ?? ''}`);
      }
      const items = payload?.body?.item;
      return Array.isArray(items) ? items : items ? [items] : [];
    } catch (err) {
      lastError = err;
      if (attempt < 2) await new Promise((r) => setTimeout(r, 1500));
    }
  }
  throw lastError;
}

const yyyymmdd = (d) =>
  `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;

/** '20260916' → '2026-09-16' (null if malformed). */
const isoDate = (s) => (/^\d{8}$/.test(s ?? '') ? `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}` : null);

/** Blank → null; a 0 water temperature means "not measured". */
function num(value, { zeroIsMissing = false } = {}) {
  if (value === null || value === undefined || String(value).trim() === '') return null;
  const n = Number(String(value).replace(/,/g, ''));
  if (!Number.isFinite(n)) return null;
  return zeroIsMissing && n === 0 ? null : n;
}

function occurrences(item) {
  const list = Array.isArray(item.item2) ? item.item2 : item.item2 ? [item.item2] : [];
  return list.map((o) => ({
    organism: (o.nam_biology ?? '').trim(),
    area: (o.txt_seas ?? '').trim(),
    minDensity: num(o.min_density),
    maxDensity: num(o.max_density),
    minTemp: num(o.min_watertemp, { zeroIsMissing: true }),
    maxTemp: num(o.max_watertemp, { zeroIsMissing: true }),
  }));
}

/**
 * NIFS 속보 text often runs bullets together ("…출현- 경남 통영…") — put
 * each "- ", "■" and "※" item on its own line.
 */
export function tidyReportText(text) {
  if (!text) return '';
  return String(text)
    .replace(/\r\n?/g, '\n')
    .replace(/([^\s])- (?=\S)/g, '$1\n- ')
    .replace(/\s*■\s*/g, '\n■ ')
    .replace(/\s*※\s*/g, '\n※ ')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .join('\n');
}

async function load() {
  const today = new Date();
  const yearAgo = new Date(today.getTime() - 365 * 24 * 60 * 60 * 1000);
  const items = await callApi({ id: 'redtideList', sdate: yyyymmdd(yearAgo), edate: yyyymmdd(today) });
  const reports = items
    .map((item) => ({
      code: String(item.cod_news ?? ''),
      reportDate: isoDate(item.day_report),
      occurrences: occurrences(item),
    }))
    .filter((r) => r.code && r.reportDate)
    .sort((a, b) => b.reportDate.localeCompare(a.reportDate) || b.code.localeCompare(a.code));

  let latest = null;
  if (reports.length > 0) {
    const head = reports[0];
    latest = { ...head, progress: '', breaking: '', outlook: '', request: '', reference: '' };
    try {
      const [detail] = await callApi({ id: 'redtideDetail', cod_news: head.code });
      if (detail) {
        latest = {
          ...head,
          occurrences: occurrences(detail).length > 0 ? occurrences(detail) : head.occurrences,
          progress: tidyReportText(detail.txt_progress),
          breaking: tidyReportText(detail.txt_breaking),
          outlook: tidyReportText(detail.txt_afterview),
          request: tidyReportText(detail.txt_request),
          reference: tidyReportText(detail.txt_reference),
        };
      }
    } catch {
      // The list entry alone is still worth showing.
    }
  }
  return { latest, recent: reports.slice(0, RECENT_COUNT), fetchedAt: new Date().toISOString() };
}

/** The newest 적조 속보 (with its detail text) and the most recent reports. */
export async function fetchRedTide({ refresh = false } = {}) {
  const age = cache ? Date.now() - cache.fetchedAt : Infinity;
  const stale = age > CACHE_TTL_MS || (refresh && age > MIN_REFRESH_INTERVAL_MS);
  if (cache && !stale) return cache.data;
  if (inFlight) return inFlight;
  inFlight = load()
    .then((data) => {
      cache = { fetchedAt: Date.now(), data };
      return data;
    })
    // NIFS down: keep serving the last good answer rather than nothing.
    .catch((err) => {
      if (cache) return cache.data;
      throw err;
    })
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}
