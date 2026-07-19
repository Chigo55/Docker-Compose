# 편집 규칙 (rules)

이 폴더는 이 저장소를 **안전하게 고치기 위한 가드레일**을 주제별로 나눠 담는다. 대부분의
규칙은 어기면 "조용한 기동 실패"나 "손상된 백업" 같은, 즉시 드러나지 않는 사고로 이어진다.
결정의 배경은 [ADR](../adr/README.md)에, 코드 스타일은 [CONVENTIONS](../CONVENTIONS.md)에 있다.

> 대부분의 규칙은 `.\scripts\doctor.ps1`이 자동 점검한다. **편집 후 커밋 전 `.\scripts\check.ps1 -Test`를 돌린다.**

## 목록

rules 목록 표는 **저장소에 커밋하지 않는다.** 여러 PR 이 같은 표에 동시에 행을 추가하다
충돌하던 문제를 없애기 위해서다([ADR-0021](../adr/0021-generated-doc-index.md)). 각 rule 의 "다루는 것"
요약은 그 파일 맨 위 frontmatter(`summary:`)에 있고(파일을 열면 GitHub 이 표로 보여 준다),
전체 목록 표는 생성기로 만들어 본다.

```powershell
.\scripts\gen-docs-index.ps1                      # ADR·rules 목록을 화면에 출력
.\scripts\gen-docs-index.ps1 -Out docs\_generated # 파일로 저장(gitignored)
```

> **새 rule 을 추가할 때는 이 README 를 건드리지 마라.** 새 파일 맨 위에 `summary` frontmatter 만
> 넣으면 된다. 목록은 위 생성기로 뽑고, CI 가 `summary` 누락을 잡는다([ADR-0021](../adr/0021-generated-doc-index.md)).
