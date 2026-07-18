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
├─ scripts/                  관리 스크립트 (여기서 실행)
│  ├─ lib/
│  │  ├─ _common.ps1         공통 함수 모음 (ops, 직접 실행하지 않음)
│  │  └─ _devtools.ps1       개발 루프 전용 헬퍼 (직접 실행하지 않음)
│  ├─ start.ps1             기동 (데이터 폴더 자동 생성)
│  ├─ stop.ps1              정지 (컨테이너 유지)
│  ├─ restart.ps1           재시작
│  ├─ update.ps1            이미지 롤링 업데이트 (하나씩 무중단 갱신)
│  ├─ status.ps1            상태 확인
│  ├─ report.ps1            farm 상태 HTML 리포트 (읽기 전용)
│  ├─ databases.ps1         인스턴스별 DB 인벤토리 (크기·복구모델·최근 백업, 읽기 전용)
│  ├─ logs.ps1              로그 조회
│  ├─ query.ps1             여러 인스턴스에 T-SQL 일괄 실행
│  ├─ shell.ps1             대화형 sqlcmd 세션 열기
│  ├─ backup.ps1            전 인스턴스 DB 백업 (Full/Diff/Log)
│  ├─ restore.ps1           백업(.bak) 복원 (backup 의 짝)
│  ├─ copy-db.ps1           인스턴스 간 DB 복제 (backup+restore)
│  ├─ rotate-password.ps1   전 인스턴스 SA 비밀번호 회전
│  ├─ doctor.ps1            기동 전 .env/compose 규약 점검
│  ├─ down.ps1              컨테이너/네트워크 제거 (데이터 보존)
│  ├─ check.ps1             [개발] 린트 + doctor (+ -Test / -Watch)
│  └─ test.ps1              [개발] Pester 단위 테스트 실행
├─ tests/
│  └─ _common.Tests.ps1     [개발] _common.ps1 자동 발견/파싱 단위 테스트
├─ compose/
│  ├─ compose.yml           컨테이너 "구조" 정의 (설정값 없음)
│  ├─ .env                  모든 "설정값" — 여기만 고치면 됩니다 (Git 제외)
│  └─ .env.example          .env 의 견본 (비밀번호 비움, 팀 공유용)
├─ docs/
│  └─ README.md             이 문서
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

### report.ps1 — farm 상태 HTML 리포트 (읽기 전용)

인스턴스 상태·최근 백업·DB 인벤토리를 한 장의 HTML로 모아 저장합니다. 아무것도 바꾸지 않는 조회 전용이라, 스케줄러로 주기 생성해 두고 브라우저로 farm 현황을 확인하는 용도로 좋습니다.

```powershell
.\scripts\report.ps1                                             # <DATA_ROOT>\_report\farm_<시각>.html 로 저장
.\scripts\report.ps1 -OutFile C:\docker\_report\farm.html -Open   # 경로 지정 + 브라우저로 열기
.\scripts\report.ps1 -NoSize                                     # 데이터 용량 계산 생략 (빠름)
```

### databases.ps1 — DB 인벤토리 (읽기 전용)

어느 인스턴스에 어떤 DB가 있고, 데이터/로그 크기·복구 모델·최근 전체 백업 시각이 어떤지 한 표로 보여 줍니다. 백업 대상 파악과 용량 계획에 씁니다. 각 인스턴스에서 `sys.databases` + `sys.master_files` + `msdb..backupset`을 조인해 조회하며, 아무것도 바꾸지 않습니다.

```powershell
.\scripts\databases.ps1                       # 전체 인스턴스의 사용자 DB 인벤토리
.\scripts\databases.ps1 -Service db2019c      # 특정 인스턴스만
.\scripts\databases.ps1 -Database MyDb        # 그 이름의 DB가 어느 인스턴스에 있는지
.\scripts\databases.ps1 -IncludeSystem        # 시스템 DB(master/tempdb/model/msdb)까지 포함
```

