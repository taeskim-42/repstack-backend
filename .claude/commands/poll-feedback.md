# TestFlight 피드백 즉시 폴링

ASC API에서 TestFlight 피드백을 즉시 가져와서 분석 파이프라인을 실행합니다.

## 실행

1. 먼저 Railway에서 ADMIN_SECRET_TOKEN을 가져옵니다:

```bash
TOKEN=$(railway variables --json | python3 -c "import sys,json; print(json.load(sys.stdin)['ADMIN_SECRET_TOKEN'])")
```

2. 폴링을 트리거합니다:

```bash
curl -s -X POST "https://repstack-backend-production.up.railway.app/admin/poll_testflight" \
  -H "X-Admin-Token: $TOKEN" | python3 -m json.tool
```

## 결과 해석

- `new_feedback_count`: 새로 발견된 피드백 수
- `results`: 각 피드백의 ID, ASC ID, 텍스트 미리보기
- `skipped: duplicate`: 이미 처리된 피드백

새 피드백이 있으면 자동으로 AI 분석 → GitHub Issue 생성까지 진행됩니다.
피드백이 0건이면 "새 피드백 없음"으로 알려주세요.
