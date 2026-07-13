# `.env` 형식 (compose/.env)

- **`$`는 `$$`로 이스케이프**한다. compose 변수 확장 규칙 때문이다. — 단, [비밀번호에는 예외](secrets.md).
- **Windows 경로도 슬래시 `/`를 쓴다** (`DATA_ROOT=C:/docker`). 역슬래시 금지.
- **주석은 값 옆이 아니라 윗줄에 단다.** 값 뒤 인라인 주석(`KEY=값  # 설명`)은 `Read-DotEnv`가
  주석을 값의 일부로 읽어 포트·비밀번호를 깨뜨린다.
- 값은 모두 ASCII 로, 한글은 주석에만 둔다([ADR-0012](../adr/0012-utf8-bom-for-powershell.md)).

> 배경: [ADR-0001](../adr/0001-env-single-source-of-truth.md) (`.env`가 유일한 설정 소스)
