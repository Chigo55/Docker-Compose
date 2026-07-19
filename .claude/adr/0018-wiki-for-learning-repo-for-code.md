---
summary: '판별 기준 = "코드가 바뀌면 같이 늙는가"'
---

# ADR-0018: Wiki 는 학습 자료, 저장소는 코드에 붙은 문서

- 상태: Accepted
- 관련: [ADR-0016](0016-track-in-github-not-docs.md), [ADR-0017](0017-ruleset-enforced-main-protection.md), [rules/github.md](../rules/github.md), [#26](https://github.com/Chigo55/Docker-Compose/issues/26)

## 배경 (Context)

저장소 문서는 사실상 전부 **고치는 사람**을 위한 것이다 — [adr/](README.md)(왜 이렇게 만들었나),
[rules/](../rules/README.md)(어기면 사고 나는 것), [CONVENTIONS.md](../CONVENTIONS.md)(코드 스타일),
`CLAUDE.md`(에이전트용). `docs/README.md` 만이 **쓰는 사람**용인데 그마저 옵션 레퍼런스지 학습
자료가 아니다. "컨테이너가 무엇인가", "왜 실행 중 `.mdf` 를 복사하면 안 되나" 를 담을 곳이 없었다.

Wiki 를 켜는 것은 한 번 반대했었다. 근거는 "문서가 코드와 갈라지면 아무도 모른다" 였다. 그런데 그
위험은 **코드에 붙은 문서**에만 있다. "Docker 볼륨이란 무엇인가" 는 `start.ps1` 이 바뀐다고 변하지
않는다. 드리프트할 게 없는 문서에는 드리프트 논거가 통하지 않는다.

여기에 [ADR-0017](0017-ruleset-enforced-main-protection.md) 이 더해졌다. main 이 ruleset 으로 보호되면서
`docs/` 한 줄을 고치는 데도 worktree → PR → CI 왕복이 든다. **배우면서 끄적이는 메모에 그 절차는 과하다.**

## 결정 (Decision)

문서를 둘 곳은 판별 기준 **하나**로 정한다 — **코드가 바뀌면 이 문서도 같이 늙는가?**

| 문서 | 위치 | 이유 |
|------|------|------|
| Docker/SQL Server 개념, 용어집, 트러블슈팅 경험담 | **Wiki** | 코드가 바뀌어도 늙지 않음 |
| 스크립트 옵션·사용법 | `docs/README.md` | 코드와 함께 늙어야 함 |
| 편집 가드레일 | `.claude/rules/` | `check.ps1` 이 검증하는 규약과 짝 |
| 결정의 배경 | `.claude/adr/` | 커밋과 함께 늙어야 의미 있음 |

- **Wiki 에 스크립트 사용법을 복사하지 않는다.** Wiki 는 별도 git 저장소라 CI 도 PR 리뷰도 없다.
  복사하는 순간 두 벌이 되고, 코드가 바뀌어도 조용히 낡는다. 사용법은 항상 `docs/README.md` 로 **링크**한다.
- Wiki 의 단일 진입점은 [Home](https://github.com/Chigo55/Docker-Compose/wiki) 이고, 저장소 About 의
  `homepage` 가 Wiki 를 가리킨다.

## 결과 (Consequences)

- **좋은 점**: 학습 자료가 생겼고(학습 로드맵), 웹에서 즉시 저장되므로 PR 왕복이 없다.
- **좋은 점**: `docs/README.md` 가 레퍼런스로 남는다. 개념 설명이 섞여 교과서로 변질되지 않는다.
- **감수할 점**: 문서가 두 곳으로 나뉜다. 경계선("같이 늙는가")을 지키지 않으면 결국 갈라진다.
- **감수할 점**: Wiki 는 CI·리뷰·이 저장소의 규약([ADR-0012](0012-utf8-bom-for-powershell.md) 인코딩 규칙 등)
  밖에 있다. 링크가 깨져도 자동으로 잡히지 않는다.
