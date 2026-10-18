// 수산 뉴스를 지금 한 번 수집합니다 — 외부 스케줄러(cron 등)에서 쓰거나 수동 점검용.
//   npm run news:collect            이 출처를 처음 수집하면 최근 30일치까지, 아니면 최신분만
//   npm run news:collect -- --backfill   최근 30일치를 다시 보충
import 'dotenv/config';

import { pool } from '../src/db.js';
import { runNewsCollection } from '../src/lib/news/collector.js';

const backfill = process.argv.includes('--backfill') ? true : undefined;
const outcome = await runNewsCollection({ backfill });
console.log(JSON.stringify(outcome, null, 2));
await pool.end();
process.exit(outcome.results.some((r) => !r.ok) ? 1 : 0);
