---
summary: "ports·volumes·networks 를 확장 문법으로"
---

# ADR-0023: compose.yml 은 Compose v2 확장 문법(long syntax)으로 쓴다

- 상태: Accepted
- 관련: [ADR-0001](0001-env-single-source-of-truth.md), [ADR-0003](0003-yaml-anchors-for-reuse.md), [ADR-0004](0004-host-bind-mount-for-data.md), `compose/compose.yml`

## 배경 (Context)

`compose.yml` 의 `ports`·`volumes`·`networks` 를 단축 문법(short syntax)으로 쓰고 있었다.

```yaml
ports: ["${DB2019A_PORT}:${MSSQL_PORT:-1433}"]
volumes:
  - "${DATA_ROOT}/${DB2019A_DIR}/data:/var/opt/mssql/data"
networks: [mssql]
```

콜론으로 이어 붙인 한 줄은 **순서를 외워야** 읽힌다("호스트:컨테이너" — 뒤집으면 조용히
엉뚱한 포트가 열린다). 이 저장소는 인스턴스 8개가 같은 모양을 반복하고, 인스턴스 추가는
기존 블록을 복사해 접두사만 바꾸는 작업이라 그 실수가 그대로 복제된다. 값이 `.env`
변수로 가려져 있어 눈으로 검산하기도 어렵다.

또 하나. 단축 문법의 문자열은 **YAML 단계에서는 그냥 문자열**이라, 오타가 나면 compose 가
파싱 단계가 아니라 기동 단계에서야 문제를 드러낸다.

## 결정 (Decision)

`ports`·`volumes`·`networks` 를 **확장 문법**으로 쓴다. 필드 이름을 모두 드러낸다.

```yaml
ports:
  - target: ${MSSQL_PORT:-1433}     # 컨테이너 안쪽
    published: "${DB2019A_PORT}"    # 호스트 쪽
    protocol: tcp
    mode: ingress
volumes:
  - type: bind
    source: "${DATA_ROOT}/${DB2019A_DIR}/data"
    target: /var/opt/mssql/data
    bind:
      create_host_path: true
networks:
  mssql: {}
```

- `mode: ingress`·`create_host_path: true` 는 **단축 문법의 기본값을 그대로 적은 것**이다.
  실제로 `docker compose config` 렌더링 결과가 전환 전후 동일하다(네트워크가 `null` 대신
  `{}` 로 찍히는 표기 차이만 남는다). 즉 이 ADR 은 **동작을 바꾸지 않는 표기 전환**이다.
- `environment`·`healthcheck.test`·`logging` 은 이미 확장 형태(매핑·배열)라 그대로 둔다.
- 앵커 재사용([ADR-0003](0003-yaml-anchors-for-reuse.md))은 유지한다. 공통 `networks`·`logging` 도 앵커
  (`x-networks`·`x-logging`)로 뽑아 `x-base` 가 참조한다.
- `bind.create_host_path: true` 를 적었다고 해서 폴더 생성을 Docker 에 맡기는 것은 아니다.
  기동 전 폴더 생성은 여전히 `start.ps1` 의 책임이다([ADR-0004](0004-host-bind-mount-for-data.md)) — Docker 가 빈
  폴더를 먼저 만들면 기존 DB 를 못 붙는다.

## 결과 (Consequences)

- **좋은 점**: 각 값이 이름으로 드러나 "호스트:컨테이너" 순서를 외울 필요가 없다.
  포트를 뒤집는 실수가 복사·붙여넣기로 번지지 않는다.
- **좋은 점**: 오타(`targt:` 등)가 compose 스키마 검증에 걸려 `doctor.ps1` 의
  `docker compose config` 단계에서 잡힌다. 기동까지 가지 않는다.
- **좋은 점**: 나중에 `read_only`·`host_ip`·네트워크 `aliases` 를 붙일 때 구조를 바꾸지 않고
  키만 추가하면 된다.
- **감수할 점**: 서비스 블록이 4줄에서 10여 줄로 길어졌다([ADR-0003](0003-yaml-anchors-for-reuse.md)의 "짧은 서비스
  블록"은 이만큼 후퇴한다). 대신 파일 상단 안내 주석에 단축↔확장 대조표를 두어 보완한다.
- **감수할 점**: 인터넷의 예제 대부분이 단축 문법이라, 복사해 온 조각을 이 파일 형식으로
  옮겨 적어야 한다. 인스턴스 추가는 **기존 서비스 블록을 복사**하는 것이 가장 안전하다.
