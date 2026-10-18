// 수산 뉴스 테스트.
//   npm test                                   — 분류·파서·시각 계산(데이터베이스 불필요)
//   NEWS_TEST_DATABASE_URL=postgres://… npm test  — 저장·중복·숨김·실패·권한까지(전용 DB 필요)
//
// DB 테스트는 news_* 표와 app_config 의 슬롯 값을 지우므로, 운영 DB 주소를 넣지 마세요.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import { after, before, beforeEach, describe, it } from 'node:test';

process.env.JWT_SECRET ??= 'test-secret';
const TEST_DB = process.env.NEWS_TEST_DATABASE_URL;
if (TEST_DB) process.env.DATABASE_URL = TEST_DB;

const fixture = (name) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8');
const { classifyNews } = await import('../src/lib/news/classify.js');
const sources = await import('../src/lib/news/sources.js');
const { currentSlot, kstClock } = await import('../src/lib/news/schedule.js');

describe('분류', () => {
  it('양식장 업무와 관련된 소식만 고르고 분류한다', () => {
    const cat = (title, summary) => classifyNews({ title, summary }).category;
    assert.equal(cat('넙치 양식장 바이러스성 질병 발생 주의'), 'disease');
    assert.equal(cat('고수온 재난 예·경보 전면 해제'), 'environment');
    assert.equal(cat('양식수산물 재해보험 개편 추진'), 'support'); // 보험·보상은 지원사업으로 본다
    assert.equal(cat('수산 재해 보험 신청 접수 안내'), 'support');
    assert.equal(cat('수과원, 벤자리 양식산업화 육성 기반 마련'), 'policy');
  });

  it('관련 없는 소식은 걸러낸다(인사·행사·동정·일반 해양·기관명만 있는 경우)', () => {
    for (const title of [
      '해양수산부 정기 인사 발령',
      '2026 수산물 축제 개최',
      '(동정) 차관, 수산업 현장 방문',
      '멸종된 독도강치 골격 복원 전시',
      '섬 주민의 일상을 지키는 뱃길 운항결손금 지원',
      '수과원, 4분기 고등어 어획량 전망',
    ]) {
      assert.equal(classifyNews({ title }).relevant, false, title);
    }
    // 기관명 "해양수산부"가 본문(소개)에만 있다고 수산 소식이 되지는 않는다.
    assert.equal(classifyNews({ title: '북극항로 시범운항', summary: '해양수산부는 …' }).relevant, false);
  });

  it('지역·어종은 확인되는 것만 뽑는다', () => {
    const r = classifyNews({ title: '넙치 양식장 바이러스 질병 전남 완도 서해안 확산' });
    assert.deepEqual(r.species, ['넙치']);
    assert.deepEqual(r.regions, ['전남', '완도', '서해안']);
    assert.deepEqual(classifyNews({ title: '농어촌 양식 지원 사업 모집' }).species, []); // 농어촌 ≠ 농어
    assert.deepEqual(classifyNews({ title: '양식 지원 사업 공고' }).regions, []);
  });
});

describe('파서·정리', () => {
  it('해양수산부 RSS: 정확한 원문 주소·게시 시각·짧은 소개', () => {
    const items = sources.parseMofRss(fixture('mof_rss.xml'));
    assert.equal(items.length, 10);
    assert.equal(items[0].sourceItemId, '69031');
    assert.equal(items[0].url, 'https://www.mof.go.kr/doc/ko/selectDoc.do?menuSeq=971&bbsSeq=10&docSeq=69031');
    assert.equal(items[0].publishedAt.toISOString(), '2026-10-16T04:43:25.000Z');
    assert.ok(items[0].summary.length > 0 && items[0].summary.length <= 160);
    assert.ok(!/[<>]/.test(items[0].summary), '태그가 남지 않아야 한다');
  });

  it('해양수산부 목록·수산과학원 목록', () => {
    const mof = sources.parseMofList(fixture('mof_list.html'));
    assert.equal(mof.length, 10);
    assert.equal(mof[0].publishedAt.toISOString(), '2026-10-15T15:00:00.000Z'); // 2026.10.16. 0시 KST
    const nifs = sources.parseNifsList(fixture('nifs_list.html'));
    assert.equal(nifs.length, 10);
    assert.equal(nifs[0].sourceItemId, '4921');
    assert.match(nifs[0].url, /^https:\/\/www\.nifs\.go\.kr\/news\/actionNewsView\.do\?MENU_ID=M0000307&NEWS_SEQ=4921&/);
  });

  it('게시일을 읽을 수 없으면 오늘 날짜를 넣지 않고 null', () => {
    assert.equal(sources.parseKstDate(''), null);
    assert.equal(sources.parseKstDate('작성일 미상'), null);
    assert.equal(sources.parseKstDate('2026.10.16.').toISOString(), '2026-10-15T15:00:00.000Z');
  });

  it('외부 글은 태그·스크립트를 지운 글자만 남긴다', () => {
    assert.equal(sources.plainText('<b>안전</b> <script>alert(1)</script><img src=x onerror=alert(1)>한 소식'), '안전 한 소식');
  });

  it('주소 정규화: 같은 글은 같은 키', () => {
    const a = sources.normalizeUrl('http://WWW.mof.go.kr/doc/ko/selectDoc.do?menuSeq=971&bbsSeq=10&docSeq=1&utm_source=x#top');
    const b = sources.normalizeUrl('https://www.mof.go.kr/doc/ko/selectDoc.do?docSeq=1&bbsSeq=10&menuSeq=971');
    assert.equal(a, b);
  });

  it('허용되지 않은 도메인은 가져오지 않는다', async () => {
    await assert.rejects(() => sources.fetchText('https://example.com/rss'), /허용되지 않은 출처/);
  });
});

