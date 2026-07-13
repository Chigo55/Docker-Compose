# ADR-0013: 평문 비밀번호 `.env`는 Git 에서 제외하고, 견본만 공유한다

- 상태: Accepted
- 관련: [ADR-0001](0001-env-single-source-of-truth.md), [ADR-0009](0009-password-via-env-var.md), `.gitignore`, `compose/.env.example`

## 배경 (Context)

`.env`가 유일한 설정 소스([ADR-0001](0001-env-single-source-of-truth.md))이므로 SA 비밀번호도 그 안에
평문으로 있다. SQL Server 컨테이너는 기동 시 환경변수로 비밀번호를 받아야 하고, 이 팀
규모/운영 환경에서는 Vault 같은 비밀 관리 도구 도입이 과하다고 판단했다(ROADMAP 의 out-of-scope).
그러나 평문 비밀번호를 Git 에 올리면 이력에 영구 노출된다.

## 결정 (Decision)

- 실값이 든 **`compose/.env`는 `.gitignore`로 제외**한다.
- 팀에는 **값을 비운 `compose/.env.example`만 커밋/공유**한다. 사용자는 이를 `.env`로 복사해 값을 채운다.
- 백업 산출물(`*.bak`, `_backup/`)도 `.gitignore`로 제외한다(BACKUP_ROOT 가 저장소 안일 경우 대비).
- 공개/미러링 전에는 Git 이력에 `.env`/`.bak`이 없는지 확인한다.

## 결과 (Consequences)

- **좋은 점**: 저장소를 공개해도 비밀번호가 노출되지 않는다.
- **좋은 점**: `.env.example`이 필요한 키의 스키마 역할도 겸해, 신규 세팅이 쉽다.
- **감수할 점**: 비밀번호는 여전히 호스트에 평문으로 존재한다 — 파일시스템 접근 통제가 전제다.
- **감수할 점**: `.env`가 Git 밖이라, 인스턴스 추가 같은 설정 변경은 팀원 간 수동 전파가 필요하다.
