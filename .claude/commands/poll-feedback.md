# TestFlight 피드백 → Opus 독립 분석 → Codex 검증 → Opus 수정

TestFlight 피드백을 가져와서 Opus가 **스크린샷 + 코드를 직접 조사**하고, Codex가 검증하는 파이프라인입니다.

> ⚠️ Issue의 AI Analysis는 없습니다 — Haiku는 분류만 하고, 근본 원인 분석은 여기서 Opus가 직접 합니다.

```
[Step 0] ASC 폴링 → DB 저장 + Issue 생성
[Step 1] Issue 폴링 (backend + frontend)
[Step 2] 스크린샷 다운로드 + Read로 직접 확인
[Step 3] Plan 모드 → 코드 직접 탐색 → 근본 원인 분석
[Step 4] 사용자 승인 → 1차 수정
[Step 5] Codex 검증 → 최종 수정
```

## Step 0: ASC API에서 최신 피드백 즉시 가져오기

Sidekiq 크론잡(5분 간격)을 기다리지 않고, 먼저 수동으로 ASC 폴링을 트리거합니다:

```bash
curl -s 'https://repstack-backend-production.up.railway.app/admin/poll_testflight?admin_token=repstack_admin_1864a749b23220d903a0c3636c1e83b1' -X POST | python3 -m json.tool
```

새 피드백이 있으면 DB에 저장되고, AI 분류 + GitHub Issue 생성이 자동으로 실행됩니다.
`new_feedback_count > 0`이면 파이프라인 처리를 위해 **30초 대기** 후 Step 1로 진행합니다:

```bash
sleep 30
```

스크린샷 backfill도 함께 트리거합니다 (ASC race condition 대응):

```bash
curl -s 'https://repstack-backend-production.up.railway.app/admin/backfill_screenshots?admin_token=repstack_admin_1864a749b23220d903a0c3636c1e83b1' -X POST | python3 -m json.tool
```

## Step 1: 열린 피드백 Issue 가져오기

backend와 frontend 레포에서 열린 testflight-feedback Issue를 가져옵니다:

```bash
gh issue list --repo taeskim-42/repstack-backend --label testflight-feedback --state open --json number,title,body,createdAt --limit 10
gh issue list --repo taeskim-42/repstack-frontend --label testflight-feedback --state open --json number,title,body,createdAt --limit 10
```

**Issue가 0건이면 "열린 피드백 없음"으로 알려주고 종료합니다.**

## Step 2: Issue 상세 + 스크린샷 필수 분석

각 Issue의 상세 내용을 읽습니다:

```bash
gh issue view <NUMBER> --repo <REPO> --json title,body,labels,createdAt
```

### 스크린샷 가져오기 (필수 — 반드시 시도)

**1단계: Issue 본문에서 추출**
Issue 본문의 `## Screenshots` 섹션에서 이미지 URL을 추출합니다 (`![Screenshot N](URL)` 형식).

**2단계: Fallback - Admin API에서 가져오기**
Issue 본문에 `## Screenshots` 섹션이 없으면, Admin API에서 스크린샷을 조회합니다:

```bash
curl -s 'https://repstack-backend-production.up.railway.app/admin/testflight_feedbacks?admin_token=repstack_admin_1864a749b23220d903a0c3636c1e83b1&limit=50' | python3 -c "
import sys, json
data = json.load(sys.stdin)
for f in data['feedbacks']:
    issue_url = f.get('github_issue_url', '')
    if '<REPO>/issues/<NUMBER>' in issue_url and f.get('screenshots'):
        for i, url in enumerate(f['screenshots']):
            print(f'SCREENSHOT_{i+1}: {url}')
"
```

이미지 URL이 있으면 **반드시** 로컬에 다운로드하고 Read로 확인합니다:

```bash
mkdir -p /tmp/testflight-feedback
curl -sL "<IMAGE_URL>" -o /tmp/testflight-feedback/issue-<NUMBER>-screenshot-1.jpg
```

다운로드한 스크린샷은 **Read 도구로 직접 확인**합니다 (이미지 파일 읽기 지원).

> 🔴 **스크린샷이 있으면 반드시 다운로드 + Read로 확인해야 합니다.**
> 스크린샷을 보지 않고 텍스트만으로 추측하면 잘못된 진단을 합니다.
> 스크린샷에서 UI 상태, 에러 메시지, 데이터 표시 등을 직접 눈으로 확인하세요.