describe('수집 시각', () => {
  it('한국 시간 08:00·14:00·20:00 중 가장 최근에 지난 슬롯', () => {
    assert.equal(currentSlot({ date: '2026-10-18', time: '08:00' }), '2026-10-18T08:00');
    assert.equal(currentSlot({ date: '2026-10-18', time: '13:59' }), '2026-10-18T08:00');
    assert.equal(currentSlot({ date: '2026-10-18', time: '14:00' }), '2026-10-18T14:00');
    assert.equal(currentSlot({ date: '2026-10-18', time: '23:30' }), '2026-10-18T20:00');
    assert.equal(currentSlot({ date: '2026-10-18', time: '07:59' }), '2026-10-17T20:00'); // 전날 마지막 슬롯
    assert.equal(currentSlot({ date: '2026-03-01', time: '03:00' }), '2026-02-28T20:00');
  });

  it('UTC 서버 시각을 한국 시간으로 바꾼다', () => {
    assert.deepEqual(kstClock(new Date('2026-10-18T23:00:00Z')), { date: '2026-10-19', time: '08:00' });
    assert.deepEqual(kstClock(new Date('2026-10-18T05:00:00Z')), { date: '2026-10-18', time: '14:00' });
  });
});

// ── 여기부터 실제 Postgres가 필요한 테스트 ──────────────────────────────
describe('저장·중복·숨김·실패·권한', { skip: TEST_DB ? false : 'NEWS_TEST_DATABASE_URL 이 없어 건너뜀' }, () => {
  let query;
  let pool;
  let collector;
  let signToken;
  let server;
  let base;
  let memberToken;

  const MOF_RSS = fixture('mof_rss.xml');
  const NIFS_LIST = fixture('nifs_list.html');
  const okResponse = (body) => new Response(body, { status: 200 });

  /** 출처별 가짜 응답. mofFail 이면 해양수산부만 서버 오류. */
  const fakeFetch = ({ mofFail = false } = {}) => async (url) => {
    if (String(url).includes('mof.go.kr')) return mofFail ? new Response('x', { status: 404 }) : okResponse(MOF_RSS);
    return okResponse(NIFS_LIST);
  };
  const count = async (where = 'true') => (await query(`select count(*)::int n from news_items where ${where}`)).rows[0].n;

  before(async () => {
    ({ query, pool } = await import('../src/db.js'));
    collector = await import('../src/lib/news/collector.js');
    ({ signToken } = await import('../src/auth.js'));
    const { default: express } = await import('express');
    await import('express-async-errors');
    const { newsRouter } = await import('../src/routes/news.js');
    const { adminRouter } = await import('../src/routes/admin.js');
    process.env.ADMIN_API_KEY = 'test-admin-key';
    const app = express();
    app.use(express.json());
    app.use('/api/news', newsRouter);
    app.use('/api/admin', adminRouter);
    server = http.createServer(app).listen(0);
    base = `http://127.0.0.1:${server.address().port}`;

    const { rows: org } = await query("insert into organizations (name) values ('뉴스테스트원') returning id");
    const { rows: member } = await query(
      "insert into members (org_id, name, email, password_hash, is_owner) values ($1, '테스터', $2, 'x', false) returning id",
      [org[0].id, `news-test-${Date.now()}@example.com`],
    );
    memberToken = signToken(member[0].id);
  });

  beforeEach(async () => {
    await query('delete from news_items');
    await query('delete from news_sources');
    await query("delete from app_config where key = 'news_last_slot'");
  });

  after(async () => {
    server?.close();
    await pool?.end();
  });

  const api = (path, { token = memberToken, adminKey, method = 'GET', body } = {}) =>
    fetch(`${base}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(adminKey ? { 'X-Admin-Key': adminKey } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });

  it('수집하면 관련 소식이 저장되고, 같은 작업을 반복해도 중복이 생기지 않는다', async () => {
    const first = await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    assert.ok(first.results.every((r) => r.ok));
    const n = await count();
    assert.ok(n > 0, '관련 소식이 저장돼야 한다');
    await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    assert.equal(await count(), n);
    const { rows } = await query('select count(distinct url_key)::int u, count(distinct (source, source_item_id))::int s from news_items');
    assert.equal(rows[0].u, n);
    assert.equal(rows[0].s, n);
  });

  it('다시 수집하면 제목 등 변경분은 갱신한다', async () => {
    const mof = sources.NEWS_SOURCES.find((s) => s.id === 'mof_press');
    const item = { sourceItemId: '1', title: '양식 지원 사업 공고', url: 'https://www.mof.go.kr/doc/ko/selectDoc.do?menuSeq=971&bbsSeq=10&docSeq=1', publishedAt: new Date(), summary: null };
    await collector.saveItems(mof.id, [item]);
    await collector.saveItems(mof.id, [{ ...item, title: '양식 지원 사업 공고(수정)' }]);
    assert.equal(await count(), 1);
    assert.equal((await query('select title from news_items')).rows[0].title, '양식 지원 사업 공고(수정)');
  });

  it('게시일을 모르는 소식은 게시일 없이 저장한다(오늘 날짜를 넣지 않는다)', async () => {
    await collector.saveItems('mof_press', [{ sourceItemId: '2', title: '양식 지원 사업 공고', url: 'https://www.mof.go.kr/doc/ko/selectDoc.do?menuSeq=971&bbsSeq=10&docSeq=2', publishedAt: null, summary: null }]);
    assert.equal((await query('select published_at from news_items')).rows[0].published_at, null);
  });

  it('30일보다 오래된 소식은 새로 들이지 않는다', async () => {
    const old = new Date(Date.now() - 40 * 24 * 3600 * 1000);
    await collector.saveItems('mof_press', [{ sourceItemId: '3', title: '양식 지원 사업 공고', url: 'https://www.mof.go.kr/doc/ko/selectDoc.do?menuSeq=971&bbsSeq=10&docSeq=3', publishedAt: old, summary: null }]);
    assert.equal(await count(), 0);
  });

  it('관리자가 숨긴 소식과 고친 분류·소개는 재수집해도 유지된다', async () => {
    await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    const { rows } = await query('select id from news_items order by id limit 2');
    const [hidden, edited] = rows.map((r) => r.id);
    await query('update news_items set is_published = false where id = $1', [hidden]);
    await query("update news_items set category = 'disease', summary = '관리자가 쓴 소개', edited_by_admin = true where id = $1", [edited]);
    await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    const after = await query('select id, is_published, category, summary from news_items where id = any($1)', [[hidden, edited]]);
    const by = Object.fromEntries(after.rows.map((r) => [r.id, r]));
    assert.equal(by[hidden].is_published, false);
    assert.equal(by[edited].category, 'disease');
    assert.equal(by[edited].summary, '관리자가 쓴 소개');
  });

  it('한 출처가 실패해도 다른 출처는 수집되고, 기존 뉴스와 마지막 성공 시각은 남는다', async () => {
    await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    const before = await count();
    const okBefore = (await query("select last_success_at from news_sources where source = 'mof_press'")).rows[0].last_success_at;

    const run = await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch({ mofFail: true }) });
    const by = Object.fromEntries(run.results.map((r) => [r.source, r]));
    assert.equal(by.mof_press.ok, false);
    assert.equal(by.nifs_press.ok, true, '다른 출처 수집은 막히지 않는다');
    assert.equal(await count(), before, '기존 뉴스는 그대로');

    const st = (await query("select * from news_sources where source = 'mof_press'")).rows[0];
    assert.match(st.last_error, /수집 실패/);
    assert.equal(st.last_success_at.getTime(), okBefore.getTime());
    assert.ok(st.last_attempt_at.getTime() >= okBefore.getTime());
  });

  it('동시에 두 번 실행해도 한 번만 돈다', async () => {
    const slow = async (url) => {
      await new Promise((r) => setTimeout(r, 300));
      return fakeFetch()(url);
    };
    const [a, b] = await Promise.all([
      collector.runNewsCollection({ backfill: false, fetchImpl: slow }),
      collector.runNewsCollection({ backfill: false, fetchImpl: slow }),
    ]);
    const skipped = [a, b].filter((r) => r.skipped);
    assert.equal(skipped.length, 1);
  });

  it('같은 수집 슬롯은 한 번만 선점된다', async () => {
    const slot = '2026-10-18T14:00';
    const claims = await Promise.all([collector.claimSlot(slot), collector.claimSlot(slot), collector.claimSlot(slot)]);
    assert.equal(claims.filter(Boolean).length, 1);
    assert.equal(await collector.claimSlot('2026-10-18T08:00'), false, '더 이른 슬롯은 다시 잡히지 않는다');
    assert.equal(await collector.claimSlot('2026-10-18T20:00'), true, '다음 슬롯은 잡힌다');
  });

  it('앱 API: 분류 필터·페이지·상세, 숨김은 보이지 않는다', async () => {
    await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    const all = await (await api('/api/news?page=1&pageSize=2')).json();
    assert.equal(all.items.length, 2);
    assert.equal(all.hasMore, (await count()) > 2);
    // 최신순(원문 게시일)
    const dates = all.items.map((i) => Date.parse(i.publishedAt));
    assert.ok(dates[0] >= dates[1]);

    const env = await (await api('/api/news?category=environment')).json();
    assert.ok(env.items.every((i) => i.category === 'environment'));
    assert.equal((await api('/api/news?category=bogus')).status, 400);

    const one = all.items[0];
    const detail = await (await api(`/api/news/${one.id}`)).json();
    assert.equal(detail.url, one.url);

    await query('update news_items set is_published = false where id = $1', [one.id]);
    assert.equal((await api(`/api/news/${one.id}`)).status, 404);
    const list = await (await api('/api/news?pageSize=30')).json();
    assert.ok(!list.items.some((i) => i.id === one.id));
    assert.equal((await api('/api/news/not-a-uuid')).status, 404);
    assert.equal((await api('/api/news', { token: null })).status, 401);
  });

  it('관리자 기능은 관리자 키가 있어야 하고, 일반 사용자는 접근할 수 없다', async () => {
    await collector.runNewsCollection({ backfill: false, fetchImpl: fakeFetch() });
    const { rows } = await query('select id from news_items limit 1');
    const id = rows[0].id;

    for (const [path, opts] of [
      ['/api/admin/news', {}],
      ['/api/admin/news/sources', {}],
      [`/api/admin/news/${id}`, { method: 'PATCH', body: { isPublished: false } }],
      ['/api/admin/news/collect', { method: 'POST', body: {} }],
    ]) {
      assert.equal((await api(path, { ...opts })).status, 401, `${path}: 일반 사용자 토큰`);
      assert.equal((await api(path, { ...opts, adminKey: 'wrong' })).status, 401, `${path}: 틀린 키`);
    }
    assert.equal(await count('is_published'), await count(), '거부된 요청으로 아무것도 바뀌지 않았다');

    // 올바른 키: 분류·소개 수정 → 숨김 → 목록(숨김 포함)·출처 상태 확인
    const edited = await api(`/api/admin/news/${id}`, { adminKey: 'test-admin-key', method: 'PATCH', body: { category: 'disease', summary: '수정한 소개' } });
    assert.equal(edited.status, 200);
    assert.equal((await edited.json()).editedByAdmin, true);
    assert.equal((await api(`/api/admin/news/${id}`, { adminKey: 'test-admin-key', method: 'PATCH', body: { category: 'nope' } })).status, 400);
    await api(`/api/admin/news/${id}`, { adminKey: 'test-admin-key', method: 'PATCH', body: { isPublished: false } });
    const hiddenList = await (await api('/api/admin/news?published=false', { adminKey: 'test-admin-key' })).json();
    assert.equal(hiddenList.items.length, 1);
    const statuses = await (await api('/api/admin/news/sources', { adminKey: 'test-admin-key' })).json();
    assert.deepEqual(statuses.map((s) => s.source).sort(), ['mof_press', 'nifs_press']);
  });
});
