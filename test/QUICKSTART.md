# wf-rules

内网安全检测规则库 + 可直接运行的 wfusion 配置。

## 目录结构

```
wf-rules/
├── wfusion.toml              ← wfusion 配置（直接运行）
├── smoke.sh                  ← 一键可用性检查：wfgen gen + wfusion batch + alert 断言
├── run.sh                    ← TCP daemon 联调：wfusion daemon + wfgen stream
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

## 可用性检查

```bash
# 前置：wfusion 和 wfgen 在 PATH 中
test/smoke.sh
```

这会：
1. lint `scenarios/port_scan_quick.wfg`
2. 生成 `data/generated/port_scan_quick.jsonl`
3. 用 `test/wfusion.batch.toml` batch 回放数据
4. 断言 `data/alerts/network.ndjson` 非空，且告警数与 oracle 一致

当前激活规则集只包含 `rules/01-recon/port_scan.wfl`，因此 smoke test 的期望输出是 `network.ndjson`。

## TCP daemon 联调

该路径需要在普通终端或非沙箱权限下运行。受限命令沙箱可能无法保持本地 TCP listener，表现为 `wfgen send` 连接 `127.0.0.1:9800` 失败。

```bash
# 默认运行 5 分钟，到时自动停止并输出 alert 统计
test/run.sh

# 指定运行时间
test/run.sh 60s
test/run.sh 10m

# 或用环境变量
DURATION=30s INTERVAL=5 RATE_SLEEP=200 test/run.sh
```

运行日志写入：

- `data/logs/wfusion.log`
- `data/logs/wfgen.log`

如果 `wfusion` 或 `wfgen stream` 提前退出，脚本会停止另一侧进程并打印对应日志尾部，避免长时间挂住。

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
