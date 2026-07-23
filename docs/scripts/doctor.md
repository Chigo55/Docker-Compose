---
summary: "기동 전 `.env`/`compose.yml` 규약 점검 (+ compose 렌더링)"
---

# doctor.ps1 — 기동 전 규약 점검

`compose/.env`와 `compose.yml`의 규약 위반을 **올리기 전에** 찾아냅니다. 한 곳이라도 어긋나면
기동이 조용히 실패하기 때문입니다.

```powershell
.\scripts\doctor.ps1
```

점검 항목: 필수 전역 키 · SA 비밀번호 정책(8자 이상 + 3종) · 인스턴스 3종 세트
(`_NAME`/`_PORT`/`_DIR`) · 포트 중복/범위 · 데이터 폴더(`_DIR`) 중복 · **`.env` 접두사 ↔
`compose.yml` 서비스 키 일치(양방향)** · `DATA_ROOT` 접근 · 값 옆 인라인 주석/역슬래시 경로 ·
(Docker 실행 중이면) `docker compose config` 렌더링 성공.

결과는 `[OK]/[경고]/[오류]`로 보여 주고, 오류가 있으면 종료 코드 1을 반환합니다(경고만 있으면 0).
처음 기동 전이나 `.env`를 크게 바꾼 뒤 실행하면 좋습니다. 저장소를 고칠 때는 [check.ps1](check.md)
이 이 점검을 자동으로 포함합니다.
