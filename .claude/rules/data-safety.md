# 데이터 안전

- 데이터는 호스트 바인드 마운트에 있다([ADR-0004](../adr/0004-host-bind-mount-for-data.md)). `down.ps1`은
  컨테이너만 지우고 **데이터는 보존**한다.
- **백업은 반드시 `backup.ps1`(엔진 `BACKUP DATABASE`)로** 한다. 실행 중 인스턴스의 `.mdf`를
  직접 복사하면 손상된 사본이 나온다([ADR-0005](../adr/0005-engine-based-backup.md)).
- `start.ps1`이 기동 전 데이터 폴더를 만든다. 이 순서를 우회해 수동으로 올리지 말 것(빈 폴더가
  생기면 기존 DB 를 못 붙는다).
