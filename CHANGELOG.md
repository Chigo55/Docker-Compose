# Changelog

이 파일은 이 저장소의 주목할 만한 변경을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를, 버전은
[유의적 버전(SemVer)](https://semver.org/lang/ko/)을 따릅니다.

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

[1.1.0]: https://github.com/Chigo55/Docker-Compose/releases/tag/v1.1.0
[1.0]: https://github.com/Chigo55/Docker-Compose/releases/tag/v1.0
