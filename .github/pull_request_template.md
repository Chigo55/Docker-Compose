## 요약

<!-- 무엇을, 왜 바꿨는지 1~2문장 -->

## 변경

<!-- 파일/영역별 변경 내용 -->

## 검증

- [ ] `.\scripts\check.ps1 -Test` 통과 (린트 + doctor + Pester)

## 체크리스트

- [ ] `.ps1` 을 고쳤다면 **UTF-8 with BOM** 으로 저장했다 ([ADR-0012](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/adr/0012-utf8-bom-for-powershell.md))
- [ ] `compose/.env` / `compose/compose.yml` 을 고쳤다면 **BOM 없이**, 값은 ASCII 로 유지했다
- [ ] 선택 항목(`MSSQL_MEMORY_LIMIT_MB`/`MSSQL_AGENT_ENABLED`/`MOUNT_LOG_SECRETS`)을 건드렸다면 **양쪽 다** 주석을 해제했다 ([rules/instances.md](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/rules/instances.md))
- [ ] 인스턴스를 추가/변경했다면 3종 세트(`_NAME`/`_PORT`/`_DIR`) + 서비스키(= prefix 소문자)가 `compose.yml` 서비스 키와 일치한다
- [ ] CI `run:` 블록(`.github/workflows/*.yml`)을 고쳤다면 **ASCII 전용**을 유지했다
- [ ] `ci.yml` 의 job `name:` 을 바꿨다면 Ruleset 의 **필수 상태 체크 이름도 함께** 고쳤다 (안 고치면 모든 PR 이 병합 불가로 멈춤 — [ADR-0017](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/adr/0017-ruleset-enforced-main-protection.md))
- [ ] 새 워크플로가 PR·이슈에 무언가를 쓴다면 `permissions:` 를 명시했다 (저장소 기본값은 `read` — 없으면 조용히 아무것도 안 남음)
- [ ] 순수 로직을 추가/수정했다면 `tests/` 에 테스트를 동반했다
- [ ] 새 ADR/rule 을 추가했다면 **README 인덱스 표를 손대지 않고**, 새 파일 맨 위에 `summary` frontmatter 만 넣었다 ([ADR-0021](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/adr/0021-generated-doc-index.md))
- [ ] 릴리스에 남을 변경이면 **카테고리 라벨**(`enhancement`/`bug`/`documentation`/`refactor`/`removed`/`dependencies` 등)을 붙였다 (릴리스 노트 자동 분류 — [ADR-0020](https://github.com/Chigo55/Docker-Compose/blob/main/.claude/adr/0020-generate-release-notes-from-prs.md))

Closes #
