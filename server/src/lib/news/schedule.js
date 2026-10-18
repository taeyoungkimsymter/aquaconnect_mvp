// 수산 뉴스 수집 시각 계산(데이터베이스와 무관). 서버는 UTC로 돌지만 시각은 모두 한국 시간(KST) 기준입니다.

export const COLLECTION_SLOTS = ['08:00', '14:00', '20:00'];
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** 한국 시간의 날짜("2026-10-18")와 시각("14:05"). */
export function kstClock(now = new Date()) {
  const k = new Date(now.getTime() + KST_OFFSET_MS).toISOString();
  return { date: k.slice(0, 10), time: k.slice(11, 16) };
}

/** 지금 기준 "가장 최근에 지난 수집 슬롯" — 예: "2026-10-18T14:00". 오전 8시 전이면 어제 20:00. */
export function currentSlot(now = kstClock()) {
  const passed = [...COLLECTION_SLOTS].reverse().find((s) => s <= now.time);
  if (passed) return `${now.date}T${passed}`;
  const yesterday = new Date(`${now.date}T00:00:00Z`);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  return `${yesterday.toISOString().slice(0, 10)}T${COLLECTION_SLOTS[COLLECTION_SLOTS.length - 1]}`;
}