기본은 **사용자 DB만** 보여 줍니다(시스템 DB 제외). `-Database`로 이름을 주면 시스템/사용자 구분 없이 그 DB만 추립니다. **최근 백업**은 복구의 기준선인 "전체(Full)" 백업의 최신 완료 시각이며, 이력이 없으면 `(없음)`으로 표시합니다. 꺼진 인스턴스는 조회할 수 없어 `DOWN`, 조회에 실패하면 `FAIL`로 표시하고, 하나라도 성공하지 못하면 종료 코드 1을 반환합니다(스케줄러 감지용).

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

### update.ps1 — 이미지 롤링 업데이트
```powershell
.\scripts\update.ps1                            # 전체를 하나씩 롤링 갱신
.\scripts\update.ps1 -Service db2022a,db2022b   # 지정한 인스턴스만
.\scripts\update.ps1 -NoPull                    # pull 없이 현재 로컬 이미지로 재생성만
.\scripts\update.ps1 -Timeout 180               # healthy 대기 제한 시간(초) 조정
```

인스턴스를 **하나씩** `pull → 재생성 → healthy 확인` 순으로 갱신하고 다음으로 넘어갑니다. 한 번에 한 인스턴스만 내려갔다 올라오므로 나머지는 계속 서비스합니다(무중단에 가까움). `restart.ps1 -Recreate`가 farm 전체를 동시에 내렸다 올리는 것과 대비됩니다.

**실패하면 그 지점에서 멈춥니다.** 이미 갱신한 인스턴스는 그대로 두고, 아직 손대지 않은 인스턴스는 건너뜁니다(SKIP) — 깨진 이미지를 farm 전체로 퍼뜨리지 않으려는 의도된 동작입니다. 마지막에 요약 표를 내고, 실패가 있으면 종료 코드 1을 반환합니다(스케줄러 감지용).

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

모든 인스턴스에 **같은 이름의 DB**가 있다는 전제로, 각 컨테이너 안에서 `BACKUP DATABASE`를 실행한 뒤 `.bak` 파일을 호스트로 꺼내옵니다. 백업 유형은 `-Type Full`(기본)·`Diff`(차등)·`Log`(트랜잭션 로그) 중에서 고릅니다.

```powershell
.\scripts\backup.ps1 -Database MyDb             # DB 이름 지정
.\scripts\backup.ps1                             # .env 의 BACKUP_DATABASE 사용
.\scripts\backup.ps1 -Service db2019c,db2022e    # 일부 인스턴스만
.\scripts\backup.ps1 -Verify                     # 백업 직후 RESTORE VERIFYONLY 검증
.\scripts\backup.ps1 -CopyOnly                   # 기존 백업 체인에 영향 없이
.\scripts\backup.ps1 -Type Diff                  # 차등 백업 (직전 전체 백업 이후 변경분)
.\scripts\backup.ps1 -Type Log                   # 트랜잭션 로그 백업
.\scripts\backup.ps1 -NotifyWebhook <URL>        # 백업 요약을 Teams/Slack 웹훅으로 전송
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

**복원**은 아래 `restore.ps1`을 쓰세요.

**야간 자동 백업** — 작업 스케줄러에 등록합니다. (경로는 실제 저장소 위치에 맞게 바꾸세요.)

```powershell
schtasks /create /tn "MSSQL Farm Backup" /sc daily /st 02:00 /rl highest `
  /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\path\to\mssql-farm\scripts\backup.ps1 -Verify"
```

### restore.ps1 — 복원

`backup.ps1`의 짝입니다. 파일을 직접 붙이지 않고 `RESTORE DATABASE`를 실행합니다. 번거로운 부분을 자동화합니다.

