# AquaConnect 관리자 대시보드

Next.js 앱. 기능은 **커뮤니티 관리**(전체 관리원의 현장 메모·댓글 검색/삭제, 글 로그 CSV 내보내기)와
**계정 관리**(정보 수정, 비밀번호 재설정, 활성화·비활성화) 두 가지뿐이다.

글 로그 CSV(`GET /api/admin/export/posts.csv?from&to&orgId&authorId&q`)는 메모·댓글을 작성 시각 순으로
한 줄씩 담는다(UTF-8 BOM, 엑셀용). 수식으로 실행될 수 있는 셀(`=`·`+`·`-`·`@`로 시작)은 앞에 `'`를 붙인다.
한 번에 최대 50,000줄.

브라우저 → `app/api/admin/[...path]` 프록시 → 서버 `/api/admin/*` 순으로 호출되며,
프록시가 `X-Admin-Key` 를 붙인다. 키는 브라우저 번들에 들어가지 않는다.

## 환경변수

| 이름 | 설명 |
| --- | --- |
| `API_BASE_URL` | AquaConnect 서버 주소. 기본값 `https://aquaconnectmvp-production.up.railway.app` |
| `ADMIN_API_KEY` | 서버(Railway)의 `ADMIN_API_KEY` 와 같은 값. 서버에 없으면 관리자 API 전체가 503 |
| `ADMIN_ID` / `ADMIN_PW` | 대시보드 로그인 계정. 기본값 `root` / `1234` |
| `ADMIN_SESSION_SECRET` | 세션 쿠키 서명 키. 운영에서는 반드시 설정 |

## 실행

```bash
npm install
npm run dev     # http://localhost:3000
```

Vercel 에 올릴 때는 이 저장소로 **별도 프로젝트**를 만들고 Root Directory 를 `admin` 으로 지정한다
(저장소 루트의 `vercel.json` 은 Flutter 웹 앱용이다).
