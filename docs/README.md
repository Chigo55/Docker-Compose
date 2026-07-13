# MSSQL Farm (Docker Compose)

SQL Server 2019 / 2022 인스턴스 여러 개를 Docker Compose로 운영하기 위한 템플릿입니다. (아래 예시는 2019 3개 + 2022 5개)
**설정값은 전부 `compose/.env`에 있고, `compose/compose.yml`은 구조만 정의합니다.**
관리 작업은 `scripts/` 폴더의 PowerShell 스크립트로 합니다.

> 이 저장소는 Windows + PowerShell 5.1 이상 + Docker Desktop 환경을 전제로 합니다.

---

## 폴더 구조

```
mssql-farm/
├─ scripts/                  관리 스크립트 (여기서 실행)
│  ├─ lib/
│  │  └─ _common.ps1         공통 함수 모음 (직접 실행하지 않음)
│  ├─ start.ps1              기동 (데이터 폴더 자동 생성)
│  ├─ stop.ps1              정지 (컨테이너 유지)
│  ├─ restart.ps1           재시작
│  ├─ status.ps1            상태 확인
│  ├─ logs.ps1              로그 조회
│  ├─ backup.ps1            전 인스턴스 DB 백업
│  └─ down.ps1              컨테이너/네트워크 제거 (데이터 보존)
├─ compose/
│  ├─ compose.yml           컨테이너 "구조" 정의 (설정값 없음)
│  ├─ .env                  모든 "설정값" — 여기만 고치면 됩니다 (Git 제외)
│  └─ .env.example          .env 의 견본 (비밀번호 비움, 팀 공유용)
├─ docs/
│  └─ README.md             이 문서
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

모든 스크립트는 저장소 맨 위 폴더에서 실행합니다. 각 스크립트는 `.env`를 스캔해
인스턴스 목록을 자동으로 알아내므로, 인스턴스가 늘어도 스크립트는 고치지 않습니다.

대부분의 스크립트는 `-Service <서비스키>`로 일부만 대상으로 삼을 수 있습니다.
서비스키는 `.env` 접두사의 소문자입니다(예: `DB2019C_*` → `db2019c`). 오타를 내면
사용 가능한 목록과 함께 알려 주고 멈춥니다.

### start.ps1 — 기동
`.env`의 `*_DIR`을 읽어 데이터 폴더를 먼저 만든 뒤 `compose up -d`를 실행합니다.
폴더가 없는 상태로 올리면 Docker가 빈 폴더를 만들어버려 기존 DB를 못 붙기 때문입니다.

```powershell
.\scripts\start.ps1                            # 전체 기동
.\scripts\start.ps1 -Pull                      # 이미지 최신본 받고 기동
.\scripts\start.ps1 -Recreate                  # 컨테이너 강제 재생성
.\scripts\start.ps1 -Service db2019c,db2022e   # 일부만
```

### status.ps1 — 상태 확인
컨테이너 상태, 헬스체크 결과, 포트 TCP 응답, 데이터 폴더 용량을 한 표로 보여줍니다.

```powershell
.\scripts\status.ps1
.\scripts\status.ps1 -Watch      # 5초마다 갱신
.\scripts\status.ps1 -NoSize     # 용량 계산 생략 (빠름)
```

### logs.ps1 — 로그
```powershell
.\scripts\logs.ps1                     # 전체, 최근 100줄
.\scripts\logs.ps1 db2019c -Follow     # 실시간 추적
.\scripts\logs.ps1 db2022b -Tail 500
.\scripts\logs.ps1 -Since 30m          # 최근 30분치
.\scripts\logs.ps1 db2022e -ErrorLog   # SQL Server 자체 errorlog
```

컨테이너 stdout 로그는 기동/에러 요약 위주입니다. 로그인 실패나 복구 상세는 `-ErrorLog`로 보세요.

### restart.ps1 — 재시작
```powershell
.\scripts\restart.ps1
.\scripts\restart.ps1 -Service db2022b
.\scripts\restart.ps1 -Recreate        # .env 변경분(포트·이미지·볼륨) 반영
```

`.env`에서 포트나 이미지 태그를 바꿨다면 `restart`만으로는 반영되지 않습니다. `-Recreate`를 쓰세요.

### stop.ps1 / down.ps1 — 정지·제거
```powershell
.\scripts\stop.ps1                     # 정지 (컨테이너 유지)
.\scripts\stop.ps1 -Service db2019c