- **백업 파일 자동 선택**: `<BACKUP_ROOT>\<컨테이너명>\<DB>_*.bak` 중 **가장 최신** 파일
- **논리 파일 자동 이동**: `RESTORE FILELISTONLY`로 백업 안의 논리 파일명을 읽어 `WITH MOVE`를 자동 구성 → `/var/opt/mssql/data`로 배치
- **버전 자동 판별**: 2019/2022 sqlcmd 경로를 컨테이너에서 실제 확인 (`_common.ps1` 재사용)
- **활성 연결 정리**: 기존 DB가 있으면 `SINGLE_USER`로 연결을 끊고 `WITH REPLACE`로 덮어씀

```powershell
.\scripts\restore.ps1 -Service db2019c -Database MyDb          # 해당 인스턴스의 최신 백업 복원
.\scripts\restore.ps1 -Database MyDb                            # 전체 인스턴스에 각자의 최신 백업 복원
.\scripts\restore.ps1 -Service db2022b -BackupFile "C:\docker\_backup\Db2022B\MyDb_20260101_020000.bak"
.\scripts\restore.ps1 -Service db2019c -Database MyDb -NoRecovery  # 이후 로그 백업을 이어 복원 (RESTORING 유지)
.\scripts\restore.ps1 -Service db2019c -Database MyDb -Chain       # 최신 전체->차등->로그 체인 자동 복원
.\scripts\restore.ps1 -Service db2019c -Database MyDb -Force        # 확인 프롬프트 없이
.\scripts\restore.ps1 -Database MyDb -Force -NotifyWebhook <URL>   # 복원 요약을 Teams/Slack 웹훅으로 전송
```

복원은 대상 DB를 **덮어쓰는 파괴적 작업**이므로 `-Force`가 없으면 먼저 확인합니다. 한 인스턴스가 실패해도 나머지는 계속 진행하고, 실패가 있으면 종료 코드 1을 반환합니다. `-BackupFile`은 파일 하나를 뜻하므로 `-Service`로 인스턴스를 하나만 지정했을 때만 씁니다. `-Chain`은 `backup.ps1 -Type Diff/Log`로 만든 차등·로그 백업을 최신 전체 백업부터 순서대로 이어 복원합니다(중간 단계는 자동으로 `NORECOVERY`).

> 자동 복원은 데이터(`D`)·로그(`L`) 파일만 처리합니다. FILESTREAM 등 다른 유형이 있으면 중단하고 수동 복원을 안내합니다.

### copy-db.ps1 — 인스턴스 간 DB 복제

`backup.ps1`(copy-only 전체 백업) + `restore.ps1`을 조합해, 한 인스턴스의 DB를 다른 인스턴스로 한 번에 복제합니다. copy-only라 원본의 백업 체인(차등 기준 등)에는 영향을 주지 않습니다.

```powershell
.\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb                        # 같은 이름으로 복제
.\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb -AsDatabase MyDb_stg   # 다른 이름으로
.\scripts\copy-db.ps1 -From db2022a -To db2022a -Database MyDb -AsDatabase MyDb_clone # 같은 인스턴스 안에서 클론
```

