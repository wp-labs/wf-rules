# wf-rules

内网安全检测规则库 + 可直接运行的 wfusion 配置。

## 目录结构

```
wf-rules/
├── wfusion.toml              ← wfusion 配置（直接运行）
├── run.sh                    ← 一键启动：wfusion daemon + wfgen stream
├── sinks/                    ← sink 路由配置
│   ├── connectors/           ← file_json connector
│   ├── business.d/           ← 按告警类型路由（network/security/dns/http/management/insider）
│   └── infra.d/              ← default + error
├── schemas/                  ← window schema（auth/network/http/dns/management/data）
├── rules/                    ← WFL 检测规则（按 ATT&CK 分类）
├── scenarios/                ← wfgen 场景文件（待补）
├── wpl-samples/              ← WPL 数据适配样例
├── DATA_CONTRACT.md          ← 字段契约
├── README.md                 ← 规则索引
└── TODO.md                   ← 待补规则
```

## 快速运行

```bash
# 前置：wfusion 和 wfgen 在 PATH 中
bash run.sh
```

这会：
1. 启动 wfusion daemon（加载 `schemas/*.wfs` + `rules/*/*.wfl`，监听 TCP :9800）
2. 启动 wfgen stream（加载 `scenarios/*.wfg`，持续生成 Arrow 数据发送到 :9800）
3. 告警输出到 `data/alerts/*.ndjson`

## 手动运行

```bash
# 终端 1：wfusion
wfusion run --config wfusion.toml --work-dir .

# 终端 2：wfgen
wfgen stream \
  --scenario-dir scenarios/ \
  --ws schemas/network.wfs schemas/auth.wfs schemas/http.wfs schemas/dns.wfs \
  --wfl rules/*/*.wfl \
  --addr 127.0.0.1:9800
```

## 数据流

```
wfgen stream (daemon)
  → Arrow IPC 帧 → TCP :9800
  → wfusion tcp_src (arrow_framed)
  → DataSourceBatchSource → decode
  → Router → Window (conn_events / auth_events / ...)
  → WFL 规则匹配
  → alerts → sinks/business.d/*.toml → data/alerts/*.ndjson
```

## 规则 → 告警路由

| 告警窗口 | sink 配置 | 输出文件 |
|---------|-----------|---------|
| network_alerts | business.d/network.toml | data/alerts/network.ndjson |
| security_alerts | business.d/security.toml | data/alerts/security.ndjson |
| dns_alerts | business.d/dns.toml | data/alerts/dns.ndjson |
| http_alerts | business.d/http.toml | data/alerts/http.ndjson |
| management_alerts | business.d/management.toml | data/alerts/management.ndjson |
| insider_alerts | business.d/insider.toml | data/alerts/insider.ndjson |
