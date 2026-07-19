# 아키텍처 결정 기록 (ADR)

이 폴더는 MSSQL Farm 저장소의 **아키텍처 결정 기록(Architecture Decision Records)** 을 담습니다.
각 파일은 "왜 이렇게 만들었는가"를 하나씩 기록합니다. 코드만 봐서는 의도를 놓치기 쉬운
설계 판단을, 배경(Context) · 결정(Decision) · 결과(Consequences)로 나눠 남깁니다.

> ADR 은 한 번 확정되면 **수정하지 않고, 뒤집을 때 새 ADR 로 대체(Superseded)** 하는 것이 관례입니다.
> 새 결정을 내렸다면 기존 파일을 지우지 말고 상태를 `Superseded by ADR-XXXX` 로 바꾸세요.

## 형식

각 ADR 은 다음 구조를 따릅니다. 맨 위 frontmatter 의 `summary` 는 인덱스 생성기
(`scripts\gen-docs-index.ps1`)가 목록 표를 만들 때 쓰는 한 줄 요약입니다([ADR-0021](0021-generated-doc-index.md)).

```
---
summary: 한 줄 요약(인덱스 자동 생성용)
---
# ADR-NNNN: 제목
- 상태: Accepted | Superseded | Deprecated
- 관련: 함께 읽을 ADR / 파일

## 배경 (Context)   무엇이 문제였는가
## 결정 (Decision)  무엇을 하기로 했는가
## 결과 (Consequences)  그래서 무엇이 좋아지고 무엇을 감수하는가
```

## 목록

ADR 목록 표는 **저장소에 커밋하지 않습니다.** 여러 PR 이 같은 표 마지막 줄에 동시에 행을
추가하다 충돌하던 문제를 없애기 위해서입니다([ADR-0021](0021-generated-doc-index.md)). 각 ADR 의 한 줄
요약은 그 파일 맨 위 frontmatter(`summary:`)에 있고(파일을 열면 GitHub 이 표로 보여 줍니다),
전체 목록 표는 생성기로 만들어 봅니다.

```powershell
.\scripts\gen-docs-index.ps1                      # ADR·rules 목록을 화면에 출력
.\scripts\gen-docs-index.ps1 -Out docs\_generated # 파일로 저장(gitignored)
```

> **새 ADR 을 추가할 때는 이 README 를 건드리지 마세요.** 새 파일 맨 위에 `summary` frontmatter 만
> 넣으면 됩니다. 목록은 위 생성기로 뽑고, CI 가 `summary` 누락을 잡습니다([ADR-0021](0021-generated-doc-index.md)).
