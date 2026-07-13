# 로드맵 — 추가하면 좋을 기능

현재 `scripts/`는 라이프사이클(start/stop/restart/down), 관찰(status/logs),
데이터(backup/restore), 실행(query), 점검(doctor)을 갖췄고, 저장소 편집용 내부 개발
루프(check/test — 린트 + 단위 테스트)도 있습니다. 이 문서는 **다음에 무엇을 추가하면
운영이 편해지는가**를 우선순위와 함께 정리한 것입니다.

- 모든 제안은 기존 설계 원칙(`.env` 단일 소스, `_common.ps1` 재사용, 자동 발견,
  UTF-8 BOM, 한국어 컬러 출력, 배치 실패 패턴)을 따르는 것을 전제로 합니다.
- **노력도**: S(반나절) / M(1~2일) / L(3일+)
- 이 문서는 계획이며 확정이 아닙니다. 실제 착수 시 우선순위는 조정될 수 있습니다.

---

## 현재 구현 상태

| 스크립트 | 역할 | 상태 |
|---|---|---|
| start / stop / restart / down | 컨테이너 라이프사이클 | ✅ |
| status / logs | 상태·로그 관찰 | ✅ |
| query | 다중 인스턴스 T-SQL 실행 | ✅ (v1.0) |
| backup / restore | DB 백업·복원 | ✅ (restore v1.0) |
| doctor | 기동 전 규약 점검 | ✅ (v1.0) |
| `_common.ps1` | 공용 함수 (자동 발견, `Invoke-Sql` 등) | ✅ |
| check / test | 내부 개발 루프 (린트 + 단위 테스트) | ✅ (P3-9 일부) |

---

## P1 — 운영에서 가장 먼저 아쉬워지는 것

### 1. `start.ps1 -Wait` (또는 `wait.ps1`) — healthy 대기
**문제**: 지금은 기동 후 "healthy까지 30~60초"라고 안내만 합니다. 스케줄러·CI·연쇄
스크립트에서 "기동이 실제로 끝났는지"를 알 수 없어, 임의의 `Start-Sleep`에 의존하게 됩니다.

**가치**: `docker inspect`의 Health.Status를 폴링해 전부 healthy가 될 때까지 대기(타임아웃 포함).
무인 자동화의 신뢰성이 올라갑니다.

```powershell
.\scripts\start.ps1 -Pull -Wait -Timeout 120
```

- **재사용**: `Get-TargetInstances`, `Test-ContainerRunning`. `_common.ps1`에 `Wait-Healthy` 헬퍼 추가 후 status.ps1도 공유.
- **노력도**: S

### 2. `databases.ps1` — DB 인벤토리
**문제**: 어느 인스턴스에 어떤 DB가 있고 크기/복구모델/마지막 백업이 언제인지 한눈에 볼 방법이 없습니다.
(백업 대상 파악, 용량 계획에 필수)

**가치**: 인스턴스별 DB 목록 + 데이터/로그 크기 + 복구 모델 + 최근 백업 시각을 한 표로.

```powershell
.\scripts\databases.ps1                       # 전체 인스턴스의 DB 인벤토리
.\scripts\databases.ps1 -Service db2019c
.\scripts\databases.ps1 -Database MyDb        # 특정 DB가 어느 인스턴스에 있는지
```

- **재사용**: `Invoke-Sql -Separator '|'`로 `sys.databases` + `backupset` 조인 결과 파싱. `Get-TargetInstances`.
- **노력도**: M

### 3. `shell.ps1` — 대화형 sqlcmd 세션
**문제**: 임시 확인·수정을 하려면 매번 긴 `docker exec ... sqlcmd -S ... -U sa -P ...`를 칩니다.

**가치**: 서비스 키 하나로 해당 인스턴스에 대화형 sqlcmd 세션을 바로 엽니다(버전 자동 판별, 비밀번호 자동 주입).

```powershell
.\scripts\shell.ps1 -Service db2019c
.\scripts\shell.ps1 -Service db2022b -Database MyDb
```

- **재사용**: `Get-SqlcmdInvocation`(버전 판별), `Read-DotEnv`(비밀번호). `docker exec -it`.
- **노력도**: S

