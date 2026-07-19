---
summary: "ADR·rules 인덱스 표를 커밋하지 않고 각 파일 frontmatter 에서 생성 — 병렬 PR 충돌 제거"
---

# ADR-0021: 문서 인덱스 표를 각 파일 frontmatter 에서 생성한다 — 공유 표 커밋 폐지

- 상태: Accepted
- 관련: [ADR-0020](0020-generate-release-notes-from-prs.md)(같은 원칙을 릴리스 노트에 먼저 적용), [ADR-0016](0016-track-in-github-not-docs.md)·[ADR-0018](0018-wiki-for-learning-repo-for-code.md)·[ADR-0019](0019-remove-frozen-roadmap.md)(문서→GitHub 이관/동결 제거 라인), [ADR-0017](0017-ruleset-enforced-main-protection.md)(자동 커밋을 막는 제약), 이슈 [#50](https://github.com/Chigo55/Docker-Compose/issues/50)

## 배경 (Context)

병렬 작업(worktree·다중 PR)에서 **문서 인덱스 표의 머지 충돌이 반복**됐다. 근원은 개별 내용이 아니라
구조다 — 여러 PR 이 같은 표의 **마지막 줄에 동시에 행을 append** 한다.

- `.claude/adr/README.md`·`.claude/rules/README.md` 의 "목록" 표가 대표적이다. 두 PR 이 각각 ADR/rule 을
  하나씩 추가하면 표 끝줄에서 **결정적으로** 충돌한다(`append-to-shared-table` 패턴).
- 이 저장소는 이미 같은 통증을 GitHub 기능으로 해소한 선례가 있다: [ADR-0020](0020-generate-release-notes-from-prs.md) 은
  `CHANGELOG.md` 의 수기 `[Unreleased]` 를 병합 PR 자동 생성으로 대체해 **병렬 PR 충돌을 제거**했다. #50 은
  이 원칙을 남은 문서로 일반화한다.
- 인덱스 표의 "요약"은 파일에서 **자동 도출되지 않는다.** 표는 제목(H1)과 별개인, 손으로 쓴 한 줄 요약을
  담는다. 생성하려면 그 요약을 **각 파일 안에 기계 판독 가능한 형태로** 둬야 한다.

핵심 제약 — **워크플로가 인덱스를 자동 커밋하는 길은 막혀 있다.** main 은 Ruleset 으로 보호되어(bypass 없음,
[ADR-0017](0017-ruleset-enforced-main-protection.md)) 어떤 액터도 main 에 직접 push 하지 못한다. 게다가 `GITHUB_TOKEN` 으로 연 PR 은 추가
워크플로(CI)를 트리거하지 않아 필수 상태 체크가 도착하지 않는다. 즉 "병합 후 봇이 표를 갱신" 류의 자동화는
PAT 등 무거운 장치를 요구한다.

검토한 대안:

- **A. 표를 커밋하되 CI 신선도 검사**(`check.ps1` 이 표가 낡았는지 검출) — `check.ps1` 루프와 자연스럽고
  GitHub 에서 표가 그대로 보인다. 그러나 두 PR 이 각자 표를 재생성하면 **여전히 같은 줄에서 기계적 충돌**이 난다.
  재생성으로 쉽게 풀리지만 #50 의 완료 기준("병렬 PR 에도 인덱스 충돌 없음")을 완전히는 못 채운다. 채택 안 함.
- **C. 병합 후 봇 PR 자동화** — 표를 유지하면서 충돌도 없앤다. 그러나 위 제약(ruleset·`GITHUB_TOKEN` CI 미트리거)
  때문에 PAT·권한 상향이 필요해 이 저장소엔 과하다. 채택 안 함.
- **D. `.gitattributes` union 병합** — 하드 충돌만 없애고 순서·중복은 보장 못 한다. 생성 방식을 택하면
  per-PR 편집 자체가 사라져 무의미하다([ADR-0020](0020-generate-release-notes-from-prs.md) 이 같은 이유로 기각). 채택 안 함.

## 결정 (Decision)

- **인덱스 표를 저장소에 커밋하지 않는다(모델 A).** `README.md` 의 "목록" 표를 제거하고, 그 자리에 생성 방법
  안내를 남긴다. 공유 표가 없으므로 병렬 PR 이 건드릴 대상 자체가 사라진다 — **충돌 원천 소멸.**
- **한 줄 요약은 각 파일 맨 위 frontmatter `summary` 에 둔다.** 요약이 자기 파일에 살아(파일당 1줄, 공유 아님)
  충돌하지 않고, 표준 YAML frontmatter 라 GitHub 이 파일을 열 때 표로 렌더링해 요약이 파일 안에서 보인다.
- **표는 `scripts/gen-docs-index.ps1` 로 온디맨드 생성한다.** 기본은 화면 출력, `-Out <dir>` 로 파일 저장
  (gitignored, `docs/_generated/`). 파서는 외부 모듈 없이 `--- ... ---` 를 손파싱한다(PS 5.1 기본엔 YAML 모듈이 없다).
- **CI/`check.ps1` 는 "표 신선도"가 아니라 "frontmatter 완비"를 검증한다.** `gen-docs-index.ps1 -Check` 가
  모든 ADR·rule 에 `summary` 가 있는지 확인하고, 없으면 `exit 1`. `check.ps1` 이 이를 세 번째 단계로 편입한다.
- **기존 ADR·rule 에 `summary` frontmatter 를 일괄 추가한다.** ADR 은 "확정 후 수정하지 않는다"([README](README.md))가
  원칙이지만, 요약 메타데이터 추가는 **결정 내용을 바꾸지 않는 기계적·비의미(non-semantic) 마이그레이션**이라
  이 일괄 편집은 예외로 둔다.

## 결과 (Consequences)

- **좋은 점**: ADR/rule 을 추가하는 두 PR 을 병렬로 올려도 인덱스에서 충돌이 나지 않는다. 각 PR 은 자기 새
  파일만 추가하고, 공유 표를 아예 건드리지 않는다.
- **좋은 점**: 요약이 그 결정/규칙 파일에 함께 산다(분산). 표라는 별도 관리 지점이 사라져 드리프트가 준다.
- **좋은 점**: [ADR-0019](0019-remove-frozen-roadmap.md)(드리프트하는 동결 문서 삭제)·[ADR-0020](0020-generate-release-notes-from-prs.md)(수기 집약 폐지)의 결을 잇는다.
  워크플로·외부 액션이 없어 [Actions 기본 권한 `read` 함정](../rules/github.md#actions)에 걸리지 않는다.
- **감수할 점**: 한눈에 보는 요약 표가 **GitHub README 에서는 사라진다.** 전체 표는 생성기를 돌려야 보이고,
  개별 요약은 각 파일을 열어야(또는 frontmatter 렌더링으로) 본다. 폴더의 파일 목록이 이를 일부 보완한다.
- **감수할 점**: 새 파일에 `summary` 를 빠뜨리면 생성이 불완전해진다. 이를 CI(`-Check`)가 잡아 병합 전에 막는다.
- **감수할 점**: 생성 인덱스의 rule 순서는 **파일명 알파벳순**(결정적)이라, README 표가 갖던 주제별 수기 배열과
  다르다. 온디맨드 뷰라 영향은 작다.
