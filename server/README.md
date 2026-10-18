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
   - `ADMIN_API_KEY` — (선택) 관리자 대시보드(`admin/`)가 `/api/admin/*`를 부를 때 쓰는 공유 비밀값.
     비워두면 관리자 API 전체가 꺼집니다(503). `admin/`의 같은 이름 환경변수와 값을 맞추세요.
   - `NIFS_API_KEY` — (선택) 발급받은 키. 비워두면 `D:\202609`와 동일한 기본 데모 키로 동작.
   - `NIFS_FEMO_API_KEY` — (선택) 어장환경관측(`femoSeaList`) 키. 비워두면 코드에 저장된 기본 키로 동작.
   - `SEED_DEMO_PASSWORD` — (선택) `npm run seed`가 만드는 소유자 계정 비밀번호. 기본값 `demo1234`.
   - `SEED_ORG_NAME` / `SEED_OWNER_NAME` / `SEED_OWNER_EMAIL` / `SEED_OWNER_PHONE` — (선택) 시드할 관리원명·소유자
     이름·로그인 이메일·전화번호. 기본값 해강수산질병관리원 / 이동길 / `leedonggil@haegang.kr` / 없음.
     전화번호는 공유 리포트의 "담당 관리사에게 연락하기" 버튼이 거는 번호입니다.
   - `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` — (선택) 휴대폰 알림(Web Push) 서명 키.
     비워두면 서버가 처음 필요할 때 키 쌍을 만들어 DB(`app_config`)에 저장하고 계속 그 키를 씁니다.
     키를 바꾸면 기존 기기 구독이 모두 무효가 되니(앱을 열면 자동 재구독) 한 번 정한 뒤엔 바꾸지 마세요.
4. 마이그레이션은 `npm start`(= `scripts/start.js`)가 서버 기동 전에
   자동으로 적용합니다 (`_migrations` 테이블로 이미 적용된 파일은 건너뜀).
   최초 1회만 Railway 콘솔의 "Run a command" (또는 `railway run`)로 시드를
   넣습니다:
   ```
   npm run seed
   ```
   시드는 관리원(organization)과 소유자 로그인 계정만 만듭니다 — 양식장·메모·
   질병정보·공유링크 같은 데모 데이터는 넣지 않습니다. 이미 같은 이메일 계정이
   있으면 아무것도 하지 않으므로 다시 실행해도 안전합니다.

   예전 시드(데모 양식장 신일수산 1양식장 등, `/r/demo` 링크)가 이미 들어간
   DB라면 한 번 정리하세요 — 정확히 그 데모 행만 지웁니다:
   ```
   npm run clear-demo            # 지울 행 수만 출력 (dry run)
   npm run clear-demo -- --yes   # 실제 삭제
   ```
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
| PUT | `/api/farms/:id` | 양식장 정보 수정 (`assignedMemberId`로 담당자 변경, 생략하면 유지) |
| DELETE | `/api/farms/:id` | 양식장 삭제 |
| GET/POST | `/api/memos` | 메모 조회(`?farmId=`)/작성 |
| PATCH | `/api/memos/:id` | 메모 수정 `{content}` — 기관 메모만, 작성자 또는 소유자·원장. 수정 전 내용은 `memo_edits`에 남고, 이력 내용은 소유자·원장에게만 응답 (다른 구성원은 `editCount`만) |
| DELETE | `/api/memos/:id` | 메모 삭제 (작성자 또는 소유자·원장) |
| POST | `/api/memos/read` | 읽음 표시 `{ids:[...]}` — 응답의 `readCount`는 작성자를 뺀 읽은 사람 수, `readByMe`는 내가 읽었는지 |
| GET/POST | `/api/memos/:id/comments` | 댓글 목록/작성 `{content}` (1000자 이내). 메모 작성자와 이미 댓글을 단 사람에게 `comment` 알림 |
| DELETE | `/api/memos/:id/comments/:commentId` | 댓글 삭제 (댓글 작성자 또는 소유자·원장) |
| GET | `/api/disease-info` | 수산질병 정보 |
| GET | `/api/reports/:farmId` | 최신 리포트(없으면 즉시 생성) |
| GET | `/api/reports?farmIds=a,b` | 여러 양식장 최신 리포트 일괄 조회 |
| POST | `/api/reports/:farmId/generate` | 리포트 새로 생성 |
| POST/GET | `/api/share-links` | 공유링크 발급/목록 |
| GET | `/api/public/reports/:token` | **공개** — 공유링크로 리포트 조회 |
| GET | `/api/ocean/realtime?station=` | **공개** — NIFS 실시간 수온 프록시 |
| GET | `/api/ocean/quality?lat=&lon=[&refresh=1]` | **공개** — 가장 가까운(50km 이내) NIFS 어장환경 조사 정점의 최신 수질(염분·DO·pH·영양염 등). 없으면 `null` |

