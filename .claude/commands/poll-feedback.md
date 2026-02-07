# TestFlight 피드백 → Opus 분석 → Codex 검증 → Opus 수정

열린 TestFlight 피드백 GitHub Issue를 가져오고, Opus 4.6이 분석/수정한 뒤 Codex 5.2가 검증하고, Opus가 최종 반영하는 파이프라인입니다.

```
[Opus 4.6] Issue 폴링 + 분석 + 1차 수정
      ↓  diff 저장
[Codex 5.2] 수정안 검증 (버그, 사이드이펙트, 누락 체크)
      ↓  검증 리포트
[Opus 4.6] 검증 피드백 반영 → 최종 수정
```

## Step 1: 열린 피드백 Issue 가져오기

backend와 frontend 레포에서 열린 testflight-feedback Issue를 가져옵니다:

```bash
gh issue list --repo taeskim-42/repstack-backend --label testflight-feedback --state open --json number,title,body,createdAt --limit 10
gh issue list --repo taeskim-42/repstack-frontend --label testflight-feedback --state open --json number,title,body,createdAt --limit 10
```

**Issue가 0건이면 "열린 피드백 없음"으로 알려주고 종료합니다.**

## Step 2: Issue 상세 + 스크린샷 다운로드

각 Issue의 상세 내용을 읽습니다:

```bash
gh issue view <NUMBER> --repo <REPO> --json title,body,labels,createdAt
```

### 스크린샷 가져오기 (2단계)

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

이미지 URL이 있으면 로컬에 다운로드합니다:

```bash
mkdir -p /tmp/testflight-feedback
curl -sL "<IMAGE_URL>" -o /tmp/testflight-feedback/issue-<NUMBER>-screenshot-1.jpg
```

다운로드한 스크린샷은 Read 도구로 직접 확인합니다 (이미지 파일 읽기 지원).
스크린샷이 없는 Issue는 텍스트 정보만으로 진행합니다.

## Step 3: Opus 분석 + 1차 코드 수정

각 피드백에 대해:

1. Issue 본문에서 핵심 정보를 추출하여 사용자에게 요약 보고:
   - 유저 피드백 원문
   - 카테고리 / 심각도
   - AI 분석 원인 및 수정 제안
   - 스크린샷 (있으면 직접 확인)

2. 관련 코드를 읽고 분석한 뒤 수정 방안을 설명

3. 사용자 승인 후 1차 코드 수정 실행

**feature_request는 수정 대신 구현 계획만 제안하고 여기서 종료합니다.**

## Step 4: Codex 5.2 검증

1차 수정 후 diff를 저장하고 Codex에게 검증을 요청합니다:

```bash
# 수정된 diff 저장
git diff > /tmp/testflight-feedback/patch-issue-<NUMBER>.diff

# Codex 5.2로 코드 리뷰 (비대화형, 읽기 전용)
codex-gn exec \
  --model openai/gpt-5.2-codex \
  -a never \
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

## Step 5: 검증 결과 반영 + 최종 수정

Codex 검증 리포트(`/tmp/testflight-feedback/codex-review-<NUMBER>.txt`)를 Read로 읽습니다.

- **approved: true** → 수정 유지, 사용자에게 최종 확인 후 커밋
- **approved: false** → Codex가 지적한 issues/suggestions를 반영하여 코드 재수정 후 사용자에게 보고

최종 수정 완료 후 `/commit` 여부를 사용자에게 확인합니다.
