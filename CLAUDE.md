# RepStack Backend - Claude Code 규칙

## 🎯 제품 비전: 살아있는 운동 시스템

RepStack은 **평생 건강 파트너**를 목표로 하는 AI 기반 운동 시스템입니다.

### 핵심 구조

```
        ┌─────────────────────────────────────┐
        │      다주차 주기화 프로그램           │
        │   (4주 근비대 → 2주 디로드 → ...)    │
        └──────────────┬──────────────────────┘
                       ↓
              ┌───────────────┐
              │   오늘의 루틴   │
              └───────┬───────┘
                      ↓
    ┌────────────────────────────────────┐
    │  🔄 일일 선순환 사이클              │
    │                                    │
    │   컨디션 체크 → 운동 수행 → 기록    │
    │        ↑                   ↓       │
    │        └──── 루틴 평가 ←───┘       │
    └────────────────────────────────────┘
                      ↓
              피드백 반영 & 학습
                      ↓
              루틴 정교화
                      ↓
              ┌───────────────┐
              │   다음 주기    │  ← 나선형 상승
              └───────────────┘
```

### 레벨별 출발점은 다르지만, 같은 나선형 구조

| 초급 | 중급 | 고급 |
|------|------|------|
| 기본 동작 학습 | 분할 훈련 | 고급 테크닉 |
| 전신 운동 (주 3회) | 상하체 분할 (주 4회) | PPL 분할 (주 5-6회) |

모든 레벨이 **같은 선순환 구조**를 타며 계속 상승합니다.

### 핵심 철학

- **건강 = 끝없는 여정**: 달성하고 끝나는 게 아니라 평생 유지하며 추구하는 가치
- **살아있는 루틴**: 사용자와 함께 진화하는 운동 프로그램
- **나선형 성장**: 초/중/고급 모두 같은 구조로 계속 발전

### 확장 기능 (로드맵)

**📸 음식 사진 → 영양 분석**
- 사용자가 먹은 음식 사진 촬영
- AI가 음식 인식 & 영양성분 분석
- 일일 섭취량 자동 기록 (칼로리, 단백질, 탄수화물, 지방)
- 운동 목표(벌크업/컷팅/유지)에 맞는 영양 피드백

```
운동 루틴 ←→ 영양 섭취
    ↓           ↓
    └─── 통합 피드백 ───┘
              ↓
        목표 달성 최적화
```

### 지식 기반: YouTube 피트니스 지식

AI Trainer가 좋은 루틴을 생성하려면 단단한 지식 기반이 필요합니다.

**파이프라인**: YouTube 영상 → STT (Whisper) → Analysis (Claude) → Embedding (OpenAI)

**지식 유형**:
- `exercise_technique`: 운동 테크닉
- `form_check`: 자세 교정
- `nutrition_recovery`: 영양/회복
- `routine_design`: 프로그램 설계

### 관련 코드

- `lib/ai_trainer/routine_generator.rb` - 고정 프로그램 기반 루틴
- `lib/ai_trainer/creative_routine_generator.rb` - RAG + LLM 창의적 루틴
- `lib/ai_trainer/tool_based_routine_generator.rb` - Tool Use 기반 루틴
- `app/services/rag_search_service.rb` - 지식 검색
- `app/models/fitness_knowledge_chunk.rb` - 지식 청크

---

## 필수 작업

### GraphQL 스키마 수정 시
GraphQL 타입, Mutation, Query 등을 수정한 후 **반드시**:

```bash
# 1. 스키마 검증 (DB와 일치 확인)
bundle exec rails graphql:schema:validate

# 2. 배포 후 문서 재생성
npm run docs:build
```

### 스키마 검증 명령어
```bash
# GraphQL-DB 일치 검증
bundle exec rails graphql:schema:validate

# 전체 검사 (검증 + 덤프 + 문서생성)
bundle exec rails graphql:schema:full_check
```

검증이 실패하면 `app/services/schema_validator.rb`의 설정을 확인하세요.

### 배포
코드 수정 후 Railway 배포 필요 시:
```bash
railway up
```

## 프로젝트 구조

- `app/graphql/` - GraphQL 스키마 정의 (Source of Truth)
- `schema.graphql` - 스키마 덤프 파일
- `docs/api/` - 자동 생성 API 문서
- `spectaql.yml` - 문서 생성 설정

## 주의사항

- API 문서는 수동으로 수정하지 않음 (자동 생성됨)
- GraphQL 스키마가 모든 것의 기준
