---
summary: "스케줄러가 실패 감지"
---

# ADR-0011: 배치 작업은 continue-on-error + 요약 표 + `exit 1`

- 상태: Accepted
- 관련: [ADR-0010](0010-preflight-validation-doctor.md), `scripts/backup.ps1`, `scripts/restore.ps1`, `scripts/query.ps1`

## 배경 (Context)

`backup`/`restore`/`query` 같은 스크립트는 여러 인스턴스를 한 번에 처리한다. 3번째
인스턴스에서 실패했다고 전체를 멈추면, 이미 처리했어야 할 나머지 인스턴스가 방치된다.
반대로 실패를 삼키면 스케줄러가 문제를 감지하지 못한다.

## 결정 (Decision)

배치 스크립트는 다음 패턴을 따른다.

1. 인스턴스마다 `try/catch`로 감싸 **하나가 실패해도 나머지를 계속** 진행한다.
   실패는 결과 행에 `FAIL` + 상세 메시지로 기록한다(실행 전 죽은 인스턴스는 `DOWN`).
2. 결과를 `[pscustomobject]` 행으로 모아 마지막에 `| Format-Table -AutoSize` 요약 표를 낸다.
3. 실패가 하나라도 있으면 **`exit 1`**(주석: "스케줄러가 실패를 감지할 수 있도록").
   전부 성공이면 Green 요약 후 암묵적 `0`.
4. 임시 자원은 `try/finally`로 성공·실패와 무관하게 정리한다.

사용자 취소(`-Force` 없이 y/N 프롬프트에서 거부)는 실패가 아니므로 `exit`가 아니라 `return`.

## 결과 (Consequences)

- **좋은 점**: 부분 실패에도 처리 가능한 인스턴스는 모두 처리된다.
- **좋은 점**: 종료 코드로 자동화(작업 스케줄러/CI)가 실패를 감지한다.
- **좋은 점**: 요약 표로 어떤 인스턴스가 왜 실패했는지 한눈에 보인다.
- **감수할 점**: 새 배치 스크립트도 이 패턴을 그대로 따라야 일관성이 유지된다(RULES 참조).
