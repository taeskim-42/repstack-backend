# RepStack Backend - Claude Code 규칙

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
