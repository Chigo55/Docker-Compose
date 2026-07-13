# 이미지/sqlcmd 경로 · 변경 반영

## 이미지 / sqlcmd 경로

- sqlcmd 경로는 `.env`의 `MSSQL_2019_SQLCMD` / `MSSQL_2022_SQLCMD` 두 곳에만 있다. 이미지
  갱신으로 경로가 바뀌면 **여기만** 고친다([ADR-0006](../adr/0006-sqlcmd-version-autodetect.md)).

## 변경 반영 (restart 주의)

- 옵션 없는 `restart.ps1`은 `.env`의 **포트/이미지/볼륨 변경을 반영하지 못한다.** 이 경우
  `restart.ps1 -Recreate`(또는 `start.ps1 -Recreate`)를 쓴다.
