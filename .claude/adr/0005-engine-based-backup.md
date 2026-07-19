---
summary: "`.mdf` 직접 복사 금지"
---

# ADR-0005: 백업은 엔진 `BACKUP DATABASE`로만 한다 (파일 복사 금지)

- 상태: Accepted
- 관련: [ADR-0004](0004-host-bind-mount-for-data.md), [ADR-0009](0009-password-via-env-var.md), `scripts/backup.ps1`, `scripts/restore.ps1`

## 배경 (Context)

데이터가 호스트 바인드 마운트에 있으므로([ADR-0004](0004-host-bind-mount-for-data.md)) `.mdf`/`.ldf`를
그냥 복사하고 싶은 유혹이 있다. 그러나 실행 중인 인스턴스의 데이터 파일은 SQL Server가
계속 쓰고 있어, 파일 단위 복사는 **트랜잭션적으로 일관되지 않은(손상된) 사본**을 만든다.

## 결정 (Decision)

백업은 **반드시 SQL Server 엔진에게 `BACKUP DATABASE`를 시킨다.** `backup.ps1`의 절차:

1. 컨테이너 실행 + DB 존재 + `ONLINE` 상태 확인
2. 컨테이너 안 스테이징 폴더에 `BACKUP DATABASE ... WITH INIT, CHECKSUM, FORMAT, STATS=10`
   (기본 `COMPRESSION`, 선택 `COPY_ONLY`)
3. `-Verify` 시 `RESTORE VERIFYONLY ... WITH CHECKSUM`으로 무결성 검증
4. `docker cp`로 호스트(`<BACKUP_ROOT>\<컨테이너명>\<DB>_<timestamp>.bak`)로 복사
5. 컨테이너 안 임시 파일 삭제

복원도 대칭적으로 `restore.ps1`이 `RESTORE FILELISTONLY`로 논리 파일명을 읽어 `WITH MOVE`를
자동 구성한다.

## 결과 (Consequences)

- **좋은 점**: 실행 중인 인스턴스에서도 일관된 백업을 얻는다.
- **좋은 점**: `CHECKSUM` + `RESTORE VERIFYONLY`로 백업 직후 무결성을 검증할 수 있다.
- **감수할 점**: 백업은 컨테이너가 살아 있고 DB가 ONLINE 일 때만 가능하다(오프라인 파일 백업 불가).
- **감수할 점**: 스테이징→`docker cp`→정리 단계가 있어 파일 복사보다 절차가 길다(스크립트가 캡슐화).
