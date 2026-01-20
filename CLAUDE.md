# RepStack Backend - Claude Code 규칙

## 필수 작업

### GraphQL 스키마 수정 시
GraphQL 타입, Mutation, Query 등을 수정한 후 **반드시** 문서 재생성:

```bash
npm run docs:build
```

이 명령어는:
1. Production 서버에서 최신 스키마 덤프 (`schema.graphql`)
2. SpectaQL로 API 문서 자동 생성 (`docs/api/index.html`)

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