---

## P2 — 데이터 수명주기 확장

### 4. `backup.ps1 -Type Diff|Log` — 차등/로그 백업
**문제**: 현재는 전체 백업만 지원합니다. 큰 DB에서 매번 전체 백업은 시간·용량 부담이 크고,
장애 시 복구 지점(RPO)을 분 단위로 줄일 수 없습니다.

**가치**: 전체(주기적) + 차등(일) + 로그(분·시) 조합으로 표준 복구 전략을 완성합니다.
restore.ps1도 체인 복원(전체→차등→로그)을 지원하도록 확장.

```powershell
.\scripts\backup.ps1 -Database MyDb -Type Full
.\scripts\backup.ps1 -Database MyDb -Type Diff
.\scripts\backup.ps1 -Database MyDb -Type Log
```

- **재사용**: 기존 backup.ps1 골격. `BACKUP DATABASE ... WITH DIFFERENTIAL` / `BACKUP LOG`.
- **주의**: 로그 백업은 복구 모델이 FULL이어야 의미가 있습니다(SIMPLE이면 스킵/경고). 파일 확장자 규약(`.bak`/`.dif`/`.trn`) 정리 필요.
- **노력도**: M~L (restore 체인 포함 시 L)

### 5. `copy-db.ps1` — 인스턴스 간 DB 복제
**문제**: "운영 DB를 스테이징 인스턴스로 복사" 같은 작업을 수동 backup+copy+restore로 해야 합니다.

**가치**: 한 번의 명령으로 A 인스턴스의 DB를 B 인스턴스로 이관(선택적으로 다른 이름으로).

```powershell
.\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb
.\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb -AsDatabase MyDb_staging
```

- **재사용**: backup.ps1 + restore.ps1을 그대로 조합(백업→docker cp→restore). `-AsDatabase`는 restore.ps1에 옵션 추가로 재활용.
- **노력도**: M

### 6. `update.ps1` — 이미지 롤링 업데이트
**문제**: 이미지 태그를 올릴 때 `restart -Recreate`는 전체를 한꺼번에 내렸다 올립니다.
farm 전체가 동시에 잠깐 내려가고, 하나가 실패해도 감지가 늦습니다.

**가치**: 인스턴스를 **하나씩** pull→recreate→healthy 확인 후 다음으로 넘어가는 롤링 업데이트.
실패하면 그 지점에서 멈추고 요약.

```powershell
.\scripts\update.ps1                     # 전체 롤링
.\scripts\update.ps1 -Service db2022a,db2022b
```

- **재사용**: `Invoke-Compose`, `Wait-Healthy`(P1-1과 공유), 배치 실패 패턴.
- **노력도**: M

---

## P3 — 보안 · 품질 · 관측

### 7. `rotate-password.ps1` — SA 비밀번호 회전
**문제**: SA 비밀번호는 `.env`에 평문이며 회전 절차가 수동입니다(글로벌 보안 규칙 위반 소지).

**가치**: `ALTER LOGIN [sa] WITH PASSWORD`를 전 인스턴스에 적용하고 `.env`도 함께 갱신(백업본 남김).

```powershell
.\scripts\rotate-password.ps1                 # 새 비밀번호 입력 프롬프트
.\scripts\rotate-password.ps1 -Generate       # 정책 충족 무작위 생성
```

- **재사용**: `Invoke-Sql`, `Read-DotEnv`. `.env` 재작성 유틸 신설 필요.
- **주의**: 회전 중 실패하면 인스턴스별로 비밀번호가 갈릴 수 있음 → 롤백/재시도 설계 필수. 되돌리기 어려운 작업이므로 확인 프롬프트 + 이전 값 백업.
- **노력도**: M

### 8. 로그 · secrets 볼륨 마운트 (compose.yml 옵션)
**문제**: 현재 `data`만 마운트라 errorlog(`/var/opt/mssql/log`)·인증서(`/var/opt/mssql/secrets`)가
컨테이너와 함께 사라집니다(README 운영 메모 참고).

