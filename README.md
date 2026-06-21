# wf-rules — 内网安全检测规则库

按 ATT&CK 攻击链分类的 WarpFusion (WFL) 检测规则。覆盖内网常见安全事件，每条规则均可独立 `wfl lint` / `wfusion run`。

## 规则索引

| 分类 | 规则 | 检测事件 | 模式 | 数据源 | 阈值 |
|------|------|---------|------|--------|------|
| 01-recon | port_scan | 端口/服务扫描 | `match<sip>` + `distinct dport` count | netflow | ≥10 端口/5min |
| 02-initial_access | ssh_brute_force | SSH 暴力破解 | `match<sip>` + count failed | auth | ≥10 失败/5min |
| 02-initial_access | weak_password_redis | 弱口令/泄露凭据登录 | `on each where external()` 点查 Redis | auth + Redis | 命中即告警 |
| 02-initial_access | password_spraying | 凭据喷射 | `match<password_hash>` + `distinct user` count | auth | ≥5 用户/5min |
| 03-lateral_movement | lateral_spread | 横向移动扩散 | `match<sip>` + `distinct dip` (远程管理端口) | netflow | ≥5 主机/5min |
| 03-lateral_movement | first_seen_relationship | 首次通信关系 | `on each where !external()` 点查 Bloom filter | netflow + Redis | 首次即告警 |
| 04-c2 | beaconing | C2 信标（近似） | `match<sip,dip>` + 短小连接 count | netflow | ≥20 次/10min |
| 04-c2 | dns_tunneling | DNS 隧道 | `match<sip>` + TXT 查询 count | dns | ≥10 次/5min |
| 04-c2 | dga_domain | DGA/新注册域名 | `on each where external()` 威胁情报点查 | dns + Redis | 命中即告警 |
| 05-exfiltration | data_upload | 数据外发 | `match<sip>` + 大流量连接 count | netflow | ≥5 次(>10MB)/5min |
| 06-credential_abuse | pass_the_hash | Pass-the-Hash 横向 | `match<sip>` + `distinct dip` (logon_type=3) | auth | ≥3 主机/10min |
| 06-credential_abuse | privileged_anomaly | 特权账户异常 | `on each where external()` 白名单点查 | auth + Redis | 命中即告警 |
| 07-chains | scan_login_xfer | 攻击链 扫描→登录→外传 | 多别名多步 `match<sip,dip>` | netflow+auth | 三步全中 |
| 08-persistence | new_account | 新建账户/特权提升 | `match<sip>` + AD 审计 count | ad_audit | ≥2 次/5min |
| 08-persistence | scheduled_task | 可疑计划任务/持久化 | `match<sip>` + 进程创建 count | process | ≥1 次/5min |
| 09-insider | off_hours_activity | 非工作时间活动 | `on each where external()` 时间点查 | auth + Redis | 命中即告警 |
| 09-insider | data_bulk_export | 批量数据导出 | `match<user>` + `sum` 行数/字节 | data | ≥100K rows/5min |

## 目录结构

```
wf-rules/
├── README.md
├── schemas/                       # 共享 schema（按数据域）
│   ├── network.wfs                # conn_events / network_alerts
│   ├── auth.wfs                   # auth_events / security_alerts
│   ├── http.wfs                   # http_events / http_alerts
│   └── dns.wfs                    # dns_events / dns_alerts
├── 01-recon/                      # 侦察
├── 02-initial_access/             # 初始访问
├── 03-lateral_movement/           # 横向移动
├── 04-c2/                         # 命令与控制
├── 05-exfiltration/               # 数据外发
├── 06-credential_abuse/           # 凭据滥用（待补）
└── 07-chains/                     # 多步攻击链
```

## 用法

```bash
# 单规则 lint
wfl lint 01-recon/port_scan.wfl -s "schemas/*.wfs"

# 单规则 explain（查看编译后的匹配计划）
wfl explain 02-initial_access/ssh_brute_force.wfl -s "schemas/*.wfs"

# 全量 lint
for r in */*.wfl; do wfl lint "$r" -s "schemas/*.wfs"; done
```

规则文件用 `use "network.wfs"` / `use "auth.wfs"` 声明依赖的 schema，`-s "schemas/*.wfs"` 提供 schema 文件。

## WFL 规则模式速查

| 模式 | 适用场景 | 示例 |
|------|---------|------|
| `match<key:win> { on event { e \| count >= N } }` | 单事件频率阈值 | ssh_brute_force |
| `match<key:win> { on event { e.field \| distinct \| count >= N } }` | 去重计数 | port_scan / lateral_spread / password_spraying |
| `on each e where external("svc", e.field)` | 逐条外部点查（Redis 等） | weak_password_redis |
| 多别名 `match<key:win> { on event { a\|count>=1; b\|count>=1; c\|count>=1 } }` | 多步序列 | scan_login_xfer |
| `join <window> snapshot on ...` | 全量富化（小规模） | （见 examples/weak_password） |
| `join <window> anti on ...` | 白名单排除 | （见 examples/port_scan_whitelist） |

## 数据源字段约定

**conn_events**（netflow）：`sip, dip, dport, bytes, bytes_in, bytes_out, protocol, action, duration, event_time`
**auth_events**：`sip, dip, dport, service, user, password_hash, result, event_time`
**http_events**：`sip, dip, method, uri, status, bytes_out, user_agent, event_time`
**dns_events**：`sip, query, qtype, rcode, response, bytes, event_time`

实际接入时按 wparse 的 wpl 解析产出对应字段；字段名需与 schema 一致。

## 备注

- **C2 信标**：本库用"高频短小连接"近似；精确周期性检测（固定间隔/低方差）建议在 wparse/ETL 侧算 `beacon_score` 后用 `on each where beacon_score > threshold` 判定。
- **数据外发**：用"大流量连接次数"近似；精确字节总量需 `sum` 聚合（WFL 支持，按需展开）。
- **weak_password_redis** 依赖 Redis：`knowdb.toml` 配 `[fun.password_check] call=sismember key=weak_passwords`，见 `examples/weak_password2`。
- **待补规则**：见 [TODO.md](TODO.md) —— 06-credential_abuse（PtH / 特权异常）、DNS 隧道 / DGA、持久化（新账户 / 计划任务）、内部滥用、以及现有 C2 / 外发规则的精确化。