.\scripts\down.ps1                     # 컨테이너 + 네트워크 제거 (확인 프롬프트)
.\scripts\down.ps1 -Force
.\scripts\down.ps1 -RemoveImages       # 이미지까지 삭제
```

데이터는 호스트 바인드 마운트(`DATA_ROOT`)에 있어 `down`으로도 삭제되지 않습니다. `start.ps1`로 다시 올리면 기존 DB에 그대로 붙습니다.

`restart: always` 정책이지만, 수동으로 `stop`한 컨테이너는 Docker가 다시 켜지 않습니다. Docker Desktop을 재시작하면 실행 중이던 컨테이너만 자동 복귀합니다.

### backup.ps1 — 백업

모든 인스턴스에 **같은 이름의 DB**가 있다는 전제로, 각 컨테이너 안에서 `BACKUP DATABASE`를 실행한 뒤 `.bak` 파일을 호스트로 꺼내옵니다.

```powershell
.\scripts\backup.ps1 -Database MyDb             # DB 이름 지정
.\scripts\backup.ps1                             # .env 의 BACKUP_DATABASE 사용
.\scripts\backup.ps1 -Service db2019c,db2022e    # 일부 인스턴스만
.\scripts\backup.ps1 -Verify                     # 백업 직후 RESTORE VERIFYONLY 검증
.\scripts\backup.ps1 -CopyOnly                   # 기존 백업 체인에 영향 없이
.\scripts\backup.ps1 -RetentionDays 0            # 오래된 백업 자동 삭제 끄기
```

저장 위치:

```
<BACKUP_ROOT>\<컨테이너명>\<DB>_<yyyyMMdd_HHmmss>.bak
```

동작 순서는 인스턴스마다 이렇습니다.

1. 컨테이너 실행 여부 + DB 존재/ONLINE 상태 확인
2. 컨테이너 내부 `BACKUP_STAGING_DIR`에 백업 (`COMPRESSION, CHECKSUM, INIT`)
3. `-Verify` 지정 시 `RESTORE VERIFYONLY`
4. `docker cp`로 호스트에 복사 후 컨테이너 내부 임시 파일 삭제
5. `BACKUP_RETENTION_DAYS`보다 오래된 `.bak` 정리

한 인스턴스가 실패해도 나머지는 계속 진행하고, 마지막에 요약 표를 보여줍니다. 실패가 있으면 종료 코드 1을 반환하므로 스케줄러에서 성공 여부를 감지할 수 있습니다.

**데이터 파일(`.mdf`)을 직접 복사하지 마세요.** 실행 중인 인스턴스의 파일을 복사하면 손상된 사본이 나옵니다. 이 스크립트가 안전한 이유는 SQL Server 엔진에게 백업을 시키기 때문입니다.

**복원**은 `.bak`을 컨테이너에 넣고 `RESTORE DATABASE`를 실행합니다.

```powershell
docker cp "C:\docker\_backup\Db2019C\MyDb_20260101_020000.bak" Db2019C:/var/opt/mssql/backup/restore.bak
docker exec -e "SQLCMDPASSWORD=<sa 비밀번호>" Db2019C /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -b -Q `
  "RESTORE DATABASE [MyDb] FROM DISK = N'/var/opt/mssql/backup/restore.bak' WITH REPLACE, RECOVERY;"
```

> 2022 인스턴스는 sqlcmd 경로가 `/opt/mssql-tools18/bin/sqlcmd`이고 `-C` 옵션이 필요합니다.

**야간 자동 백업** — 작업 스케줄러에 등록합니다. (경로는 실제 저장소 위치에 맞게 바꾸세요.)

```powershell
schtasks /create /tn "MSSQL Farm Backup" /sc daily /st 02:00 /rl highest `
  /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\path\to\mssql-farm\scripts\backup.ps1 -Verify"
```

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

선택 항목(`MSSQL_MEMORY_LIMIT_MB`, `MSSQL_AGENT_ENABLED`)은 주석 처리되어 있습니다. 쓰려면 `compose/.env`와 `compose/compose.yml`의 대응 줄을 **둘 다** 해제하세요. 빈 값으로 넘어가면 SQL Server가 기동에 실패할 수 있습니다.

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

**마운트 범위** — 현재 `/var/opt/mssql/data`만 마운트합니다. 에러로그(`/var/opt/mssql/log`)와 인증서(`/var/opt/mssql/secrets`)는 컨테이너와 함께 사라집니다. 보존이 필요하면 각 서비스 `volumes`에 추가하세요.

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

## 라이선스

[MIT License](../LICENSE) © 2026 정인호 (Inho Jeong)

> 공개 시 주의: 실제 값이 든 `compose/.env`(SA 비밀번호 포함)는 `.gitignore`로 제외되어 커밋되지 않습니다. 저장소를 공개하기 전에 `git log`/현재 트리에 `.env`나 `.bak` 등 민감 파일이 들어가 있지 않은지 반드시 확인하세요.