## 알아둘 점

- "AI 정리 소견"은 `src/lib/reportGenerator.js`의 규칙 기반 로직이며 실제
  LLM 호출이 아닙니다 (Flutter 쪽 `report_generator.dart`와 동일한 로직을
  유지하려고 노력했지만, 백엔드가 붙은 뒤로는 이 파일이 정본입니다).
- NIFS `risaList` API는 실시간 수온만 제공하고 7일 이력/염도/용존산소/적조는
  주지 않습니다 — `oceanSnapshotForFarm()`은 그 사실을 숨기지 않고 그대로
  단일 값만 리포트 생성에 반영합니다.
- 염분·용존산소·pH 등은 NIFS 어장환경관측(`femoSeaList`, `src/lib/femo.js`,
  `D:\py\croll\main.py` 이식)에서 가져옵니다. 실시간 센서가 아니라 연 4회
  내외의 정기 현장조사라 관측일이 수개월 전일 수 있고, 서버는 작년+올해
  자료를 메모리에 6시간 캐시합니다 (`refresh=1`은 1분에 한 번까지만 재조회).

## 알림 (Web Push)

- 알림이 생기는 경우: 양식장 위험도가 올라갈 때(양호→주의/위험, 주의→위험 — 조직 전체), 다른 구성원이
  메모를 남길 때(작성자 제외). 각 구성원이 마이페이지 > 알림 설정에서 종류별로 끌 수 있고, 끈 종류는 알림함에도 쌓이지 않습니다.
- `GET /api/notifications` 알림함, `POST /api/notifications/:id/read`, `POST /api/notifications/read-all`,
  `GET|PUT /api/notifications/settings`, `GET|PUT /api/notifications/digest` (업무 알림 설정 `{dailyEnabled, dailyTime:"HH:MM", weeklyEnabled}`),
  `GET /api/notifications/push/public-key`,
  `POST|DELETE /api/notifications/push/subscriptions`, `POST /api/notifications/test`.
- 기기 쪽은 `web/push_sw.js` 서비스워커가 받습니다. 안드로이드 Chrome·PC 브라우저는 바로 되고,
  아이폰(iOS 16.4+)은 Safari에서 "홈 화면에 추가"로 설치한 앱에서만 알림을 켤 수 있습니다.

## 어가 문의 (공유 리포트)

- `POST /api/public/reports/:token/inquiries` (**공개**, 로그인 불필요) — body `{ "message": "..." }`, 500자 이내,
  링크당 1시간 10건까지(초과 시 429). 만료·회수된 링크는 404.
- 접수되면 `inquiries`에 저장되고, 메모 목록에 `어가 · <양식장명>` 작성자·`문의` 태그로 남으며, 관리원 전원에게
  `inquiry` 알림(휴대폰 푸시 포함)이 갑니다. 문의 알림은 알림 설정과 관계없이 항상 갑니다.
- 공유 리포트의 "전화 걸기"는 양식장 담당 구성원의 `members.phone`으로 겁니다 (`SEED_OWNER_PHONE` 참고).

## 회원가입 (수산질병관리원)

`aquaconnect_web`의 가입 위저드를 옮기되 **사업자등록증 첨부·관리자 승인은 뺐습니다** — 가입하면 즉시 사용 가능하고
응답에 로그인 토큰이 바로 들어 있습니다. 어가는 계정 없이 공유 링크로만 보므로 가입 유형은 관리원 하나뿐입니다.

- `GET /api/auth/terms` → `{ termsVersion }`
- `GET /api/auth/check-email?email=` → `{ available }` (대소문자 무시)
- `POST /api/auth/signup` → 201 `{ token, member, organization }` (로그인 응답과 같은 모양)
  ```json
  {
    "account": { "name": "대표자명", "email": "a@b.kr", "password": "8자+2종", "phone": "01012345678" },
    "organization": { "name": "○○수산질병관리원", "address": "주소", "businessRegNo": "선택, 10자리" },
    "terms": { "termsVersion": "2026-10-01", "termsAgreed": true, "privacyAgreed": true, "marketingAgreed": false }
  }
  ```
  관리원(organizations)과 소유자 계정(members, role=owner)을 한 트랜잭션으로 만들고 약관 동의 시각을 기록합니다.
  이메일·사업자등록번호 중복은 409, 같은 IP에서 1시간 10건 초과는 429.
  입력 규칙은 `src/lib/validators.js` ↔ `lib/core/utils/validators.dart`가 같은 규칙을 씁니다(한쪽을 바꾸면 둘 다).

## 구성원 · 관리원 정보 · 변경 이력

