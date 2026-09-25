# 공유 리포트(어가 열람 화면) 가이드

수산질병관리원이 "공유하기"로 보낸 링크(`/r/:token`)를 어가가 카톡/문자로 열어
로그인 없이 보는 읽기 전용 페이지입니다. 상호작용은 **조치사항 체크**와
**문의하기(전화/메모)** 두 가지뿐입니다.

## 1. 적용 순서

```bash
cd server
npm run migrate   # 003_shared_report.sql 적용
npm run seed      # /r/demo 예시 데이터 생성 (주의: 기존 데이터를 truncate 함)
npm start
```

Flutter는 `API_BASE_URL`이 설정되면 서버에, 아니면 mock(`/r/demo`)에 붙습니다.

## 2. 리포트 작성 가이드 (기관 담당자가 채우는 값)

| 필드 | 작성 요령 | 예시 |
|---|---|---|
| `overallStatus.summary` | 한 줄(30자 내외). 결론부터 | 고수온 지속으로 관찰이 필요합니다 |
| `diagnosis` | 전문가 서술. 관찰 → 판단 → 권고 순서, 3~5문장, 전문용어는 풀어서 | 아가미 색이 옅어지고 유영이 둔한 개체가 관찰되었습니다. 고수온 스트레스로 판단되며… |
| `actions[].title` | 어가가 바로 할 수 있는 동사형, 20자 이내 | 사료량 줄이기 |
| `actions[].sub` | 기준·수치를 붙인 부연 설명 | 평소의 70% 수준으로, 수온이 내려갈 때까지 유지 |
| `flaggedPhotos[].label` | 무엇이 문제인지 4~10자 | 아가미 색 변화 |
| `flaggedPhotos[].needsAttention` | 이상 소견이면 `true`(amber 테두리) | true |
| `videoDuration` | 사람이 읽는 형식 | 3분 42초 |
| `organizations.phone` | 문의 전화번호(하이픈 포함 가능) | 061-555-0123 |

## 3. API

### GET `/api/public/reports/:token` (공개)
기존 `farm`/`report`/`link`에 화면용 `shared`가 추가되었습니다.
만료·폐기 링크는 `404 {"error":"링크가 만료되었거나 존재하지 않습니다."}`.

```json
{
  "shared": {
    "farmName": "신일수산 1양식장",
    "species": "우럭",
    "orgName": "해강수산질병관리원",
    "sharedAt": "2026-09-26T01:30:00.000Z",
    "overallStatus": { "level": "watch", "summary": "고수온 지속으로 관찰이 필요합니다" },
    "metrics": [
      { "label": "주간 폐사", "value": "18", "unit": "마리", "note": "최근 7일 누적" },
      { "label": "평균 수온", "value": "29.1", "unit": "℃", "note": "9월 리포트" }
    ],
    "flaggedPhotos": [{ "url": "", "label": "아가미 색 변화", "needsAttention": true }],
    "diagnosis": "이번 달 방문 시 …",
    "actions": [
      { "id": "0b1e…", "title": "사료량 줄이기", "sub": "평소의 70% 수준으로…", "done": false }
    ],
    "videoUrl": "https://example.com/videos/demo-field.mp4",
    "videoDuration": "3분 42초",
    "contactPhone": "061-555-0123"
  }
}
```
- `level`: `good` | `watch` | `urgent` (DB `risk_level` `good`/`warning`/`danger`에서 변환)
- `flaggedPhotos[].url`이 빈 문자열이면 플레이스홀더 타일로 표시
- `videoUrl`이 `null`이면 영상 카드 숨김, 사진이 없으면 사진 섹션 숨김

### PATCH `/api/public/reports/:token/actions/:actionId`
```json
// request
{ "done": true }
// 200
{ "id": "0b1e…", "done": true }
```
링크의 양식장 리포트에 속한 조치사항만 변경 가능(다른 양식장은 404).
화면은 낙관적 업데이트 후 실패 시 되돌리고 스낵바로 알립니다.

### POST `/api/public/reports/:token/inquiries`
```json
// request (최대 500자)
{ "message": "오늘 아침부터 우럭 폐사가 늘었습니다. 방문 가능한 시간이 언제인가요?" }
// 201
{ "ok": true }
```
`inquiries`에 저장되고, 기관 앱 메모 목록에도 `author_type='farm'`, 태그 `문의`로
나타납니다.

## 4. 데이터 모델 (003_shared_report.sql)

- `organizations.phone`
- `reports.species | diagnosis | flagged_photos(jsonb) | video_url | video_duration`
- `report_actions(id, report_id, position, title, sub, done, done_at)` — 기존
  리포트는 첫 공유 열람 시 `follow_ups`에서 자동 생성
- `inquiries(id, share_link_id, farm_id, message, created_at)`

## 5. 알려진 한계 / 다음 단계

- 사진 업로드·저장소가 없어 `flagged_photos.url`은 직접 URL을 넣어야 합니다.
  기관 앱에서 진단 소견/사진/영상을 입력하는 화면은 아직 없습니다.
- 규칙 기반 리포트 생성은 `diagnosis`를 채우지 않아, 비어 있으면 요약+소견으로 대체됩니다.
- 공개 POST/PATCH에는 rate limit이 없습니다(토큰이 추측 어려운 값이라는 점에만 의존).
- PDF 저장 버튼은 아직 "준비 중"입니다.