스크린샷이 없는 Issue는 텍스트 정보만으로 진행합니다.

## Step 3: Opus 독립 분석 (Plan 모드)

> ⚠️ Issue 본문에는 AI Analysis가 없습니다. Haiku는 분류(category/severity)만 했으므로,
> 근본 원인 분석은 **여기서 Opus가 코드를 직접 읽고 판단**해야 합니다.

**반드시 `EnterPlanMode`로 진입한 후** 다음을 수행합니다:

### 3-1. 정보 수집

각 피드백에 대해 사용자에게 요약 보고:
- 유저 피드백 원문
- 카테고리 / 심각도
- 스크린샷에서 관찰된 내용 (있으면)

### 3-2. 코드 직접 탐색

스크린샷과 피드백 텍스트를 기반으로 **관련 코드를 직접 읽고 탐색**합니다:

- GraphQL mutation/query 확인
- Service 레이어 확인
- 모델 로직 확인
- iOS 코드가 필요하면 frontend repo도 탐색

### 3-3. RepStack 함정 체크리스트

코드를 읽을 때 다음 **알려진 함정**을 반드시 확인합니다:

| # | 함정 | 올바른 패턴 |
|---|------|------------|
| 1 | WorkoutSession active 상태 | `end_time.nil?`로 판단 (NOT `status == "active"`) |
| 2 | 듀얼 데이터 경로 | 채팅 기록 → `workout_sets`만 / 앱 기록 → `workout_sets` + `workout_records` |
| 3 | 컬럼명 매핑 | `how_to` NOT `instructions`, `weight_description` NOT `weight_guide` |
| 4 | GraphQL 타입 네이밍 | DB `estimated_duration` ↔ iOS `estimated_duration_minutes` |
| 5 | 타임존 | `config.time_zone = "Asia/Seoul"` 설정됨, `in_time_zone` 중복 호출 불필요 |

### 3-4. 분석 결과 보고

Plan 모드에서 다음을 사용자에게 보고합니다:
- 근본 원인 (코드 레벨)
- 영향 범위
- 수정 방안 (구체적 파일 + 라인)
- **feature_request는 구현 계획만 제안하고 여기서 종료**

## Step 4: 사용자 승인 → 1차 코드 수정

사용자 승인 후 `ExitPlanMode`로 나와서 코드를 수정합니다.

## Step 5: Codex 5.2 검증

1차 수정 후 diff를 저장하고 Codex에게 검증을 요청합니다:

```bash
# 수정된 diff 저장
git diff > /tmp/testflight-feedback/patch-issue-<NUMBER>.diff

# Codex 5.2로 코드 리뷰 (비대화형, 읽기 전용)
codex-gn exec \
  --model openai/gpt-5.2-codex \
  --full-auto \
  --sandbox read-only \
  "다음 git diff를 리뷰해줘. 이 패치는 TestFlight 피드백 Issue #<NUMBER>에 대한 수정이야.

피드백 원문: <FEEDBACK_TEXT>

리뷰 기준:
1. 버그가 있는지 (null 체크 누락, 타입 에러, 로직 오류)
2. 사이드이펙트가 있는지 (다른 기능에 영향)
3. 피드백이 요구한 문제가 실제로 해결되는지
4. 누락된 수정이 있는지

diff 내용:
$(cat /tmp/testflight-feedback/patch-issue-<NUMBER>.diff)

JSON 형식으로 응답해줘:
{
  \"approved\": true/false,
  \"issues\": [\"발견된 문제 목록\"],
  \"suggestions\": [\"개선 제안 목록\"],
  \"verdict\": \"한줄 요약\"
}" 2>&1 | tee /tmp/testflight-feedback/codex-review-<NUMBER>.txt
```

## Step 6: 검증 결과 반영 + 최종 수정

Codex 검증 리포트(`/tmp/testflight-feedback/codex-review-<NUMBER>.txt`)를 Read로 읽습니다.

- **approved: true** → 수정 유지, 사용자에게 최종 확인 후 커밋
- **approved: false** → Codex가 지적한 issues/suggestions를 반영하여 코드 재수정 후 사용자에게 보고

최종 수정 완료 후 `/commit` 여부를 사용자에게 확인합니다.
