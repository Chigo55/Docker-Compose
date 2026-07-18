# Changelog

이 파일은 이 저장소의 주목할 만한 변경을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를, 버전은
[유의적 버전(SemVer)](https://semver.org/lang/ko/)을 따릅니다.

## [Unreleased]

v1.1.1 이후 병합된 변경을 모읍니다. 하위호환 기능 추가(신규 관리 스크립트 4종)가 포함되므로, 릴리스 시점에 **v1.2.0**(마이너 범프)으로 확정합니다.

### 추가 (Added)
- **`shell.ps1`** — 대상 인스턴스에 대화형 `sqlcmd` 세션을 엽니다(2019/2022 경로·`-C` 자동 판별). (#6, PR #20)
- **`report.ps1`** — farm 전체 상태를 HTML 리포트로 생성합니다. (#13)
- **`copy-db.ps1`** — 백업→복원을 이어 인스턴스 간 DB 를 복제합니다(`WITH MOVE`·대상 이름 자동). (#8)
- **`rotate-password.ps1`** — SA 비밀번호를 회전합니다(정책·금지 문자 검사). ⚠️ 실 SQL Server 환경 미검증 상태로, 실행 시 이를 고지합니다. (#10, 검증 추적 #16)
- **`backup.ps1 -NotifyWebhook`** — 백업 요약을 Teams/Slack webhook 으로 전송합니다. (#13)
- **`restore.ps1 -NotifyWebhook`** — 복원 요약(성공/실패)을 Teams/Slack webhook 으로 전송합니다. 전송 로직을 `_common.ps1` 의 공용 헬퍼 `Send-WebhookNotification` 으로 올려 `backup.ps1` 과 공유합니다. (#15)
- **Dependabot** — `github-actions` 생태계를 weekly 로 추적합니다. (#23)
- **이슈/PR 템플릿** — 버그·기능 요청 이슈 템플릿과, 저장소 고유 함정(BOM·ASCII·양쪽 켜기·3종 세트)을 담은 PR 체크리스트를 추가했습니다. (#25)
- **보안 신고 경로** — Security 탭의 비공개 취약점 신고(private vulnerability reporting)와 `.github/SECURITY.md`(지원 버전·의도된 설계 고지)를 마련했습니다. (#28)

### 변경 (Changed)
- CI: `actions/checkout@v5` → `@v7` (dependabot). (#33)
- CI: `claude-code-review.yml`·`claude.yml` 의 `permissions` 를 `write` 로 올려, 리뷰·`@claude` 응답이 조용히 폐기되던 문제를 해결했습니다. (#27, #30)
- **main 브랜치 보호를 Ruleset `main protection` 으로 강제**합니다(PR 필수·force push/삭제 금지·bypass 없음). 저장소 파일이 아닌 GitHub 설정 변경입니다. (#22)

### 수정 (Fixed)
- `doctor.ps1` 이 성공 시 명시적 `exit 0` 을 반환해 종료 코드 누수를 차단합니다(Docker 미기동으로 compose 렌더링만 건너뛰는 경로 포함). (#3, PR #19)

### 제거 (Removed)
- `docs/ROADMAP.md` — 실제와 어긋난 동결 사본이라 삭제했습니다. 로드맵의 단일 소스는 GitHub Project 입니다(원문은 `git show v1.1.1:docs/ROADMAP.md`). (ADR-0019)

### 문서 (Docs)
- worktree·PR·CI 작업 흐름과 "추적은 문서가 아니라 GitHub 으로" 원칙을 정식 문서로 승격했습니다(ADR-0015·0016, `rules/workflow.md`). (#17)
- 원격 GitHub 설정(ruleset·Actions 권한·Wiki·Security)을 `rules/github.md` 로 문서화했습니다(ADR-0017·0018). (#37)
- 최근 스크립트·옵션을 `docs/README.md`·`CLAUDE.md` 에 반영했습니다. (#18)
- `rotate-password.ps1` 미검증 상태를 실행 시점에 고지하도록 했습니다. (#34, PR #36)

## [1.1.1] - 2026-07-14

CI 워크플로 안정화 패치. 스크립트/운영 동작 변경은 없습니다.

### 수정 (Fixed)
- CI: `run:` 블록을 ASCII 전용으로 변경했습니다. GitHub 이 만드는 BOM 없는 임시 스크립트를 windows-latest 의 Windows PowerShell 5.1 이 ANSI 로 오독해, 블록 안 한글이 깨지며 파싱이 실패(`Missing closing ')'`)하던 문제를 해결했습니다.

### 변경 (Changed)
- CI: `actions/checkout@v4` → `@v5` (Node 20 지원 종료 대응).

## [1.1.0] - 2026-07-14

v1.0 이후의 하위 호환 기능 추가와 개발/CI 정비를 모읍니다. 기존 명령의 기본 동작은 그대로입니다.

### 추가 (Added)
- **`start.ps1 -Wait` / `-Timeout`** — 전 인스턴스가 healthy 가 될 때까지 폴링하며 대기합니다(무인 자동화·CI 신뢰성). 타임아웃 시 `exit 1`. `_common.ps1` 에 `Wait-Healthy`·`Get-ContainerHealth` 헬퍼 신설. (P1-1)
- **`backup.ps1 -Type Full|Diff|Log`** — 전체(`.bak`)에 더해 차등(`.dif`)·트랜잭션 로그(`.trn`) 백업을 지원합니다. 로그 백업 시 복구 모델이 SIMPLE 이면 건너뜁니다(SKIP, 실패 아님). (P2-4)
- **`restore.ps1 -Chain`** — 최신 전체→차등→로그 백업을 자동으로 이어 복원합니다(앞은 NORECOVERY, 마지막만 RECOVERY). (P2-4)
- **errorlog·secrets 볼륨 마운트 옵션** — `.env` 의 `MOUNT_LOG_SECRETS=true` 와 `compose.yml` 각 서비스 `volumes` 의 log/secrets 주석 두 줄을 함께 켜면 호스트에 보존됩니다(`start.ps1` 이 폴더 생성). (P3-8)
- **내부 개발 루프** — `check.ps1`(PSScriptAnalyzer 린트 + doctor) / `test.ps1`(Pester 5+ 단위 테스트) + `tests/`. 개발 모듈은 선택 의존성(`-Install` 부트스트랩).
- **GitHub Actions CI** — `push`(main/master)·모든 `pull_request` 마다 windows-latest + PowerShell 5.1 에서 `check.ps1 -Test -Install` 실행. (P3-9)

### 변경 (Changed)
- `status.ps1` 의 헬스 표시를 `Get-ContainerHealth` 로 통일했습니다(예: `health: starting` → `starting`).
- `backup.ps1` 의 보관 정리(`-RetentionDays`)가 `.bak`/`.dif`/`.trn` 세 유형을 함께 처리합니다(시각 기준·체인 비인식).

### 문서 (Docs)
- `.claude/` 아래 ADR·규칙(rules)·코드 규약(CONVENTIONS), `docs/ROADMAP.md` 추가/정비.

## [1.0] - 초기 릴리스

- SQL Server 2019/2022 다중 인스턴스 Docker Compose 운영 템플릿.
- 관리 스크립트: `start` / `stop` / `restart` / `down` / `status` / `logs` / `query` / `backup` / `restore` / `doctor`.
- `.env` 단일 설정 소스 + 인스턴스 자동 발견, 공용 라이브러리 `scripts/lib/_common.ps1`.

[Unreleased]: https://github.com/Chigo55/Docker-Compose/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/Chigo55/Docker-Compose/releases/tag/v1.1.1
[1.1.0]: https://github.com/Chigo55/Docker-Compose/releases/tag/v1.1.0
[1.0]: https://github.com/Chigo55/Docker-Compose/releases/tag/v1.0