- `GET /api/members` — 관리원 구성원 목록(활성·비활성). `PATCH /api/members/:id/role` `{role: director|staff|employee}`,
  `POST /api/members/:id/deactivate|reactivate`, `POST /api/members/:id/transfer-ownership`.
  소유자·원장만 변경 가능, 본인·소유자는 대상이 될 수 없고, 양도는 소유자만. 비활성 구성원은 로그인이 막히고
  이미 받은 토큰도 즉시 401이 됩니다(`requireAuth`가 매 요청 상태 확인).
- `GET|PUT /api/organization` — 관리원명·주소·대표 연락처 (수정은 소유자·원장).
- `GET /api/organization/audit-logs?type=member|farm|organization&before=<ISO>&limit=` — 변경 이력, 최신순.
  구성원(역할·비활성·재활성·소유자 양도), 양식장(등록·수정·삭제, 바뀐 항목만), 관리원(가입·정보 수정)이 기록되고,
  위험도·수온처럼 시스템이 자동으로 갱신하는 값은 기록하지 않습니다.
  **3개월이 지난 이력은 서버가 기동 시와 6시간마다 자동 삭제**합니다(`src/lib/audit.js`의 `AUDIT_RETENTION`).
- `POST /api/share-links/:id/revoke` — 공유 링크 회수(어가 링크 즉시 404). 목록 응답에 `farmName` 포함.

## 구성원 초대

- 소유자·원장: `POST /api/invitations` `{role: director|staff|employee, expireDays: 7|30, note?}` → 1회용 코드(10자) ·
  `GET /api/invitations`(대기 중 + 만료됨) · `POST /api/invitations/:id/extend`(지금부터 7일로 연장) ·
  `POST /api/invitations/:id/cancel`.
- 공개: `GET /api/public/invitations/:code` → 관리원명·역할·초대한 사람·만료 (없으면 404, 사용·취소·만료면 410과 사유) ·
  `POST /api/public/invitations/:code/accept` `{account:{name,email,password,phone}, terms:{...}}` → 그 관리원에
  초대 역할로 계정을 만들고 로그인 토큰 반환. 초대 소진은 같은 트랜잭션의 조건부 update라 동시에 눌러도 1명만 성공합니다.
  가입 횟수 제한(IP당 1시간 10건)은 회원가입과 공유합니다.
- 앱 링크는 `<웹 주소>/#/invite/<code>`. 초대 생성·취소·합류는 변경 이력에 남습니다.

### 댓글 첨부 · 사람 호출

- `POST /api/memos/:id/comments` `{content, mentionedMemberIds?, attachments?: [{kind: photo|file, fileName, contentType, dataBase64}]}` — 글 없이 첨부만 보내도 됩니다.
  사진은 jpeg/png/webp 5MB 이하 최대 5장, 파일은 pdf·doc(x)·xls(x)·ppt(x)·hwp(x)·txt·csv·zip 10MB 이하 최대 3개(합계 24MB). 그 밖의 형식(html·svg·exe 등)은 거부합니다.
- 첨부 받기: `GET /api/memos/:id/comments/:commentId/attachments/:attachmentId` (같은 조직만; 파일은 항상 내려받기로 응답).
- 호출한 구성원(같은 조직의 활동 중인 사람, 본인 제외, 최대 10명)은 따로 "호출했어요" 알림을 받고, 나머지 스레드 참여자는 기존 "새 댓글" 알림을 받습니다.

### 미완료된 업무 / 오늘 해야할 일

서버가 1분마다 확인해서 (`src/lib/digest.js`, 한국 시간 기준) 알림함 + 휴대폰 푸시로 보냅니다.
- 업무 = '할일' 태그가 붙었거나 `할일:`이 들어간 메모. 메모는 누구나 완료 처리할 수 있고(`PUT /api/memos/:id/completion` `{completed}`, 할일이 아니어도 가능) `memos.completed_at`에 기록됩니다.
- 미완료된 업무: 각자 정한 시각(기본 08:30)에 조직의 완료되지 않은 할일 메모 수와 앞쪽 몇 건.
- 오늘 해야할 일: 같은 시각에 내가 담당하는 양식장의 완료되지 않은 할일 메모.
- 설정 컬럼 이름은 예전 그대로입니다: `daily_*` = 미완료된 업무, `weekly_enabled`/`last_weekly_on` = 오늘 해야할 일. 발송 시각(`daily_time`)은 둘이 공유합니다.
- 보낸 날짜를 `digest_settings.last_daily_on/last_weekly_on`에 기록하므로 재시작해도 같은 요약을 두 번 보내지 않습니다.
  이미 지난 시각으로 바꾸면 그날은 건너뛰고 다음 날부터 보냅니다.