`-To`의 대상 DB를 덮어쓰는 **파괴적 작업**이라 `-Force`가 없으면 먼저 확인합니다. 전송에 쓴 `.bak`은 `<BACKUP_ROOT>\<From 컨테이너>\`에 남습니다(보관 정책이 정리).

### query.ps1 — 여러 인스턴스에 T-SQL 일괄 실행

인스턴스가 여러 개인 farm에서 "전부에 같은 질의"(버전 확인, DB 목록, 설정 점검)를 한 번에 실행합니다. `_common.ps1`의 `Invoke-Sql`을 그대로 씁니다.

```powershell
.\scripts\query.ps1 "SELECT @@VERSION"                                    # 전체 인스턴스 버전
.\scripts\query.ps1 "SELECT name FROM sys.databases ORDER BY name" -Service db2019c
.\scripts\query.ps1 -File .\scripts\sql\health.sql                        # 파일에서 읽어 실행
.\scripts\query.ps1 "SELECT COUNT(*) FROM dbo.Orders" -Database MyDb -Service db2022a,db2022b
```

읽기 쿼리에 권장합니다. 데이터를 바꾸는 문장(`UPDATE`/`DROP` 등)도 실행되므로, 전체 대상으로 파괴적 쿼리를 돌릴 때는 `-Service`로 범위를 좁히세요. 꺼진 인스턴스는 `DOWN`으로 표시되고, 하나라도 성공하지 못하면 종료 코드 1을 반환합니다.

### shell.ps1 — 대화형 sqlcmd 세션

임시 확인·수정을 하려고 매번 긴 `docker exec -it ... sqlcmd ...`를 치는 수고 없이, 서비스 키 하나로 해당 인스턴스에 sqlcmd 프롬프트(`1>`)를 바로 엽니다. 버전(2019/2022)과 비밀번호는 `_common.ps1`이 자동 처리하며, `-P` 대신 `SQLCMDPASSWORD` 환경변수로 접속합니다.

```powershell
.\scripts\shell.ps1 -Service db2019c              # db2019c 에 master 로 접속
.\scripts\shell.ps1 db2022b -Database MyDb        # 서비스 키는 첫 인자로도 받음, 기본 DB 지정
```

대화형 세션이라 대상은 **정확히 하나**여야 합니다. 인스턴스가 2개 이상이면 `-Service`로 하나를 지정하세요. 세션 종료는 프롬프트에서 `EXIT`/`QUIT`(또는 Ctrl+C).

### rotate-password.ps1 — SA 비밀번호 회전

> **미검증 — 이 스크립트는 실 SQL Server 환경에서 아직 한 번도 검증되지 않았습니다**([#16](https://github.com/Chigo55/Docker-Compose/issues/16)).
> 아래 설명하는 롤백(실패 시 원복)은 정적 검토만 거쳤습니다. 회전과 롤백이 모두 실패하면 인스턴스별 비밀번호가 `.env`와 어긋나 farm 접속이 막힙니다.

모든 인스턴스는 `.env`의 `MSSQL_SA_PASSWORD` 하나를 공유하므로, 회전은 farm 전체에 대해 **모두 성공 또는 모두 원복**으로만 처리합니다(일부만 바뀌면 `.env`와 어긋나 인증이 조용히 깨집니다). 전 인스턴스에 `ALTER LOGIN [sa]`를 적용한 뒤 `.env`를 갱신하고, 하나라도 실패하면 이미 바꾼 인스턴스를 이전 값으로 되돌립니다. 시작 전 `.env`는 `compose/.env.bak.<시각>`으로 백업됩니다.

```powershell
.\scripts\rotate-password.ps1            # 새 비밀번호를 두 번 입력받아 적용
.\scripts\rotate-password.ps1 -Generate  # 정책 충족 무작위 비밀번호 생성 후 회전
```

되돌리기 어려운 farm 전체 작업이라 `-Force`가 없으면 먼저 확인합니다. **실제 환경에 쓰기 전 테스트 환경에서 검증하세요.** 전제로 모든 인스턴스가 실행 중이어야 하며, 새 비밀번호는 정책(8자 이상 + 3종)과 금지 문자($ " \ 그리고 백틱) 검사를 통과해야 합니다.

### doctor.ps1 — 기동 전 규약 점검

`compose/.env`와 `compose.yml`의 규약 위반을 **올리기 전에** 찾아냅니다. 한 곳이라도 어긋나면 기동이 조용히 실패하기 때문입니다.

```powershell
.\scripts\doctor.ps1
```

점검 항목: 필수 전역 키 · SA 비밀번호 정책(8자 이상 + 3종) · 인스턴스 3종 세트(`_NAME`/`_PORT`/`_DIR`) · 포트 중복/범위 · 데이터 폴더(`_DIR`) 중복 · **`.env` 접두사 ↔ `compose.yml` 서비스 키 일치(양방향)** · `DATA_ROOT` 접근 · 값 옆 인라인 주석/역슬래시 경로 · (Docker 실행 중이면) `docker compose config` 렌더링 성공. 결과는 `[OK]/[경고]/[오류]`로 보여 주고, 오류가 있으면 종료 코드 1을 반환합니다(경고만 있으면 0). 처음 기동 전이나 `.env`를 크게 바꾼 뒤 실행하면 좋습니다.

---

## 내부 개발 루프 (저장소를 고칠 때)

운영이 아니라 **스크립트나 `compose` 설정을 편집할 때** 쓰는 로컬 검증 루프입니다. 실사용 운영에는 필요 없습니다.

```powershell
.\scripts\check.ps1                 # 린트(PSScriptAnalyzer) + doctor(+compose 렌더링) 1회
.\scripts\check.ps1 -Test           # 위 + Pester 단위 테스트까지
.\scripts\check.ps1 -Watch -Test    # 파일 저장 때마다 전체 루프 자동 재실행 (편집→즉시 피드백)
.\scripts\test.ps1                  # Pester 단위 테스트만 (tests\ 폴더)
.\scripts\check.ps1 -Install        # 없는 개발 모듈(PSScriptAnalyzer/Pester)을 CurrentUser 로 설치
```

- 오류가 하나라도 있으면 **종료 코드 1**을 반환합니다(CI/자동화 감지용).
- **개발 모듈은 선택 의존성**입니다. 없으면 해당 단계만 건너뛰고(노란 안내), `-Install`로 부트스트랩합니다.
  테스트는 **Pester 5 이상**이 필요합니다(Windows 기본 3.4.0 은 문법이 달라 쓰지 않음).
- 린트는 이 저장소 관례와 충돌하는 규칙 5개를 제외합니다(제외 이유는 `check.ps1` 의 `$ExcludedRules` 주석 참고): `PSAvoidUsingWriteHost` · `PSUseSingularNouns` · `PSReviewUnusedParameter` · `PSAvoidUsingPlainTextForPassword`(평문 SA 비밀번호는 의도된 설계 — ADR-0013) · `PSUseShouldProcessForStateChangingFunctions`(수동 y/N 프롬프트 관례 — CONVENTIONS §9).
- 단위 테스트는 Docker가 필요 없는 순수 로직(`Read-DotEnv` 파싱, `Get-Instances` 발견, `Resolve-Services` 검증)을 대상으로 합니다.

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

대화형 셸(`shell.ps1`)·차등/로그 백업(`backup.ps1 -Type`)·비밀번호 회전(`rotate-password.ps1`)·인스턴스 간 복제(`copy-db.ps1`)·farm 리포트(`report.ps1`)·DB 인벤토리(`databases.ps1`)·이미지 롤링 업데이트(`update.ps1`)는 이미 구현되어 위에 정리했습니다.
남은 계획의 단일 소스는 [GitHub Project](https://github.com/users/Chigo55/projects/4)와 `roadmap` 라벨 이슈입니다. 단위 테스트·린트·GitHub Actions CI 는 위의 [내부 개발 루프](#내부-개발-루프-저장소를-고칠-때)와 `.github/workflows/ci.yml` 로 이미 갖췄습니다.

---

## 보안

취약점을 발견하면 **공개 이슈가 아니라** [Security 탭의 비공개 신고](https://github.com/Chigo55/Docker-Compose/security/advisories/new)로 알려주세요. 신고 범위와 이 저장소의 의도된 설계(평문 `.env` 등 — 오신고가 잦은 부분)는 [SECURITY.md](../.github/SECURITY.md)에 정리해 두었습니다.

---

## 라이선스

[MIT License](../LICENSE) © 2026 정인호 (Inho Jeong)

> 공개 시 주의: 실제 값이 든 `compose/.env`(SA 비밀번호 포함)는 `.gitignore`로 제외되어 커밋되지 않습니다. 저장소를 공개하기 전에 `git log`/현재 트리에 `.env`나 `.bak` 등 민감 파일이 들어가 있지 않은지 반드시 확인하세요.
