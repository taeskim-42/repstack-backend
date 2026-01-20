# RepStack API Reference

**Version**: 1.0.0
**Base URL**: `POST /graphql`
**Content-Type**: `application/json`

---

## 목차

1. [인증](#인증)
2. [응답 형식](#응답-형식)
3. [Mutations](#mutations-17개)
   - [인증](#인증-mutations)
   - [프로필](#프로필-mutations)
   - [운동 세션](#운동-세션-mutations)
   - [루틴](#루틴-mutations)
   - [AI 기능](#ai-기능-mutations)
   - [승급 시스템](#승급-시스템-mutations)
4. [Queries](#queries-12개)
5. [Types](#types)
6. [Enums](#enums)
7. [에러 처리](#에러-처리)

---

## 인증

모든 API는 인증이 필요합니다. (예외: `health`, `version`, `signInWithApple`, `devSignIn`)

```
Authorization: Bearer <token>
```

### 토큰 발급
- **프로덕션**: `signInWithApple` mutation
- **개발/테스트**: `devSignIn` mutation

### 토큰 만료
- 유효기간: 24시간
- 만료 시 재로그인 필요

---

## 응답 형식

### GraphQL 요청
```json
{
  "query": "mutation { ... }",
  "variables": { "key": "value" }
}
```

### 성공 응답 - CRUD Mutations
```json
{
  "data": {
    "mutationName": {
      "resourceName": { /* 리소스 데이터 */ },
      "errors": []
    }
  }
}
```

### 성공 응답 - AI Mutations (⚡ 표시)
```json
{
  "data": {
    "mutationName": {
      "success": true,
      "resourceName": { /* 리소스 데이터 */ },
      "error": null
    }
  }
}
```

### 에러 응답
```json
{
  "errors": [
    {
      "message": "에러 메시지",
      "extensions": { "code": "ERROR_CODE" }
    }
  ]
}
```

---

# Mutations (17개)

## 인증 Mutations

### signInWithApple

Apple Sign In으로 인증합니다.

**인증 필요**: ❌

```graphql
mutation SignInWithApple($identityToken: String!, $userName: String) {
  signInWithApple(input: {
    identityToken: $identityToken
    userName: $userName
  }) {
    authPayload {
      token
      user {
        id
        email
        name
      }
    }
    errors
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `identityToken` | `String!` | ✓ | Apple에서 발급한 JWT identity token |
| `userName` | `String` | | 사용자 이름 (최초 로그인 시에만 전달됨) |

**Response Fields**

| 필드 | 타입 | 설명 |
|------|------|------|
| `authPayload.token` | `String` | JWT 액세스 토큰 (24시간 유효) |
| `authPayload.user` | `User` | 사용자 정보 |
| `errors` | `[String]` | 에러 메시지 배열 |

**Example Response**
```json
{
  "data": {
    "signInWithApple": {
      "authPayload": {
        "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
        "user": {
          "id": "1",
          "email": "user@example.com",
          "name": "홍길동"
        }
      },
      "errors": []
    }
  }
}
```

**iOS Implementation**
```swift
import AuthenticationServices

func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) {
    guard let identityToken = credential.identityToken,
          let tokenString = String(data: identityToken, encoding: .utf8) else { return }

    let userName = [credential.fullName?.givenName, credential.fullName?.familyName]
        .compactMap { $0 }
        .joined(separator: " ")

    // GraphQL 호출
    // variables: { identityToken: tokenString, userName: userName.isEmpty ? nil : userName }
}
```

---

### devSignIn

개발/테스트 환경 전용 로그인입니다.

> **활성화 조건**: `RAILS_ENV=development` / `RAILS_ENV=test` / `ALLOW_DEV_SIGN_IN=true`

**인증 필요**: ❌

```graphql
mutation DevSignIn($email: String, $name: String) {
  devSignIn(input: {
    email: $email
    name: $name
  }) {
    authPayload {
      token
      user {
        id
        email
        name
      }
    }
    errors
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|:----:|--------|------|
| `email` | `String` | | `test@example.com` | 테스트 사용자 이메일 |
| `name` | `String` | | `Test User` | 테스트 사용자 이름 |

**cURL Example**
```bash
# 기본 테스트 사용자
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { devSignIn(input: {}) { authPayload { token } errors } }"}'

# 커스텀 사용자
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { devSignIn(input: { email: \"dev@test.com\", name: \"개발자\" }) { authPayload { token } errors } }"}'
```

---

## 프로필 Mutations

### updateProfile

신체 정보와 피트니스 설정을 수정합니다.

**인증 필요**: ✅

```graphql
mutation UpdateProfile($input: UserProfileInput!) {
  updateProfile(input: { profileInput: $input }) {
    userProfile {
      id
      height
      weight
      bodyFatPercentage
      fitnessGoal
    }
    errors
  }
}
```

**UserProfileInput Type**
```graphql
input UserProfileInput {
  height: Float           # 키 (cm)
  weight: Float           # 몸무게 (kg)
  bodyFatPercentage: Float # 체지방률 (%)
  fitnessGoal: String      # 운동 목표
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `height` | `Float` | | 키 (cm) |
| `weight` | `Float` | | 몸무게 (kg) |
| `bodyFatPercentage` | `Float` | | 체지방률 (%) |
| `fitnessGoal` | `String` | | 운동 목표 |

---

### updateUserProfile

개별 프로필 필드를 수정합니다.

**인증 필요**: ✅

```graphql
mutation UpdateUserProfile(
  $height: Float
  $weight: Float
  $bodyFatPercentage: Float
  $currentLevel: String
  $fitnessGoal: String
  $weekNumber: Int
  $dayNumber: Int
) {
  updateUserProfile(input: {
    height: $height
    weight: $weight
    bodyFatPercentage: $bodyFatPercentage
    currentLevel: $currentLevel
    fitnessGoal: $fitnessGoal
    weekNumber: $weekNumber
    dayNumber: $dayNumber
  }) {
    userProfile {
      id
      height
      weight
      bodyFatPercentage
      currentLevel
      fitnessGoal
      weekNumber
      dayNumber
      bmi
      bmiCategory
    }
    errors
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `height` | `Float` | | 키 (cm) |
| `weight` | `Float` | | 몸무게 (kg) |
| `bodyFatPercentage` | `Float` | | 체지방률 (%) |
| `currentLevel` | `String` | | 현재 레벨 (beginner, intermediate, advanced) |
| `fitnessGoal` | `String` | | 운동 목표 |
| `weekNumber` | `Int` | | 현재 주차 (1-52) |
| `dayNumber` | `Int` | | 현재 일차 (1-7) |

---

## 운동 세션 Mutations

### startWorkoutSession

새 운동 세션을 시작합니다.

**인증 필요**: ✅

```graphql
mutation StartWorkoutSession($name: String, $notes: String) {
  startWorkoutSession(input: {
    name: $name
    notes: $notes
  }) {
    workoutSession {
      id
      name
      startTime
      notes
      active
    }
    errors
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `name` | `String` | | 세션 이름 |
| `notes` | `String` | | 메모 |

**Example Response**
```json
{
  "data": {
    "startWorkoutSession": {
      "workoutSession": {
        "id": "123",
        "name": "오늘의 운동",
        "startTime": "2024-01-20T10:00:00Z",
        "notes": null,
        "active": true
      },
      "errors": []
    }
  }
}
```

---

### addWorkoutSet

운동 세트를 기록합니다.

**인증 필요**: ✅

```graphql
mutation AddWorkoutSet(
  $sessionId: ID!
  $exerciseName: String!
  $weight: Float
  $weightUnit: String
  $reps: Int
  $durationSeconds: Int
  $notes: String
) {
  addWorkoutSet(input: {
    sessionId: $sessionId
    exerciseName: $exerciseName
    weight: $weight
    weightUnit: $weightUnit
    reps: $reps
    durationSeconds: $durationSeconds
    notes: $notes
  }) {
    workoutSet {
      id
      exerciseName
      weight
      weightUnit
      reps
      durationSeconds
      notes
      volume
    }
    errors
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|:----:|--------|------|
| `sessionId` | `ID!` | ✓ | | 세션 ID |
| `exerciseName` | `String!` | ✓ | | 운동 이름 |
| `weight` | `Float` | | | 무게 |
| `weightUnit` | `String` | | `kg` | 무게 단위 (kg, lbs) |
| `reps` | `Int` | | | 반복 횟수 |
| `durationSeconds` | `Int` | | | 운동 시간 (초) - 플랭크 등 |
| `notes` | `String` | | | 메모 |

---

### endWorkoutSession

운동 세션을 종료합니다.

**인증 필요**: ✅

```graphql
mutation EndWorkoutSession($id: ID!) {
  endWorkoutSession(input: { id: $id }) {
    workoutSession {
      id
      startTime
      endTime
      durationInSeconds
      durationFormatted
      active
      completed
      totalSets
      totalVolume
    }
    errors
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `id` | `ID!` | ✓ | 종료할 세션 ID |

**Response Fields**

| 필드 | 타입 | 설명 |
|------|------|------|
| `durationInSeconds` | `Int` | 총 운동 시간 (초) |
| `durationFormatted` | `String` | 포맷된 운동 시간 (예: "1h 30m") |
| `active` | `Boolean` | 활성 여부 (종료 후 false) |
| `completed` | `Boolean` | 완료 여부 (종료 후 true) |
| `totalSets` | `Int` | 총 세트 수 |
| `totalVolume` | `Float` | 총 볼륨 (무게 × 반복수) |

---

## 루틴 Mutations

### saveRoutine

루틴을 저장합니다.

**인증 필요**: ✅

```graphql
mutation SaveRoutine(
  $level: String!
  $weekNumber: Int!
  $dayNumber: Int!
  $workoutType: String!
  $dayOfWeek: String!
  $estimatedDuration: Int!
  $exercises: [ExerciseInput!]!
) {
  saveRoutine(input: {
    level: $level
    weekNumber: $weekNumber
    dayNumber: $dayNumber
    workoutType: $workoutType
    dayOfWeek: $dayOfWeek
    estimatedDuration: $estimatedDuration
    exercises: $exercises
  }) {
    workoutRoutine {
      id
      level
      weekNumber
      dayNumber
    }
    errors
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `level` | `String!` | ✓ | 레벨 (beginner, intermediate, advanced) |
| `weekNumber` | `Int!` | ✓ | 주차 (1-52) |
| `dayNumber` | `Int!` | ✓ | 일차 (1-7) |
| `workoutType` | `String!` | ✓ | 운동 유형 (upper_body, lower_body, full_body, cardio) |
| `dayOfWeek` | `String!` | ✓ | 요일 (Monday-Sunday) |
| `estimatedDuration` | `Int!` | ✓ | 예상 소요 시간 (분) |
| `exercises` | `[ExerciseInput!]!` | ✓ | 운동 목록 |

**ExerciseInput Type**
```graphql
input ExerciseInput {
  exerciseName: String!      # 운동 이름
  targetMuscle: String!      # 타겟 근육
  orderIndex: Int!           # 순서
  sets: Int!                 # 세트 수
  reps: Int!                 # 반복 횟수
  weight: Float              # 권장 무게
  restDurationSeconds: Int!  # 휴식 시간 (초)
  rangeOfMotion: String!     # 가동 범위 설명
  howTo: String!             # 운동 방법
  purpose: String!           # 운동 목적
}
```

---

### completeRoutine

루틴을 완료 처리합니다.

**인증 필요**: ✅

```graphql
mutation CompleteRoutine($routineId: ID!) {
  completeRoutine(input: { routineId: $routineId }) {
    routine {
      id
      isCompleted
    }
    errors
  }
}
```

---

## AI 기능 Mutations

### generateAiRoutine ⚡

AI가 개인화된 루틴을 생성합니다.

**인증 필요**: ✅

```graphql
mutation GenerateAiRoutine($dayOfWeek: Int, $condition: ConditionInput) {
  generateAiRoutine(input: {
    dayOfWeek: $dayOfWeek
    condition: $condition
  }) {
    success
    routine {
      name
      exercises {
        exerciseName
        targetMuscle
        sets
        reps
        weight
      }
    }
    error
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `dayOfWeek` | `Int` | | 요일 (1=월요일, 7=일요일) |
| `condition` | `ConditionInput` | | 현재 컨디션 |

---

### checkCondition ⚡

컨디션을 체크하고 운동 조정 권고를 받습니다. (구조화된 입력)

**인증 필요**: ✅

```graphql
mutation CheckCondition($input: ConditionInput!) {
  checkCondition(input: $input) {
    success
    adaptations
    intensityModifier
    durationModifier
    exerciseModifications
    restRecommendations
    error
  }
}
```

**ConditionInput Type**
```graphql
input ConditionInput {
  energyLevel: Int!      # 에너지 레벨 (1-5)
  stressLevel: Int!      # 스트레스 레벨 (1-5)
  sleepQuality: Int!     # 수면 품질 (1-5)
  motivation: Int!       # 운동 의욕 (1-5)
  availableTime: Int!    # 가용 시간 (분)
  soreness: JSON         # 근육통 {"chest": 3, "legs": 2}
  notes: String          # 추가 메모
}
```

**Response Fields**

| 필드 | 타입 | 설명 |
|------|------|------|
| `adaptations` | `[String]` | 운동 조정 권고 목록 |
| `intensityModifier` | `Float` | 강도 조절 계수 (0.5-1.5) |
| `durationModifier` | `Float` | 시간 조절 계수 (0.7-1.3) |
| `exerciseModifications` | `[String]` | 운동 수정 사항 |
| `restRecommendations` | `[String]` | 휴식 권고 사항 |

---

### checkConditionFromVoice ⚡

**음성 입력**으로 컨디션을 체크합니다. AI가 자연어를 분석합니다.

**인증 필요**: ✅

```graphql
mutation CheckConditionFromVoice($voiceText: String!) {
  checkConditionFromVoice(input: { voiceText: $voiceText }) {
    success
    condition {
      energyLevel
      stressLevel
      sleepQuality
      motivation
      soreness
      availableTime
      notes
    }
    adaptations
    intensityModifier
    durationModifier
    exerciseModifications
    restRecommendations
    interpretation
    error
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `voiceText` | `String!` | ✓ | 음성 인식된 텍스트 |

**Example Inputs**
- `"오늘 좀 피곤하고 어깨가 아파요"`
- `"컨디션 좋아요, 운동하고 싶어요"`
- `"잠을 못 자서 힘들어요"`
- `"I'm feeling great today!"`

**Example Response**
```json
{
  "data": {
    "checkConditionFromVoice": {
      "success": true,
      "condition": {
        "energyLevel": 2,
        "stressLevel": 3,
        "sleepQuality": 3,
        "motivation": 3,
        "soreness": { "shoulder": 3 },
        "availableTime": 60,
        "notes": null
      },
      "adaptations": ["운동 강도를 낮추세요", "어깨 부위 운동을 피하세요"],
      "intensityModifier": 0.7,
      "durationModifier": 0.85,
      "exerciseModifications": ["어깨 운동 제외"],
      "restRecommendations": [],
      "interpretation": "피곤함과 어깨 통증이 감지되었습니다.",
      "error": null
    }
  }
}
```

---

### recordWorkout ⚡

운동 기록을 저장합니다.

**인증 필요**: ✅

```graphql
mutation RecordWorkout($input: WorkoutRecordInput!) {
  recordWorkout(input: $input) {
    success
    workoutRecord {
      id
      date
      totalDuration
      completionStatus
    }
    error
  }
}
```

**WorkoutRecordInput Type**
```graphql
input WorkoutRecordInput {
  routineId: ID!
  date: String                          # ISO 8601 (기본: 오늘)
  exercises: [ExerciseRecordInput!]!
  totalDuration: Int!                   # 총 운동 시간 (초)
  perceivedExertion: Int!               # RPE (1-10)
  completionStatus: CompletionStatus!   # COMPLETED, PARTIAL, SKIPPED
}

input ExerciseRecordInput {
  exerciseName: String!
  sets: Int!
  reps: Int!
  weight: Float
}
```

---

### submitFeedback ⚡

운동 피드백을 제출합니다. (구조화된 입력)

**인증 필요**: ✅

```graphql
mutation SubmitFeedback($input: FeedbackInput!) {
  submitFeedback(input: $input) {
    success
    feedback {
      id
      rating
      feedbackType
    }
    analysis {
      insights
      adaptations
      nextWorkoutRecommendations
    }
    error
  }
}
```

**FeedbackInput Type**
```graphql
input FeedbackInput {
  workoutRecordId: ID!
  routineId: ID!
  feedbackType: FeedbackType!   # DIFFICULTY, EFFECTIVENESS, ENJOYMENT, TIME, OTHER
  rating: Int!                  # 1-5
  feedback: String!             # 피드백 내용
  suggestions: [String]         # 개선 제안
  wouldRecommend: Boolean!      # 추천 여부
}
```

---

### submitFeedbackFromVoice ⚡

**음성 입력**으로 피드백을 제출합니다. AI가 자연어를 분석합니다.

**인증 필요**: ✅

```graphql
mutation SubmitFeedbackFromVoice($voiceText: String!, $routineId: ID) {
  submitFeedbackFromVoice(input: {
    voiceText: $voiceText
    routineId: $routineId
  }) {
    success
    feedback {
      id
      rating
      feedbackType
      summary
      wouldRecommend
    }
    analysis {
      insights
      adaptations
      nextWorkoutRecommendations
    }
    interpretation
    error
  }
}
```

**Parameters**

| 이름 | 타입 | 필수 | 설명 |
|------|------|:----:|------|
| `voiceText` | `String!` | ✓ | 음성 인식된 피드백 텍스트 |
| `routineId` | `ID` | | 루틴 ID (선택) |

**Example Inputs**
- `"오늘 운동 너무 힘들었어요, 무게가 무거웠어요"`
- `"운동 좋았어요! 다음에도 이렇게 하고 싶어요"`
- `"좀 쉬웠어요, 다음엔 더 무겁게 해도 될 것 같아요"`
- `"The workout was too hard today"`

**Example Response**
```json
{
  "data": {
    "submitFeedbackFromVoice": {
      "success": true,
      "feedback": {
        "id": "456",
        "rating": 2,
        "feedbackType": "DIFFICULTY",
        "summary": "운동이 힘들었다고 느꼈습니다",
        "wouldRecommend": false
      },
      "analysis": {
        "insights": ["운동이 힘들었다고 느꼈습니다"],
        "adaptations": ["다음 운동 강도를 낮추세요"],
        "nextWorkoutRecommendations": ["무게를 5-10% 줄여보세요"]
      },
      "interpretation": "사용자가 운동 강도가 높았다고 피드백했습니다.",
      "error": null
    }
  }
}
```

> **Note**: `analysis.adaptations`와 `analysis.nextWorkoutRecommendations`는 다음 `generateAiRoutine` 호출 시 자동으로 반영됩니다.

---

## 승급 시스템 Mutations

### startLevelTest ⚡

승급 시험을 시작합니다.

**인증 필요**: ✅

```graphql
mutation StartLevelTest {
  startLevelTest(input: {}) {
    success
    test {
      testId
      exercises {
        exerciseType
        targetWeightKg
        targetReps
      }
    }
    error
  }
}
```

**Response Fields**

| 필드 | 타입 | 설명 |
|------|------|------|
| `testId` | `String` | 시험 ID |
| `exercises` | `[LevelTestExercise]` | 시험 운동 목록 |
| `exercises.exerciseType` | `String` | 운동 유형 (bench, squat, deadlift) |
| `exercises.targetWeightKg` | `Float` | 목표 무게 (kg) |
| `exercises.targetReps` | `Int` | 목표 반복 횟수 |

---

### submitLevelTestResult ⚡

승급 시험 결과를 제출합니다.

**인증 필요**: ✅

```graphql
mutation SubmitLevelTestResult(
  $testId: String!
  $exercises: [LevelTestExerciseResultInput!]!
) {
  submitLevelTestResult(input: {
    testId: $testId
    exercises: $exercises
  }) {
    success
    passed
    newLevel
    feedback
    nextSteps
    error
  }
}
```

**LevelTestExerciseResultInput Type**
```graphql
input LevelTestExerciseResultInput {
  exerciseType: String!  # bench, squat, deadlift
  weightKg: Float!       # 실제 수행 무게
  reps: Int!             # 실제 수행 횟수
}
```

**Response Fields**

| 필드 | 타입 | 설명 |
|------|------|------|
| `passed` | `Boolean` | 합격 여부 |
| `newLevel` | `String` | 새로운 레벨 (합격 시) |
| `feedback` | `String` | AI 피드백 |
| `nextSteps` | `[String]` | 다음 단계 권고 |

---

# Queries (12개)

## health

서버 상태를 확인합니다.

**인증 필요**: ❌

```graphql
query {
  health
}
```

**Response**: `"ok"`

---

## version

API 버전을 확인합니다.

**인증 필요**: ❌

```graphql
query {
  version
}
```

**Response**: `"1.0.0"`

---

## node / nodes

Relay 표준 ID로 객체를 조회합니다.

**인증 필요**: ✅

```graphql
query Node($id: ID!) {
  node(id: $id) {
    id
    ... on User {
      email
      name
    }
    ... on WorkoutSession {
      startTime
      status
    }
    ... on WorkoutRoutine {
      name
      level
    }
  }
}

query Nodes($ids: [ID!]!) {
  nodes(ids: $ids) {
    id
    ... on User { email }
  }
}
```

---

## me

현재 로그인한 사용자 정보를 조회합니다.

**인증 필요**: ✅

```graphql
query Me {
  me {
    id
    email
    name
    createdAt
    updatedAt
    userProfile {
      id
      height
      weight
      bodyFatPercentage
      currentLevel
      weekNumber
      dayNumber
      fitnessGoal
      programStartDate
      bmi
      bmiCategory
      daysSinceStart
    }
  }
}
```

**Response Fields - UserProfile**

| 필드 | 타입 | 설명 |
|------|------|------|
| `height` | `Float` | 키 (cm) |
| `weight` | `Float` | 몸무게 (kg) |
| `bodyFatPercentage` | `Float` | 체지방률 (%) |
| `currentLevel` | `String` | 현재 레벨 (beginner, intermediate, advanced) |
| `weekNumber` | `Int` | 현재 주차 |
| `dayNumber` | `Int` | 현재 일차 (1-7) |
| `fitnessGoal` | `String` | 운동 목표 |
| `programStartDate` | `String` | 프로그램 시작일 (ISO8601) |
| `bmi` | `Float` | BMI 지수 (computed) |
| `bmiCategory` | `String` | BMI 분류 (Underweight, Normal, Overweight, Obese) |
| `daysSinceStart` | `Int` | 프로그램 시작 후 경과일 (computed) |

---

## todayRoutine

오늘의 루틴을 조회합니다.

**인증 필요**: ✅

```graphql
query TodayRoutine {
  todayRoutine {
    id
    name
    level
    weekNumber
    dayNumber
    isCompleted
    exercises {
      id
      exerciseName
      targetMuscle
      sets
      reps
      weight
      weightDescription
      restDurationSeconds
      restDurationFormatted
      orderIndex
      rangeOfMotion
      howTo
      purpose
    }
  }
}
```

---

## myRoutines

내 루틴 목록을 조회합니다.

**인증 필요**: ✅

```graphql
query MyRoutines($limit: Int, $completedOnly: Boolean) {
  myRoutines(limit: $limit, completedOnly: $completedOnly) {
    id
    name
    level
    weekNumber
    dayNumber
    isCompleted
    createdAt
  }
}
```

**Parameters**

| 이름 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `limit` | `Int` | `10` | 조회 개수 (최대 100) |
| `completedOnly` | `Boolean` | `false` | 완료된 루틴만 조회 |

---

## mySessions

내 운동 세션 기록을 조회합니다.

**인증 필요**: ✅

```graphql
query MySessions($limit: Int, $includeSets: Boolean) {
  mySessions(limit: $limit, includeSets: $includeSets) {
    id
    name
    startTime
    endTime
    notes
    active
    completed
    durationInSeconds
    durationFormatted
    totalSets
    totalVolume
    exercisesPerformed
    workoutSets {
      id
      exerciseName
      weight
      weightUnit
      reps
      durationSeconds
      notes
      volume
    }
  }
}
```

**Parameters**

| 이름 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `limit` | `Int` | `10` | 조회 개수 (최대 100) |
| `includeSets` | `Boolean` | `true` | 세트 정보 포함 여부 |

---

## getUserLevelAssessment

사용자 레벨 평가 정보를 조회합니다.

**인증 필요**: ✅

```graphql
query GetUserLevelAssessment {
  getUserLevelAssessment {
    userId
    level
    fitnessFactors
    maxLifts
    assessedAt
    validUntil
  }
}
```

---

## getUserConditionLogs

최근 컨디션 로그를 조회합니다.

**인증 필요**: ✅

```graphql
query GetUserConditionLogs($days: Int) {
  getUserConditionLogs(days: $days) {
    date
    energyLevel
    stressLevel
    sleepQuality
    motivation
    soreness
    availableTime
  }
}
```

**Parameters**

| 이름 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `days` | `Int` | `7` | 조회할 일수 |

---

## getWorkoutAnalytics

운동 통계를 조회합니다.

**인증 필요**: ✅

```graphql
query GetWorkoutAnalytics($days: Int) {
  getWorkoutAnalytics(days: $days) {
    totalWorkouts
    totalTime
    averageRpe
    completionRate
    workoutFrequency
    muscleGroupDistribution
    progressionTrends
  }
}
```

**Parameters**

| 이름 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `days` | `Int` | `30` | 분석 기간 (일) |

**Response Fields**

| 필드 | 타입 | 설명 |
|------|------|------|
| `totalWorkouts` | `Int` | 총 운동 횟수 |
| `totalTime` | `Int` | 총 운동 시간 (분) |
| `averageRpe` | `Float` | 평균 RPE |
| `completionRate` | `Float` | 완료율 (0-1) |
| `workoutFrequency` | `Float` | 주당 운동 빈도 |
| `muscleGroupDistribution` | `JSON` | 근육군별 운동 비율 |
| `progressionTrends` | `JSON` | 진행 추이 |

---

## checkLevelTestEligibility

승급 시험 자격을 확인합니다.

**인증 필요**: ✅

```graphql
query CheckLevelTestEligibility {
  checkLevelTestEligibility {
    eligible
    reason
    nextEligibleDate
    workoutsCompleted
    workoutsRequired
  }
}
```

**Response Fields**

| 필드 | 타입 | 설명 |
|------|------|------|
| `eligible` | `Boolean` | 시험 자격 여부 |
| `reason` | `String` | 자격/비자격 사유 |
| `nextEligibleDate` | `String` | 다음 자격 예상일 |
| `workoutsCompleted` | `Int` | 완료한 운동 수 |
| `workoutsRequired` | `Int` | 필요한 운동 수 |

---

# Types

## User
```graphql
type User {
  id: ID!
  email: String!
  name: String!
  createdAt: String!
  updatedAt: String!
  userProfile: UserProfile
  workoutSessions(limit: Int = 10): [WorkoutSession!]!
  workoutRoutines(limit: Int = 10): [WorkoutRoutine!]!
  currentWorkoutSession: WorkoutSession
  hasActiveWorkout: Boolean!
  totalWorkoutSessions: Int!
}
```

## UserProfile
```graphql
type UserProfile {
  id: ID!
  height: Float              # 키 (cm)
  weight: Float              # 몸무게 (kg)
  bodyFatPercentage: Float   # 체지방률 (%)
  currentLevel: String       # beginner, intermediate, advanced
  weekNumber: Int!           # 현재 주차
  dayNumber: Int!            # 현재 일차 (1-7)
  fitnessGoal: String        # 운동 목표
  programStartDate: String   # 프로그램 시작일 (ISO8601)
  # Computed fields
  bmi: Float                 # BMI 지수
  bmiCategory: String!       # Underweight, Normal, Overweight, Obese
  daysSinceStart: Int!       # 프로그램 시작 후 경과일
}
```

## WorkoutSession
```graphql
type WorkoutSession {
  id: ID!
  name: String
  startTime: ISO8601DateTime!
  endTime: ISO8601DateTime
  notes: String
  workoutSets: [WorkoutSet!]!
  # Computed fields
  active: Boolean!           # 활성 세션 여부
  completed: Boolean!        # 완료 여부
  durationInSeconds: Int     # 운동 시간 (초)
  durationFormatted: String  # 포맷된 시간 (예: "1h 30m")
  totalSets: Int!            # 총 세트 수
  exercisesPerformed: [String!]!  # 수행한 운동 목록
  totalVolume: Float!        # 총 볼륨
}
```

## WorkoutSet
```graphql
type WorkoutSet {
  id: ID!
  exerciseName: String!
  weight: Float
  weightUnit: String!        # kg 또는 lbs
  reps: Int
  durationSeconds: Int       # 시간 기반 운동용 (플랭크 등)
  notes: String
  # Computed fields
  volume: Float!             # 무게 × 반복수
  isTimedExercise: Boolean!  # 시간 기반 운동 여부
  isWeightedExercise: Boolean! # 중량 운동 여부
  durationFormatted: String  # 포맷된 시간
  weightInKg: Float          # kg 단위 무게
  weightInLbs: Float         # lbs 단위 무게
}
```

## WorkoutRoutine
```graphql
type WorkoutRoutine {
  id: ID!
  name: String
  level: String!
  weekNumber: Int!
  dayNumber: Int!
  dayOfWeek: String
  isCompleted: Boolean!
  exercises: [RoutineExercise!]
}
```

## RoutineExercise
```graphql
type RoutineExercise {
  id: ID!
  exerciseName: String!
  targetMuscle: String!
  orderIndex: Int!
  sets: Int!
  reps: Int!
  weight: Float
  weightDescription: String  # 무게 설명 (예: "체중의 80%")
  restDurationSeconds: Int   # 휴식 시간 (초)
  rangeOfMotion: String
  howTo: String
  purpose: String
  bpm: Int                   # 유산소 운동용 BPM
  # Computed fields
  estimatedExerciseDuration: Int  # 예상 운동 시간 (초)
  restDurationFormatted: String   # 포맷된 휴식 시간
  isCardio: Boolean!
  isStrength: Boolean!
  exerciseSummary: String
  targetMuscleGroup: String
}
```

---

# Enums

## TrainingLevel
| 값 | 설명 |
|-----|------|
| `BEGINNER` | 초급 |
| `INTERMEDIATE` | 중급 |
| `ADVANCED` | 고급 |

## CompletionStatus
| 값 | 설명 |
|-----|------|
| `COMPLETED` | 완료 |
| `PARTIAL` | 부분 완료 |
| `SKIPPED` | 건너뜀 |

## FeedbackType
| 값 | 설명 |
|-----|------|
| `DIFFICULTY` | 난이도 관련 |
| `EFFECTIVENESS` | 효과 관련 |
| `ENJOYMENT` | 만족도 관련 |
| `TIME` | 시간 관련 |
| `OTHER` | 기타 |

---

# 에러 처리

## 인증 에러

토큰이 없거나 유효하지 않은 경우:

```json
{
  "errors": [{
    "message": "Authentication required",
    "extensions": { "code": "UNAUTHENTICATED" }
  }]
}
```

## CRUD Mutation 에러

validation 실패 등:

```json
{
  "data": {
    "updateProfile": {
      "user": null,
      "errors": ["Email has already been taken"]
    }
  }
}
```

## AI Mutation 에러

AI 서비스 오류 등:

```json
{
  "data": {
    "generateAiRoutine": {
      "success": false,
      "routine": null,
      "error": "AI service unavailable"
    }
  }
}
```

---

# 환경 설정

## 필수 환경 변수

```bash
APPLE_CLIENT_ID=com.tskim.workoutlog
ANTHROPIC_API_KEY=sk-ant-...  # AI 기능용
SECRET_KEY_BASE=...           # JWT 서명용
```

## 개발 서버 실행

```bash
bundle install
rails db:migrate
rails server
# http://localhost:3000/graphql
```
