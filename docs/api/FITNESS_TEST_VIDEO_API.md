# 영상 기반 체력 테스트 API

## 개요
사용자가 운동 영상을 업로드하면 Claude Vision AI가 분석하여 반복 횟수와 자세 점수를 측정합니다.

## 플로우
```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│ 1. URL  │────▶│ 2. S3   │────▶│ 3. 제출 │────▶│ 4. 폴링 │
│   요청   │     │  업로드  │     │         │     │   결과   │
└─────────┘     └─────────┘     └─────────┘     └─────────┘
```

---

## Step 1: 업로드 URL 받기

각 운동별로 호출합니다.

```graphql
mutation CreateFitnessTestUploadUrl($input: CreateFitnessTestUploadUrlInput!) {
  createFitnessTestUploadUrl(input: $input) {
    uploadUrl    # S3 presigned URL
    videoKey     # 나중에 제출할 때 사용
    expiresAt    # URL 만료 시간 (1시간)
    errors
  }
}
```

**Variables:**
```json
{
  "input": {
    "exerciseType": "pushup",
    "contentType": "video/mp4"
  }
}
```

**exerciseType 예시:**
| 맨몸 운동 | 바벨 운동 |
|----------|----------|
| `pushup` | `bench_press` |
| `squat` | `barbell_squat` |
| `pullup` | `deadlift` |

---

## Step 2: S3에 영상 업로드

받은 `uploadUrl`로 직접 PUT 요청합니다.

```swift
// iOS 예시
func uploadVideo(url: URL, videoData: Data) async throws {
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")

    let (_, response) = try await URLSession.shared.upload(for: request, from: videoData)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw UploadError.failed
    }
}
```

```typescript
// React Native 예시
const uploadVideo = async (uploadUrl: string, videoUri: string) => {
  const response = await fetch(videoUri);
  const blob = await response.blob();

  await fetch(uploadUrl, {
    method: 'PUT',
    headers: { 'Content-Type': 'video/mp4' },
    body: blob,
  });
};
```

---

## Step 3: 영상 제출

모든 영상 업로드 완료 후 호출합니다.

```graphql
mutation SubmitFitnessTestVideos($input: SubmitFitnessTestVideosInput!) {
  submitFitnessTestVideos(input: $input) {
    submissionId  # DB ID
    jobId         # 폴링용 고유 ID
    status        # PENDING
    errors
  }
}
```

**Variables:**
```json
{
  "input": {
    "videos": [
      { "exerciseType": "pushup", "videoKey": "fitness-tests/123/pushup_xxx.mp4" },
      { "exerciseType": "squat", "videoKey": "fitness-tests/123/squat_xxx.mp4" },
      { "exerciseType": "pullup", "videoKey": "fitness-tests/123/pullup_xxx.mp4" }
    ]
  }
}
```

**바벨 운동 예시:**
```json
{
  "input": {
    "videos": [
      { "exerciseType": "bench_press", "videoKey": "fitness-tests/123/bench_xxx.mp4" },
      { "exerciseType": "barbell_squat", "videoKey": "fitness-tests/123/squat_xxx.mp4" },
      { "exerciseType": "deadlift", "videoKey": "fitness-tests/123/dead_xxx.mp4" }
    ]
  }
}
```

---

## Step 4: 결과 폴링

`jobId`로 결과를 조회합니다. 3-5초 간격으로 폴링하세요.

```graphql
query GetFitnessTestResult($jobId: String) {
  getFitnessTestResult(jobId: $jobId) {
    status           # PENDING | PROCESSING | COMPLETED | FAILED
    fitnessScore     # 0-100
    assignedLevel    # 1-7
    assignedTier     # beginner | intermediate | advanced
    message          # 동기부여 메시지
    recommendations  # 추천 사항 배열

    videos {
      exerciseType
      videoKey
    }

    analyses {
      exerciseType   # "pushup", "bench_press" 등
      repCount       # 반복 횟수
      formScore      # 자세 점수 0-100
      issues         # 문제점 배열 ["무릎이 안쪽으로 모임"]
      feedback       # 피드백 텍스트
    }

    errorMessage     # 실패 시 에러 메시지
  }
}
```

**응답 예시 (완료):**
```json
{
  "data": {
    "getFitnessTestResult": {
      "status": "COMPLETED",
      "fitnessScore": 75,
      "assignedLevel": 3,
      "assignedTier": "intermediate",
      "message": "좋은 기초 체력을 보유하고 계시네요! 🔥",
      "recommendations": ["균형 잡힌 훈련을 유지하세요"],
      "analyses": [
        {
          "exerciseType": "pushup",
          "repCount": 20,
          "formScore": 80,
          "issues": [],
          "feedback": "훌륭한 자세입니다!"
        },
        {
          "exerciseType": "squat",
          "repCount": 25,
          "formScore": 70,
          "issues": ["무릎이 약간 안쪽으로 모임"],
          "feedback": "무릎을 발끝 방향으로 유지하세요"
        },
        {
          "exerciseType": "pullup",
          "repCount": 8,
          "formScore": 75,
          "issues": [],
          "feedback": "좋은 동작 범위입니다"
        }
      ]
    }
  }
}
```

---

## 전체 플로우 코드 예시

```typescript
// 1. 업로드 URL 받기 (3개 운동)
const exercises = ['pushup', 'squat', 'pullup'];
const videoKeys: { exerciseType: string; videoKey: string }[] = [];

for (const exercise of exercises) {
  const { data } = await client.mutate({
    mutation: CREATE_UPLOAD_URL,
    variables: { input: { exerciseType: exercise } }
  });

  const { uploadUrl, videoKey } = data.createFitnessTestUploadUrl;

  // 2. S3 업로드
  await uploadVideo(uploadUrl, videoFiles[exercise]);

  videoKeys.push({ exerciseType: exercise, videoKey });
}

// 3. 제출
const { data: submitData } = await client.mutate({
  mutation: SUBMIT_VIDEOS,
  variables: { input: { videos: videoKeys } }
});

const { jobId } = submitData.submitFitnessTestVideos;

// 4. 폴링
const pollResult = async () => {
  const { data } = await client.query({
    query: GET_RESULT,
    variables: { jobId },
    fetchPolicy: 'network-only'
  });

  const { status } = data.getFitnessTestResult;

  if (status === 'COMPLETED' || status === 'FAILED') {
    return data.getFitnessTestResult;
  }

  await sleep(3000);
  return pollResult();
};

const result = await pollResult();
```

---

## 에러 처리

| 에러 메시지 | 원인 | 해결 |
|------------|------|------|
| "인증이 필요합니다" | 토큰 없음/만료 | 재로그인 |
| "이미 레벨이 측정되었습니다" | 이미 테스트 완료 | 승급 테스트로 유도 |
| "이미 처리 중인 테스트가 있습니다" | 중복 제출 | 기존 jobId로 폴링 |
| "지원하지 않는 파일 형식입니다" | video/mp4 외 | mp4로 변환 |

---

## 참고

- **분석 소요 시간**: 약 30초-2분 (영상 길이에 따라)
- **지원 포맷**: video/mp4, video/quicktime, video/x-m4v
- **최대 영상 수**: 10개
- **영상 저장**: 분석 후 자동 삭제 (비용 절감)
