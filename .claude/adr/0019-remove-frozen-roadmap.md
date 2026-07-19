---
summary: "역사 보존은 git 이 한다 — ADR-0016 의 동결 조항 대체"
---

# ADR-0019: 동결된 `docs/ROADMAP.md` 를 삭제한다

- 상태: Accepted
- 관련: [ADR-0016](0016-track-in-github-not-docs.md)(이 ADR 이 그 "동결 보존" 조항을 대체한다), [ADR-0018](0018-wiki-for-learning-repo-for-code.md)

## 배경 (Context)

[ADR-0016](0016-track-in-github-not-docs.md)은 로드맵의 단일 소스를 GitHub Project 로 옮기면서,
`docs/ROADMAP.md` 는 **동결된 초기 스냅샷**으로 남기기로 했다. 초기 계획의 근거를 잃지 않으려는
판단이었다.

그 조항이 잘 늙지 않았다.

- **동결 문서는 실제와 어긋난다.** ADR-0016 이 스스로 "감수할 점" 으로 적어둔 그대로다. 지금
  `shell.ps1`·`report.ps1`·`copy-db.ps1`·`rotate-password.ps1` 은 구현이 끝났는데 문서에는 여전히
  "추가하면 좋을 기능" 으로 적혀 있다.
- **역사 보존은 이미 git 이 한다.** 동결 사본을 워킹트리에 두지 않아도 git history 와 태그
  (v1.0 ~ v1.1.1)에 그대로 남는다. 워킹트리의 사본은 보존이 아니라 중복이다.
- **워킹트리에 있는 문서는 "읽으라고 있는 것" 으로 읽힌다.** 상단 배너를 붙여도, 253줄을 열어
  배너를 확인한 뒤에야 안 읽어도 되는 문서였음을 안다.

## 결정 (Decision)

- **`docs/ROADMAP.md` 를 삭제한다.** [ADR-0016](0016-track-in-github-not-docs.md)의 "동결하여 남긴다"
  조항을 이 ADR 이 대체한다. **로드맵의 단일 소스가 Project 라는 결정 자체는 그대로 유효**하다.
- 저장소 안의 참조(`CLAUDE.md`·`docs/README.md`·`.claude/rules/`)는 Project 링크로 바꾼다.
- **[ADR-0013](0013-plaintext-password-gitignored.md)·[ADR-0014](0014-internal-dev-loop.md)·`ci.yml` 의
  인용("ROADMAP 의 out-of-scope", "ROADMAP P3-9")은 고치지 않고 그대로 둔다.** ADR 은 확정 시점의
  사실을 적은 역사 기록이고, 수정하지 않는 것이 [이 폴더의 관례](README.md)다. 그 시점에 그 문서는
  실제로 있었다.

## 결과 (Consequences)

- **좋은 점**: 실제와 어긋난 문서를 읽고 오해할 여지가 사라진다. 로드맵을 찾는 사람은 Project 한 곳으로 간다.
- **좋은 점**: "동결 배너를 유지한다" 는 관리 항목이 없어진다.
- **감수할 점**: 이슈 제목의 항목 번호(예: [#5](https://github.com/Chigo55/Docker-Compose/issues/5) "P1-2",
  [#9](https://github.com/Chigo55/Docker-Compose/issues/9) "P2-6")의 출처가 워킹트리에 없다. 번호의 뜻이
  궁금하면 git history(`git show v1.1.1:docs/ROADMAP.md`)에서 본다.
- **감수할 점**: ADR-0013·ADR-0014·`ci.yml` 의 인용이 워킹트리에 없는 문서를 가리킨다. 의도된 것이며,
  위 명령으로 원문을 확인할 수 있다.