**가치**: 선택적 볼륨 마운트로 errorlog·인증서를 호스트에 보존(장애 사후 분석).
기존 `MSSQL_MEMORY_LIMIT_MB`처럼 `.env`+`compose.yml` 대응 줄을 함께 주석 해제하는 방식.

- **재사용**: 앵커(`x-base`)에 볼륨 추가 패턴. `start.ps1`의 폴더 자동 생성 로직 확장.
- **노력도**: S

### 9. 테스트 · 린트 · CI 파이프라인  — 🟡 로컬 부분 완료, CI 남음
**문제**: 스크립트가 늘면서 회귀 위험이 커집니다.

**진행 상황**:
- ✅ **Pester** — `_common.ps1` 순수 함수 단위 테스트(`Read-DotEnv` 파싱, `Get-Instances` 발견,
  `Resolve-Services` 오타 검증). `tests/_common.Tests.ps1` + `scripts/test.ps1`. Pester 5+ 필요.
  (설정 주입은 `$script:DotEnvCache`에 사전을 직접 넣는 방식이라, 사전 리팩터 없이 순수 로직을 테스트합니다.)
- ✅ **PSScriptAnalyzer** — `scripts/check.ps1`이 정적 분석 실행(저장소 관례와 충돌하는 규칙은 제외).
- ✅ **로컬 통합 루프** — `check.ps1 -Test`(+`-Watch`)로 린트 + doctor + 테스트를 한 번에.
- ⬜ **GitHub Actions** — 남은 작업. PR마다 windows-latest 러너에서 `check.ps1 -Test`(Docker 불필요 부분) 실행.

```
.github/workflows/ci.yml   # windows-latest 러너에서 .\scripts\check.ps1 -Test -Install
tests/_common.Tests.ps1    # ✅ 이미 있음
```

- **주의**: Docker가 필요한 부분(백업/복원 실동작)은 CI에서 검증이 어렵습니다. 현재 테스트는 그 경계를
  피해 순수 로직만 다룹니다. 실동작 검증까지 넓히려면 I/O 분리 리팩터가 선행되면 좋습니다.
- **남은 노력도**: S (CI 워크플로 파일 1개)

### 10. `report.ps1` / 백업 결과 알림
**문제**: 무인 운영(야간 백업 등)에서 결과를 사람이 능동적으로 봐야 합니다.

**가치**:
- `report.ps1`: 전체 farm 상태(status + DB 인벤토리 + 최근 백업)를 HTML 리포트로 저장.
- 백업/복원 실패 시 webhook(Teams/Slack) 또는 메일 알림.

```powershell
.\scripts\report.ps1 -OutFile C:\docker\_report\farm.html
.\scripts\backup.ps1 -Database MyDb -NotifyWebhook $env:TEAMS_WEBHOOK
```

- **재사용**: status/databases의 수집 로직. `ConvertTo-Html`, `Invoke-RestMethod`.
- **노력도**: M

---

## 범위 밖 (의도적으로 제외)

이 저장소의 성격(단일 호스트 · Docker Compose · 소규모 farm)에 맞지 않아 **당분간 넣지 않는** 것들입니다.

| 항목 | 제외 이유 |
|---|---|
| Prometheus/Grafana 풀 모니터링 스택 | 인스턴스 수 대비 과함. 필요 시 `report.ps1`로 충분 |
| Always On 가용성 그룹 · 복제 | 단일 호스트 · Developer 에디션에 부적합 |
| Kubernetes/Helm 이관 | Compose 단순성 철학과 상충. 별도 프로젝트로 분리하는 편이 나음 |
| `.env` 암호화/Vault 연동 | 현재 위협 모델(로컬 운영 + `.gitignore` 제외)에는 과함. 팀 공유가 늘면 재검토 |

---

## 다음 액션 제안

착수 순서는 **P1-1 (`-Wait`) → P1-3 (`shell.ps1`) → P1-2 (`databases.ps1`)**를 권장합니다.
셋 다 노력도가 낮고(`_common.ps1` 재사용), 나머지 P2/P3 기능들이 이 위에 얹혀 가치가 커지기 때문입니다.
특히 `Wait-Healthy` 헬퍼(P1-1)는 `update.ps1`(P2-6)의 전제가 되므로 먼저 만들어 두면 좋습니다.
