---
summary: "전 인스턴스 SA 비밀번호 회전 — 모두 성공 또는 모두 원복 (미검증)"
---

# rotate-password.ps1 — SA 비밀번호 회전

> **미검증 — 이 스크립트는 실 SQL Server 환경에서 아직 한 번도 검증되지 않았습니다**([#16](https://github.com/Chigo55/Docker-Compose/issues/16)).
> 아래 설명하는 롤백(실패 시 원복)은 정적 검토만 거쳤습니다. 회전과 롤백이 모두 실패하면
> 인스턴스별 비밀번호가 `.env`와 어긋나 farm 접속이 막힙니다.

모든 인스턴스는 `.env`의 `MSSQL_SA_PASSWORD` 하나를 공유하므로, 회전은 farm 전체에 대해
**모두 성공 또는 모두 원복**으로만 처리합니다(일부만 바뀌면 `.env`와 어긋나 인증이 조용히
깨집니다). 전 인스턴스에 `ALTER LOGIN [sa]`를 적용한 뒤 `.env`를 갱신하고, 하나라도 실패하면
이미 바꾼 인스턴스를 이전 값으로 되돌립니다. 시작 전 `.env`는 `compose/.env.bak.<시각>`으로
백업됩니다.

```powershell
.\scripts\rotate-password.ps1            # 새 비밀번호를 두 번 입력받아 적용
.\scripts\rotate-password.ps1 -Generate  # 정책 충족 무작위 비밀번호 생성 후 회전
```

되돌리기 어려운 farm 전체 작업이라 `-Force`가 없으면 먼저 확인합니다. **실제 환경에 쓰기 전
테스트 환경에서 검증하세요.** 전제로 모든 인스턴스가 실행 중이어야 하며, 새 비밀번호는
정책(8자 이상 + 3종)과 금지 문자($ " \ 그리고 백틱) 검사를 통과해야 합니다
([rules/secrets.md](../../.claude/rules/secrets.md)).
