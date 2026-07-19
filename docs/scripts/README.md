# 스크립트 사용법 (docs/scripts)

이 폴더는 `scripts/` 의 스크립트 **하나당 문서 하나**를 담습니다. 옵션·동작·주의사항의
**단일 소스**이며, 사용자 문서의 입구는 [../README.md](../README.md) 입니다.

> 왜 파일을 쪼갰나요? 예전에는 모든 사용법이 `docs/README.md` 의 한 섹션에 쌓였습니다.
> 스크립트를 추가하는 PR 마다 같은 섹션 끝에 블록을 append 해 **병렬 PR 이 결정적으로 충돌**했습니다.
> 스크립트당 파일 하나면 새 PR 은 자기 새 파일만 만들고 공유 영역을 건드리지 않습니다
> ([ADR-0022](../../.claude/adr/0022-per-script-docs.md), [ADR-0021](../../.claude/adr/0021-generated-doc-index.md)).

## 형식

각 문서는 맨 위 frontmatter 로 시작합니다. `summary` 는 인덱스 생성기
(`scripts\gen-docs-index.ps1`)가 목록 표를 만들 때 쓰는 한 줄 요약입니다.

````
---
summary: 한 줄 요약(인덱스 자동 생성용)
---
# <name>.ps1 — 무엇을 하는 스크립트인가

<한두 문단 설명>

```powershell
<대표 실행 예시>
```

<주의사항 · 동작 순서 · 종료 코드>
````

## 목록

목록 표는 **저장소에 커밋하지 않습니다.** ADR·rules 인덱스와 같은 이유입니다
([ADR-0021](../../.claude/adr/0021-generated-doc-index.md)) — 공유 표가 없으면 충돌할 대상도 없습니다.
각 문서의 요약은 그 파일 맨 위 frontmatter 에 있고(파일을 열면 GitHub 이 표로 보여 줍니다),
전체 표는 생성기로 만들어 봅니다.

```powershell
.\scripts\gen-docs-index.ps1                      # ADR·rules·scripts 목록을 화면에 출력
.\scripts\gen-docs-index.ps1 -Out docs\_generated # 파일로 저장(gitignored)
```

> **새 스크립트를 추가할 때는 이 README 를 건드리지 마세요.** `docs/scripts/<name>.md` 를 새로
> 만들고 맨 위에 `summary` frontmatter 를 넣으면 됩니다. 문서를 빠뜨리거나 요약을 빠뜨리면
> `.\scripts\check.ps1`(그리고 CI)이 잡습니다.

## 공통 규칙

- 모든 스크립트는 **저장소 맨 위 폴더**에서 `.\scripts\<name>.ps1` 로 실행합니다.
- 인스턴스 목록은 `compose/.env` 스캔으로 **자동 발견**됩니다. 인스턴스가 늘어도 스크립트는
  고치지 않습니다([ADR-0002](../../.claude/adr/0002-instance-autodiscovery.md)).
- 대부분의 스크립트는 `-Service <서비스키>` 로 대상을 좁힐 수 있습니다. 서비스키는 `.env`
  접두사의 소문자입니다(예: `DB2019C_*` → `db2019c`). 오타를 내면 사용 가능한 목록과 함께
  알려 주고 멈춥니다.
- 배치 성격의 스크립트는 한 인스턴스가 실패해도 나머지를 계속 진행하고, 마지막에 요약 표를
  낸 뒤 실패가 있으면 **종료 코드 1** 을 반환합니다(스케줄러 감지용).
