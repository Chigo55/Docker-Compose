---
summary: "[개발] ADR·rules·scripts 인덱스 생성/검증 — 표는 커밋하지 않음"
---

# gen-docs-index.ps1 — 문서 인덱스 생성·검증

이 저장소는 문서 인덱스 표(ADR·rules·scripts 목록)를 **커밋하지 않습니다.** 여러 PR 이 같은 표
마지막 줄에 동시에 행을 append 하다 결정적으로 충돌하던 문제를 없애기 위해서입니다
([ADR-0021](../../.claude/adr/0021-generated-doc-index.md), [ADR-0022](../../.claude/adr/0022-per-script-docs.md)).
대신 한 줄 요약은 각 문서 맨 위 frontmatter(`summary:`)에 두고, 표는 이 스크립트로 만들어 봅니다.

```powershell
.\scripts\gen-docs-index.ps1                       # ADR·rules·scripts 목록을 화면에 출력
.\scripts\gen-docs-index.ps1 -Out docs\_generated  # 파일로 저장 (gitignored)
.\scripts\gen-docs-index.ps1 -Check                # frontmatter·문서 완비 검증 (없으면 exit 1)
```

`-Check` 가 검증하는 것:

- `.claude/adr/*.md` · `.claude/rules/*.md` · `docs/scripts/*.md` 에 `summary` frontmatter 가 있는가
- `scripts/*.ps1` 마다 **대응 문서 `docs/scripts/<name>.md` 가 있는가** (문서 없는 새 스크립트 차단)
- 반대로 `docs/scripts/*.md` 중 **대응 스크립트가 사라진 고아 문서**가 없는가

[check.ps1](check.md) 이 이 검증을 세 번째 단계로 포함하므로, 보통은 `check.ps1` 만 돌리면 됩니다.
`-Out` 산출물(`docs/_generated/`)은 `.gitignore` 대상인 온디맨드 뷰입니다.
