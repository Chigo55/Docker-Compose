# MSSQL Farm (Docker Compose)

SQL Server 2019 / 2022 인스턴스 여러 개를 Docker Compose로 운영하기 위한 템플릿입니다. (아래 예시는 2019 3개 + 2022 5개)
**설정값은 전부 `compose/.env`에 있고, `compose/compose.yml`은 구조만 정의합니다.**
관리 작업은 `scripts/` 폴더의 PowerShell 스크립트로 합니다.

> 이 저장소는 Windows + PowerShell 5.1 이상 + Docker Desktop 환경을 전제로 합니다.

> **Docker나 SQL Server가 처음이라면** 이 문서(옵션 레퍼런스) 대신 [Wiki 의 학습 로드맵](https://github.com/Chigo55/Docker-Compose/wiki/학습-로드맵)부터 보세요.
> 개념 → 이 저장소의 어디에 나타나는가 → 직접 확인할 명령 순서로 정리해 두었습니다.

---

## 폴더 구조

```
mssql-farm/
├─ scripts/                  관리 스크립트 (여기서 실행 — 사용법은 docs/scripts/)
│  ├─ lib/
│  │  ├─ _common.ps1         공통 함수 모음 (ops, 직접 실행하지 않음)
│  │  └─ _devtools.ps1       개발 루프 전용 헬퍼 (직접 실행하지 않음)
│  └─ *.ps1                  스크립트 하나 = 명령 하나 (start/backup/doctor/...)
├─ tests/
│  └─ _common.Tests.ps1     [개발] _common.ps1 자동 발견/파싱 단위 테스트
├─ compose/
│  ├─ compose.yml           컨테이너 "구조" 정의 (설정값 없음)
│  ├─ .env                  모든 "설정값" — 여기만 고치면 됩니다 (Git 제외)
│  └─ .env.example          .env 의 견본 (비밀번호 비움, 팀 공유용)
├─ docs/
│  ├─ README.md             이 문서 (입구 · 설정 레퍼런스)
│  └─ scripts/              스크립트별 사용법 (스크립트 하나당 파일 하나)
├─ .github/                 CI 워크플로 · 이슈/PR 템플릿 · dependabot
├─ .claude/                 설계 문서 (adr/ · rules/ · CONVENTIONS.md)
├─ .gitignore
└─ CLAUDE.md                AI 어시스턴트(Claude Code)용 저장소 가이드
```

> **왜 이렇게 나눴나요?** 실행하는 것(scripts), 설정하는 것(compose), 읽는 것(docs)을
> 폴더로 분리해 두면, 무엇을 어디서 만져야 하는지 헷갈리지 않습니다.
> 스크립트는 항상 저장소 맨 위 폴더에서 `\.scripts\...` 형태로 실행합니다.

---

## 구성 (예시)

| 인스턴스 | 버전 | 포트 | 데이터 디렉터리 |
|---|---|---|---|
| Db2019A | 2019 | 40000 | `<DATA_ROOT>/Db2019A/data` |
| Db2019B | 2019 | 40100 | `<DATA_ROOT>/Db2019B/data` |
| Db2019C | 2019 | 40200 | `<DATA_ROOT>/Db2019C/data` |
| Db2022A | 2022 | 41000 | `<DATA_ROOT>/Db2022A/data` |
| Db2022B | 2022 | 41100 | `<DATA_ROOT>/Db2022B/data` |
| Db2022C | 2022 | 41200 | `<DATA_ROOT>/Db2022C/data` |
| Db2022D | 2022 | 41300 | `<DATA_ROOT>/Db2022D/data` |
| Db2022E | 2022 | 41400 | `<DATA_ROOT>/Db2022E/data` |

> 인스턴스 이름/개수/포트는 예시입니다. `compose/.env`에서 실제 환경에 맞게 바꾸세요.
> 기존 데이터를 옮겨 붙일 때는 컨테이너 이름(`_NAME`)과 폴더 이름(`_DIR`)이 다를 수 있습니다. 그럴 땐 임의로 통일하지 마세요.

접속: `localhost,<포트>` / 계정 `sa` / 비밀번호는 `compose/.env`의 `MSSQL_SA_PASSWORD`

---

## 시작하기

```powershell
# 0) (최초 1회) 견본을 복사해 .env 를 만들고 비밀번호를 채웁니다.
Copy-Item .\compose\.env.example .\compose\.env
#    → .env 를 열어 MSSQL_SA_PASSWORD 와 DATA_ROOT, 인스턴스 목록을 확인/수정

# 1) 기동 (이미지 최신본 받고 시작)
.\scripts\start.ps1 -Pull

# 2) 상태 확인 (healthy 까지 30~60초)
.\scripts\status.ps1
```

---

## 스크립트 사용법

**스크립트별 사용법은 [`docs/scripts/`](scripts/) 에 파일 하나씩** 있습니다 —
`scripts\<name>.ps1` 의 사용법은 `docs/scripts/<name>.md` 이고, 옵션·동작·주의사항의 단일 소스입니다.
폴더를 열면 파일 목록이 보이고, 각 문서를 열면 맨 위 요약(frontmatter)이 표로 렌더링됩니다.

목록 표는 **저장소에 커밋하지 않습니다.** 스크립트를 추가하는 PR 마다 같은 표에 행을 append 하다
충돌하던 문제를 없애기 위해서입니다([ADR-0022](../.claude/adr/0022-per-script-docs.md) ·
[ADR-0021](../.claude/adr/0021-generated-doc-index.md)). 요약이 붙은 전체 목록은 필요할 때 생성기로 뽑아 봅니다.

```powershell
.\scripts\gen-docs-index.ps1                       # ADR·rules·scripts 목록을 화면에 출력
.\scripts\gen-docs-index.ps1 -Out docs\_generated  # 파일로 저장(gitignored)
```

공통 규칙은 이렇습니다.

- 모든 스크립트는 저장소 맨 위 폴더에서 실행합니다. 각 스크립트는 `.env`를 스캔해 인스턴스 목록을
  자동으로 알아내므로, 인스턴스가 늘어도 스크립트는 고치지 않습니다.
- 대부분의 스크립트는 `-Service <서비스키>`로 일부만 대상으로 삼을 수 있습니다. 서비스키는 `.env`
  접두사의 소문자입니다(예: `DB2019C_*` → `db2019c`). 오타를 내면 사용 가능한 목록과 함께 알려 주고 멈춥니다.
- 배치 성격의 스크립트는 하나가 실패해도 나머지를 계속 진행하고, 요약 표를 낸 뒤 실패가 있으면
  **종료 코드 1**을 반환합니다(스케줄러 감지용).

---

## 내부 개발 루프 (저장소를 고칠 때)

운영이 아니라 **스크립트나 `compose` 설정을 편집할 때** 쓰는 로컬 검증 루프입니다. 실사용 운영에는 필요 없습니다.

```powershell
.\scripts\check.ps1 -Test           # 린트 + doctor + 문서 인덱스 검증 + Pester (커밋 전 게이트)
.\scripts\check.ps1 -Watch -Test    # 파일 저장 때마다 전체 루프 자동 재실행
```

단계별 설명·옵션·개발 모듈(PSScriptAnalyzer/Pester) 부트스트랩은 [check.ps1 문서](scripts/check.md)에,
테스트 범위는 [test.ps1 문서](scripts/test.md)에 있습니다. 오류가 하나라도 있으면 **종료 코드 1**을
반환합니다(CI/자동화 감지용).

> **설계 문서** — 왜 이렇게 만들었는지(ADR)·편집 규칙(RULES)·코드 규약(CONVENTIONS)은 `.claude/` 폴더에 정리되어 있습니다. 스크립트를 새로 추가하거나 고치기 전에 참고하세요.
>
> **기여 흐름** — 변경은 worktree 에서 만들고 PR 로 병합합니다. main 은 Ruleset 으로 보호되어 **직접 push 가 거부**되고, GitHub Actions CI(`.github/workflows/ci.yml`)가 **필수 상태 체크**라 통과해야 병합할 수 있습니다. 자세한 흐름은 [.claude/rules/workflow.md](../.claude/rules/workflow.md), 원격에 켜져 있는 GitHub 기능 전체(Actions 권한·dependabot·Security 등)는 [.claude/rules/github.md](../.claude/rules/github.md) 참고.

---

## `compose/.env` 레퍼런스

| 그룹 | 변수 | 설명 |
|---|---|---|
| 프로젝트 | `COMPOSE_PROJECT_NAME`, `NETWORK_NAME`, `NETWORK_DRIVER` | compose 프로젝트/네트워크 |
| 이미지 | `MSSQL_REPO`, `MSSQL_2019_TAG`, `MSSQL_2022_TAG` | 이미지 저장소와 태그 |
| 헬스체크 경로 | `MSSQL_2019_SQLCMD`, `MSSQL_2022_SQLCMD` | 버전별 sqlcmd 경로 |
| SQL Server | `ACCEPT_EULA`, `MSSQL_SA_PASSWORD`, `MSSQL_PID`, `TZ`, `MSSQL_PORT` | 공통 런타임 환경변수 |
| 컨테이너 | `RESTART_POLICY`, `STOP_GRACE_PERIOD` | 재시작 정책, 종료 대기 시간 |
| 헬스체크 | `HEALTHCHECK_INTERVAL`, `_TIMEOUT`, `_RETRIES`, `_START_PERIOD` | 헬스체크 주기 |
| 로그 | `LOG_MAX_SIZE`, `LOG_MAX_FILE` | json-file 로그 로테이션 |
| 백업 | `BACKUP_DATABASE`, `BACKUP_ROOT`, `BACKUP_RETENTION_DAYS`, `BACKUP_STAGING_DIR` | 백업 대상 DB / 저장 위치 / 보관 기간 |
| 데이터 | `DATA_ROOT` | 데이터 루트 (Windows도 슬래시 `/` 사용) |
| 인스턴스별 | `<PREFIX>_NAME`, `_PORT`, `_DIR` | 컨테이너명 / 호스트 포트 / 데이터 폴더 |

선택 항목(`MSSQL_MEMORY_LIMIT_MB`, `MSSQL_AGENT_ENABLED`)은 주석 처리되어 있습니다. 쓰려면 `compose/.env`와 `compose/compose.yml`의 대응 줄을 **둘 다** 해제하세요. 빈 값으로 넘어가면 SQL Server가 기동에 실패할 수 있습니다. 에러로그·인증서를 호스트에 보존하는 `MOUNT_LOG_SECRETS`도 같은 '양쪽 함께 켜기' 항목입니다(위 운영 메모의 마운트 범위 참고).

`.env` 값에 `$`가 포함되면 `$$`로 이스케이프해야 하고, 설명은 값 옆이 아니라 윗줄에 답니다.

---

## 인스턴스 추가하기

1. `compose/.env`에 3줄 추가

```
DB2022F_NAME=Db2022F
DB2022F_PORT=41500
DB2022F_DIR=Db2022F
```

2. `compose/compose.yml`에 서비스 블록 추가 (서비스 키 = prefix 소문자)

```yaml
  db2022f:
    <<: *mssql2022
    container_name: ${DB2022F_NAME}
    hostname: ${DB2022F_NAME}
    ports: ["${DB2022F_PORT}:${MSSQL_PORT:-1433}"]
    volumes: ["${DATA_ROOT}/${DB2022F_DIR}/data:/var/opt/mssql/data"]
```

3. `.\scripts\start.ps1` — 스크립트는 `.env`를 스캔하므로 수정할 필요가 없습니다.

---

## 운영 메모

**설정 최종 확인** — 적용 전에 `.env`가 실제로 어떻게 반영되는지 볼 수 있습니다. `compose.yml`과 `.env`가 같은 `compose/` 폴더 안에 있으므로, 그 폴더로 이동해 실행하면 됩니다.

```powershell
Push-Location .\compose
docker compose config          # 렌더링 결과 확인
Pop-Location
```

**컨테이너 간 통신** — 모두 같은 네트워크(`NETWORK_NAME`)에 있어, 컨테이너 안에서는 `<hostname>,1433`으로 서로 접근할 수 있습니다. 호스트에서는 매핑된 포트를 씁니다.

**메모리** — 인스턴스가 여러 개 상시 기동되면 각자 가용 메모리를 최대한 확보하려 합니다. 호스트 메모리가 넉넉하지 않다면 `MSSQL_MEMORY_LIMIT_MB`를 켜는 것을 권합니다.

**백업** — `.\scripts\backup.ps1`을 쓰세요. 데이터 파일(`.mdf`)을 직접 복사하면 실행 중 인스턴스에서는 손상된 사본이 나옵니다.

**마운트 범위** — 기본은 `/var/opt/mssql/data`만 마운트하므로 에러로그(`/var/opt/mssql/log`)·인증서(`/var/opt/mssql/secrets`)는 컨테이너와 함께 사라집니다. 보존하려면 `compose/.env`의 `MOUNT_LOG_SECRETS=true`와 `compose/compose.yml` 각 서비스 `volumes`의 log/secrets 마운트 2줄 주석을 **함께** 해제하세요. 그러면 `start.ps1`이 `<DATA_ROOT>/<_DIR>/log`·`secrets` 폴더를 만들어 호스트에 보존합니다.

**비밀번호** — `compose/.env`에 평문으로 들어갑니다. 실제 값이 든 `.env`는 `.gitignore`로 제외되어 있고, 팀에는 `compose/.env.example`만 공유합니다.

---

## 문제 해결

**healthy로 안 바뀜** — 이미지가 업데이트되며 sqlcmd 경로가 바뀌었을 수 있습니다. 확인 후 `compose/.env`의 `MSSQL_2019_SQLCMD` / `MSSQL_2022_SQLCMD`를 고치세요.

```powershell
docker exec Db2019C ls /opt/mssql-tools*/bin/
```

**기동 직후 컨테이너가 죽음** — 대부분 SA 비밀번호 정책 위반(8자 이상 + 대문자/소문자/숫자/기호 중 3종) 또는 데이터 폴더 권한 문제입니다.

```powershell
.\scripts\logs.ps1 <service> -Tail 50
```

**포트 충돌** — `netstat -ano | findstr :40000`으로 점유 프로세스를 확인하고, `compose/.env`에서 포트를 바꾼 뒤 `.\scripts\restart.ps1 -Recreate`를 실행하세요.

---

## 향후 계획

대화형 셸(`shell.ps1`)·차등/로그 백업(`backup.ps1 -Type`)·비밀번호 회전(`rotate-password.ps1`)·인스턴스 간 복제(`copy-db.ps1`)·farm 리포트(`report.ps1`)·DB 인벤토리(`databases.ps1`)·이미지 롤링 업데이트(`update.ps1`)는 이미 구현되어 [docs/scripts/](scripts/) 에 정리했습니다.
남은 계획의 단일 소스는 [GitHub Project](https://github.com/users/Chigo55/projects/4)와 `roadmap` 라벨 이슈입니다. 단위 테스트·린트·GitHub Actions CI 는 위의 [내부 개발 루프](#내부-개발-루프-저장소를-고칠-때)와 `.github/workflows/ci.yml` 로 이미 갖췄습니다.

---

## 보안

취약점을 발견하면 **공개 이슈가 아니라** [Security 탭의 비공개 신고](https://github.com/Chigo55/Docker-Compose/security/advisories/new)로 알려주세요. 신고 범위와 이 저장소의 의도된 설계(평문 `.env` 등 — 오신고가 잦은 부분)는 [SECURITY.md](../.github/SECURITY.md)에 정리해 두었습니다.

---

## 라이선스

[MIT License](../LICENSE) © 2026 정인호 (Inho Jeong)

> 공개 시 주의: 실제 값이 든 `compose/.env`(SA 비밀번호 포함)는 `.gitignore`로 제외되어 커밋되지 않습니다. 저장소를 공개하기 전에 `git log`/현재 트리에 `.env`나 `.bak` 등 민감 파일이 들어가 있지 않은지 반드시 확인하세요.
