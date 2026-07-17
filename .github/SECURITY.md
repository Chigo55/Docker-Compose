# 보안 정책

## 취약점 신고

**공개 이슈로 신고하지 마세요.** 공개 이슈는 신고와 동시에 내용이 전 세계에 드러납니다.

이 저장소는 GitHub 의 **private vulnerability reporting** 을 켜 두었습니다. 비공개로 신고하고, 논의하고, 패치가 배포된 뒤에 공개합니다.

- 경로: 저장소 상단 **Security** 탭 → **Report a vulnerability**
- 바로가기: <https://github.com/Chigo55/Docker-Compose/security/advisories/new>

신고에 담아 주시면 좋은 것: 영향받는 스크립트/파일, 재현 절차, PowerShell·Docker Desktop 버전, 예상되는 피해 범위.

개인이 유지하는 프로젝트라 상시 대응은 어렵습니다. 보통 **7일 이내에 첫 응답**을 드리고, 이후 진행 상황은 해당 advisory 안에서 공유합니다.

## 지원 버전

최신 마이너 버전만 패치합니다. 이전 태그로 백포트하지 않으니, 신고 전에 최신 릴리스에서도 재현되는지 확인해 주세요.

| 버전 | 지원 |
|------|------|
| 1.1.x (최신) | ✅ |
| 그 이전 | ❌ |

## 신고 전에 — 이 저장소의 의도된 설계

아래는 **취약점이 아니라 문서화된 설계 결정**입니다. 신고해 주셔도 "의도된 동작"으로 닫히게 됩니다.

**`compose/.env` 의 평문 SA 비밀번호** — `.env` 가 유일한 설정 소스이고([ADR-0001](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/adr/0001-env-single-source-of-truth.md)), SQL Server 컨테이너는 기동 시 환경변수로 비밀번호를 받아야 합니다. 이 규모에서 Vault 도입은 과하다고 판단해 평문을 택했고, 대신 **실값이 든 `compose/.env` 는 `.gitignore` 로 제외**하고 값을 비운 `compose/.env.example` 만 공유합니다([ADR-0013](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/adr/0013-plaintext-password-gitignored.md)). 저장소에서 보이는 비밀번호 자리는 전부 견본입니다. 비밀번호가 호스트 파일시스템에 평문으로 남는 것은 이 결정이 감수하는 부분이며, 파일시스템 접근 통제를 전제합니다.

**SA 계정 사용** — `mcr.microsoft.com/mssql/server` 이미지의 기본 부트스트랩 경로입니다.

**`sqlcmd -C`(인증서 신뢰)** — 컨테이너의 자체 서명 인증서를 신뢰하기 위한 로컬 전제입니다([ADR-0006](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/adr/0006-sqlcmd-version-autodetect.md)).

**포트를 호스트에 바인딩하는 것** — 로컬 개발 도구에서 붙기 위한 목적입니다.

## 범위

이 저장소는 **로컬 개발 환경용 템플릿**이며, 인터넷에 노출된 운영 환경을 전제하지 않습니다. 방화벽 뒤 개발 PC 에서 Docker Desktop 으로 돌리는 상황을 가정합니다.

**범위 안**

- 관리 스크립트가 비밀번호를 의도치 않게 노출하는 경로(로그·에러 메시지·명령행 인자·HTML 리포트 등)
- 스크립트 인자 처리 결함(예: `-Database`/경로 인자를 통한 T-SQL·명령 인젝션)
- 커밋된 파일에 실제 비밀 값이 들어간 경우
- GitHub Actions 워크플로의 권한·시크릿 취급 문제
- 데이터 손실로 이어지는 파괴적 동작의 안전장치 누락

**범위 밖**

- 위의 "의도된 설계" 항목
- SQL Server 이미지 자체의 취약점 → [Microsoft 에 신고](https://msrc.microsoft.com/report)해 주세요
- Docker Desktop·PowerShell 등 전제 플랫폼의 취약점 → 각 벤더로
- 호스트에 이미 셸/파일시스템 접근 권한이 있어야 성립하는 시나리오(비밀번호·데이터가 그 아래 있다는 것이 전제입니다)

## 이미 갖춰진 방어

- **secret scanning** + **push protection** 활성화 — 실수로 실값 `.env` 나 비밀번호를 커밋하면 push 단계에서 차단됩니다. 평문 `.env` 설계의 실질적 방어막입니다.
- **Dependabot** — `.github/workflows/*` 의 액션 버전을 추적합니다.
