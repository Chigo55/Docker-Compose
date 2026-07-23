---
summary: "같은 T-SQL 을 여러 인스턴스에 일괄 실행하고 결과를 모아 표시"
---

# query.ps1 — 여러 인스턴스에 T-SQL 일괄 실행

인스턴스가 여러 개인 farm에서 "전부에 같은 질의"(버전 확인, DB 목록, 설정 점검)를 한 번에
실행합니다. `_common.ps1`의 `Invoke-Sql`을 그대로 씁니다.

```powershell
.\scripts\query.ps1 "SELECT @@VERSION"                                    # 전체 인스턴스 버전
.\scripts\query.ps1 "SELECT name FROM sys.databases ORDER BY name" -Service db2019c
.\scripts\query.ps1 -File .\scripts\sql\health.sql                        # 파일에서 읽어 실행
.\scripts\query.ps1 "SELECT COUNT(*) FROM dbo.Orders" -Database MyDb -Service db2022a,db2022b
```

읽기 쿼리에 권장합니다. 데이터를 바꾸는 문장(`UPDATE`/`DROP` 등)도 실행되므로, 전체 대상으로
파괴적 쿼리를 돌릴 때는 `-Service`로 범위를 좁히세요. 꺼진 인스턴스는 `DOWN`으로 표시되고,
하나라도 성공하지 못하면 종료 코드 1을 반환합니다.

한 인스턴스에서 이것저것 대화형으로 확인할 때는 [shell.ps1](shell.md) 이 편합니다.
