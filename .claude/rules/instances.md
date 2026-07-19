---
summary: "인스턴스 추가/변경(3종 세트) · 선택 항목 양쪽 켜기"
---

# 인스턴스 추가/변경 · 선택 항목

## 인스턴스 추가/변경 (규약의 핵심)

한 인스턴스 = 접두사가 같은 **3종 세트**다([ADR-0002](../adr/0002-instance-autodiscovery.md)).

- 추가 시: **`compose/.env`에 3줄**(`<PREFIX>_NAME` / `<PREFIX>_PORT` / `<PREFIX>_DIR`) +
  **`compose/compose.yml`에 서비스 블록**(`<<: *mssql2019` 또는 `*mssql2022` 병합).
- **서비스키 = `<PREFIX>`.ToLower()** 이고, `compose.yml`의 서비스 키와 **반드시 일치**해야 한다.
- **스크립트는 손대지 않는다.** 인스턴스 목록은 `.env` 스캔으로 자동 발견된다.
- 호스트 포트는 인스턴스마다 유일해야 하고, `_DIR`(데이터 폴더)도 인스턴스끼리 공유 금지.
- 컨테이너명(`_NAME`)과 폴더명(`_DIR`)은 **다르게 둘 수 있다**(예: 이관 시 `_DIR=Db2019A-old`).
  기존 DB 경로 호환을 위한 것이니 **임의로 통일하지 말 것**.

## 선택 항목은 양쪽을 함께 켠다

`MSSQL_MEMORY_LIMIT_MB`, `MSSQL_AGENT_ENABLED`는 선택 항목이다. 쓰려면 **`compose/.env`와
`compose/compose.yml`의 대응 줄을 둘 다 주석 해제**해야 한다. 한쪽만 풀면 빈 값이 넘어가
컨테이너가 기동에 실패한다.
