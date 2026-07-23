---
summary: "엔진 백업(Full/Diff/Log) + 검증·보관 정리 — `.mdf` 직접 복사 금지"
---

# backup.ps1 — 백업

모든 인스턴스에 **같은 이름의 DB**가 있다는 전제로, 각 컨테이너 안에서 `BACKUP DATABASE`를
실행한 뒤 `.bak` 파일을 호스트로 꺼내옵니다. 백업 유형은 `-Type Full`(기본)·`Diff`(차등)·
`Log`(트랜잭션 로그) 중에서 고릅니다.

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

한 인스턴스가 실패해도 나머지는 계속 진행하고, 마지막에 요약 표를 보여줍니다. 실패가 있으면
종료 코드 1을 반환하므로 스케줄러에서 성공 여부를 감지할 수 있습니다.

**데이터 파일(`.mdf`)을 직접 복사하지 마세요.** 실행 중인 인스턴스의 파일을 복사하면 손상된
사본이 나옵니다. 이 스크립트가 안전한 이유는 SQL Server 엔진에게 백업을 시키기 때문입니다
([ADR-0005](../../.claude/adr/0005-engine-based-backup.md)).

**복원**은 [restore.ps1](restore.md) 을 쓰세요.

**야간 자동 백업** — 작업 스케줄러에 등록합니다. (경로는 실제 저장소 위치에 맞게 바꾸세요.)

```powershell
schtasks /create /tn "MSSQL Farm Backup" /sc daily /st 02:00 /rl highest `
  /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\path\to\mssql-farm\scripts\backup.ps1 -Verify"
```
