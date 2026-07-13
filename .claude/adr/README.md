# 아키텍처 결정 기록 (ADR)

이 폴더는 MSSQL Farm 저장소의 **아키텍처 결정 기록(Architecture Decision Records)** 을 담습니다.
각 파일은 "왜 이렇게 만들었는가"를 하나씩 기록합니다. 코드만 봐서는 의도를 놓치기 쉬운
설계 판단을, 배경(Context) · 결정(Decision) · 결과(Consequences)로 나눠 남깁니다.

> ADR 은 한 번 확정되면 **수정하지 않고, 뒤집을 때 새 ADR 로 대체(Superseded)** 하는 것이 관례입니다.
> 새 결정을 내렸다면 기존 파일을 지우지 말고 상태를 `Superseded by ADR-XXXX` 로 바꾸세요.

## 형식

각 ADR 은 다음 구조를 따릅니다.

```
# ADR-NNNN: 제목
- 상태: Accepted | Superseded | Deprecated
- 관련: 함께 읽을 ADR / 파일

## 배경 (Context)   무엇이 문제였는가
## 결정 (Decision)  무엇을 하기로 했는가
## 결과 (Consequences)  그래서 무엇이 좋아지고 무엇을 감수하는가
```

## 목록

| # | 제목 | 요약 |
|---|------|------|
| [0001](0001-env-single-source-of-truth.md) | `.env`가 유일한 설정 소스 | compose.yml 은 구조만, 값은 전부 `.env` |
| [0002](0002-instance-autodiscovery.md) | 인스턴스 자동 발견 | `<PREFIX>_PORT` 스캔으로 인스턴스 목록을 도출 |
| [0003](0003-yaml-anchors-for-reuse.md) | YAML 앵커로 공통 정의 재사용 | `x-base`/`x-mssql-2019`/`x-mssql-2022` |
| [0004](0004-host-bind-mount-for-data.md) | 데이터는 호스트 바인드 마운트 | 컨테이너를 지워도 DB 보존 |
| [0005](0005-engine-based-backup.md) | 엔진 백업(BACKUP DATABASE)만 사용 | `.mdf` 직접 복사 금지 |
| [0006](0006-sqlcmd-version-autodetect.md) | sqlcmd 경로 런타임 자동 판별 | 2019/2022 경로 차이를 `test -x`로 흡수 |
| [0007](0007-shared-common-library.md) | 공용 라이브러리 `_common.ps1` dot-source | 자동 발견/헬퍼 재사용, 하드코딩 금지 |
| [0008](0008-explicit-compose-file-flags.md) | compose 호출 시 `-f`/`--env-file` 항상 명시 | 어느 폴더에서 실행해도 동일 동작 |
| [0009](0009-password-via-env-var.md) | 비밀번호를 `SQLCMDPASSWORD` 환경변수로 전달 | 셸 인용/특수문자 문제 회피 |
| [0010](0010-preflight-validation-doctor.md) | 기동 전 규약 점검 `doctor.ps1` | 조용한 기동 실패를 사전 차단 |
| [0011](0011-batch-continue-on-error.md) | 배치는 continue-on-error + 요약 + `exit 1` | 스케줄러가 실패 감지 |
| [0012](0012-utf8-bom-for-powershell.md) | `.ps1`은 UTF-8 BOM, docker 파일은 BOM 없음 | PS 5.1 한글 인코딩 사고 방지 |
| [0013](0013-plaintext-password-gitignored.md) | 평문 비밀번호 `.env`는 Git 제외, 견본만 공유 | `.env.example` 커밋 |
