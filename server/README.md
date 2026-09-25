# AquaConnect API

Express + Postgres backend for the AquaConnect Flutter app: institute login,
farms, memos, generated reports, share links, and a NIFS 실시간 수온 proxy
(ported from `D:\202609\index.mjs`, avoiding the NIFS API's CORS restriction
for Flutter Web).

## Railway 배포

1. Railway 프로젝트를 만들고 이 `server/` 폴더를 GitHub 저장소로 연결하거나
   Railway CLI로 배포합니다 (`railway up`, 이 폴더 기준).
2. **Postgres 플러그인을 이 서비스에 연결**합니다 — Railway가 자동으로
   `DATABASE_URL` 환경변수를 주입합니다. 직접 설정할 필요 없음.
3. 서비스 환경변수에 다음을 추가합니다:
   - `JWT_SECRET` — 임의의 긴 랜덤 문자열 (`node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`)
   - `NIFS_API_KEY` — (선택) 발급받은 키. 비워두면 `D:\202609`와 동일한 기본 데모 키로 동작.
   - `SEED_DEMO_PASSWORD` — (선택) `npm run seed` 실행 시 데모 로그인 비밀번호. 기본값 `demo1234`.
4. 배포 후 Railway 콘솔의 "Run a command" (또는 `railway run`)로 한 번만 실행:
   ```
   npm run migrate
   npm run seed
   ```
   `npm run seed`는 `mock_seed.dart`와 동일한 데모 데이터(해강수산질병관리원 ·
   이동길 · 신일수산 1양식장 등)와 로그인 계정
   (`leedonggil@haegang.kr` / `demo1234`), 그리고 항상 열람 가능한 데모
   공유링크(`/r/demo`)를 만듭니다.
5. Flutter 쪽에서 이 서비스의 공개 URL을 가리키도록 빌드/실행합니다:
   ```
   flutter run -d chrome --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<railway-service>.up.railway.app
   ```

## 로컬 개발

```
cp .env.example .env   # DATABASE_URL을 로컬 Postgres로 지정
npm install
npm run migrate
npm run seed
npm run dev             # http://localhost:8080
```

Postgres가 로컬에 없다면 `npm run smoke-test`로 (pg-mem 기반 인메모리
에뮬레이터에 대해) 마이그레이션 SQL과 주요 쿼리 모양이 유효한지만 빠르게
확인할 수 있습니다 — 실제 Postgres를 대체하진 않으니, 실서비스 전에는
`npm run migrate && npm run seed`를 진짜 Postgres에 대해 꼭 한 번 실행해
보세요.

## API 개요

모든 `/api/*` 라우트(로그인 제외)는 `Authorization: Bearer <token>` 필요.
`/api/public/*`와 `/api/ocean/*`는 인증 불필요(공유링크로 받은 양식장주,
그리고 헬스체크용).

| Method | Path | 설명 |
|---|---|---|
| POST | `/api/auth/login` | 이메일/비밀번호 로그인 → JWT |
| GET | `/api/auth/me` | 현재 세션 복원 |
| GET | `/api/farms`, `/api/farms/:id` | 담당 양식장 목록/상세 |
| POST | `/api/farms` | 양식장 등록 (양식장명/위치/전화번호 필수) |
| PUT | `/api/farms/:id` | 양식장 정보 수정 |
| DELETE | `/api/farms/:id` | 양식장 삭제 |
| GET/POST | `/api/memos` | 메모 조회(`?farmId=`)/작성 |
| GET | `/api/disease-info` | 수산질병 정보 |
| GET | `/api/reports/:farmId` | 최신 리포트(없으면 즉시 생성) |
| GET | `/api/reports?farmIds=a,b` | 여러 양식장 최신 리포트 일괄 조회 |
| POST | `/api/reports/:farmId/generate` | 리포트 새로 생성 |
| POST/GET | `/api/share-links` | 공유링크 발급/목록 |
| GET | `/api/public/reports/:token` | **공개** — 공유링크로 리포트 조회 |
| PATCH | `/api/public/reports/:token/actions/:id` | **공개** — 조치사항 완료 토글 |
| POST | `/api/public/reports/:token/inquiries` | **공개** — 어가 문의 메모 접수 |
| GET | `/api/ocean/realtime?station=` | **공개** — NIFS 실시간 수온 프록시 |

## 알아둘 점

- "AI 정리 소견"은 `src/lib/reportGenerator.js`의 규칙 기반 로직이며 실제
  LLM 호출이 아닙니다 (Flutter 쪽 `report_generator.dart`와 동일한 로직을
  유지하려고 노력했지만, 백엔드가 붙은 뒤로는 이 파일이 정본입니다).
- NIFS `risaList` API는 실시간 수온만 제공하고 7일 이력/염도/용존산소/적조는
  주지 않습니다 — `oceanSnapshotForFarm()`은 그 사실을 숨기지 않고 그대로
  단일 값만 리포트 생성에 반영합니다.
