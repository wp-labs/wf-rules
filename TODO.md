# wf-rules TODO — 待补检测规则

已落库的 8 条规则见 [README.md](README.md)。以下为待补充的检测场景，按优先级排列。每条给出建议的 WFL 模式与数据源，便于后续实现。

## P1 — 高价值，建议优先补

### 1. 06-credential_abuse/pass_the_hash.wfl ✅ 已实现
- **检测**：Pass-the-Hash / Pass-the-Ticket 横向认证（Windows 4624 logon type 3 + 异常来源）
- **模式**：`match<sip:10m>` + `distinct dip >= 3` + `logon_type == 3` + `result == "success"`
- **数据源**：auth_events（已扩 `logon_type` 字段）
- **状态**：已落库 | `wfl lint` 通过

### 2. 06-credential_abuse/privileged_anomaly.wfl ✅ 已实现
- **检测**：特权账户（Domain Admin）异常登录到非授权主机
- **模式**：`on each e where external("privileged_users", e.user) && !external("authorized_hosts", ...)`
- **数据源**：auth + Redis（privileged_users / authorized_hosts）
- **状态**：已落库 | `wfl lint` 通过

### 3. 04-c2/dns_tunneling.wfl ✅ 已实现
- **检测**：DNS 隧道（TXT 查询高频）
- **模式**：`match<sip:5m>` + TXT query count ≥ 10
- **数据源**：dns_events
- **状态**：已落库 | `wfl lint` 通过

### 4. 04-c2/dga_domain.wfl ✅ 已实现
- **检测**：DGA / 新注册 / 低信誉域名解析
- **模式**：`on each d where external("domain_reputation", d.query)` 点查威胁情报
- **数据源**：dns_events + Redis
- **状态**：已落库 | `wfl lint` 通过

## P2 — 中价值

### 5. 08-persistence/new_account.wfl ✅ 已实现
- **检测**：新建账户 / 隐藏账户（`$` 结尾）、被加入特权组（4728/4732/4756）
- **模式**：`match<sip:5m>` + AD 审计事件 count ≥ 2
- **数据源**：`management.wfs` — `ad_change_events` 流
- **状态**：已落库 | `wfl lint` 通过

### 6. 08-persistence/scheduled_task.wfl ✅ 已实现
- **检测**：可疑计划任务/服务/启动项创建（持久化）
- **模式**：`match<sip:5m>` + 进程创建事件 count ≥ 1
- **数据源**：`management.wfs` — `process_events` 流
- **状态**：已落库 | `wfl lint` 通过

### 7. 09-insider/data_bulk_export.wfl ✅ 已实现
- **检测**：DB 批量查询 / 文件服务器批量下载（内部滥用）
- **模式**：`match<user:5m>` + `sum(row_count) >= 100000` + `sum(bytes_out) >= 50MB`
- **数据源**：`data.wfs` — `data_access_events` 流
- **状态**：已落库 | `wfl lint` 通过

### 8. 09-insider/off_hours_activity.wfl ✅ 已实现
- **检测**：非工作时间认证/操作
- **模式**：`on each e where external("is_off_hours", e.event_time)` 点查
- **数据源**：auth_events + Redis
- **状态**：已落库 | `wfl lint` 通过

## P3 — 现有规则的精确化

### 9. 04-c2/beaconing 精确化
- 现状：用"高频短小连接"近似
- 改进：wparse/ETL 侧算 `beacon_score`（间隔方差 + 包长方差），规则改 `on each c where c.beacon_score > 0.8`
- 依赖：conn_events 加 `beacon_score` 字段（wparse 侧聚合）

### 10. 05-exfiltration/data_upload 精确化
- 现状：用"大流量连接次数"近似
- 改进：`match<sip:5m> { on event { c.bytes_out | sum >= 100000000 } }`（确认 WFL `sum` 语法）
- 或：ETL 侧算 5min 滚动 `out_bytes_total`，规则阈值判定

### 11. 03-lateral_movement/first_seen_relationship.wfl ✅ 已实现
- **检测**：历史未见的 (sip, dip) 通信（图基线首现）
- **模式**：`on each c where !external("first_seen", fmt("{}-{}", c.sip, c.dip))` 点查 Bloom filter
- **数据源**：conn_events + Redis Bloom filter
- **状态**：已落库 | `wfl lint` 通过

## 实现约定
- 新规则放对应分类目录，文件名小写下划线。
- 每条规则必须含 `limits { ... }` 块（v2.1 要求）。
- `wfl lint <rule> -s "schemas/*.wfs"` 通过为验收标准。
- 需要新事件字段的，先扩 `schemas/` 对应 `.wfs`。
- 依赖 external() 的，README 注明 knowdb.toml `[fun.*]` 配置。
