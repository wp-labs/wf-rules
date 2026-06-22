# 任务进展 — 2026-06-22

## 总体状态

| 环节 | 状态 |
|------|------|
| wfusion 启动 + sink 构建 | ✅ |
| wfgen → wfusion 数据流 | ✅ |
| Arrow IPC 解码 / 窗口路由 | ✅ |
| on-event 规则告警（ssh_brute）| ✅ 3000 条/30000 事件 |
| close 模式规则告警（port_scan）| ⚠️ 单元测试+集成测试通过，gen+send/stream 集成 0 告警 |

## port_scan close 模式排查

### 问题

port_scan 是 close 模式（`match<sip:20s>`, `on event ... and close ...`），应通过 `scan_timeouts`（每 1s 扫描过期实例）自然产出告警，但 gen+send / stream 集成测试中 `network.ndjson` 始终为 0。

### 已验证：代码正确

| 测试 | 验证内容 | 结果 |
|------|---------|------|
| `execute_close_yield_resolves_tracked_bind_alias_field` | CepStateMachine close → CloseOutput → execute_close → OutputRecord，yield `c.sip` 正确解析 | ✅ 232 passed |
| `port_scan_rule_triggers_close_alert` | 完整 RuleTask 管线：窗口追加 → pull_and_advance → scan_timeouts → close_all → execute_close_with_joins → emit → alert_rx | ✅ 61 passed |

### 已确认

- `scan_timeouts` 每 ~1s 正常被调用
- `scan_expired_at` 过期逻辑正确（`created_at + window_dur`，heap 比较 watermark）
- 窗口改为 20s，gen 数据跨度 60s，实例理论上应过期
- cancel token 修复：`rule_cancel.child_token()` → `cancel.child_token()`（SIGTERM 时 rule task 直接感知）

### 未解决：集成层 0 告警

| 测试方式 | 二进制 | 规则 | 结果 |
|---------|--------|------|------|
| gen+send | release/debug, clean build | port_scan-only | 0 alert |
| stream | release | 全部规则 | 0 alert |

**可能原因（未验证）：**
- Arrow IPC 中 `event_time`（1.78×10^18）在 `Value::Number(f64)` 下精度丢失约 208ns
- `wfgen send` 单大帧 vs `wfgen stream` 分块处理路径差异
- wp-reactor 路径依赖增量编译缓存导致二进制未更新

### 下一步

1. 排查 Arrow IPC 的 `event_time` 精度丢失（对比 stream 分块）
2. 或用 `wfgen stream --interval 5` 跑足窗口时长来验证
3. 以单元测试+集成测试结果为信心基准，接受代码正确性

---

## 后续低优先 TODO

- **方案 B：只收集被引用的字段**。当前 `collect_alias_event`/`collect_event_fields` 仍对每个事件全字段累积（仅加了条数封顶）。彻底解是从 plan 预算出每 step/alias 实际被 yield/L3 引用的字段名，只收这些。收益：内存再降数量级。代价：要扩 MatchPlan 结构、改 `collect_*` 签名、动多个手搓 plan 的测试。
- **`collected_values` 同款无界增长**。`update_measure` 里 `bs.collected_values.push(val)` 每事件累加。可复用 `push_capped`。
- **blackhole sink 注册**。`BlackHoleFactory` 已存在于 `wp-core-connectors`，`wfusion/register.rs::register_connectors()` 未注册。
- **`derive_legacy_injects` 保留 entity 聚类**。新语法 injection 转旧语法时 `SeqBlock.entity` 信息丢失。

---

## 关键路径

| 项目 | 路径 |
|------|------|
| wf-rules | `wf-rules/` |
| warp-fusion | `warp-fusion/` |
| wp-reactor | `wp-reactor/` |
| wfusion binary | `~/bin/wfusion`（从 `warp-fusion/target/release/wfusion` copy）|

---

## 快速测试

```bash
cd wf-rules

# 重建（改 wp-reactor 后必须）
cd ../warp-fusion && cargo build --release && cp target/release/wfusion ~/bin/wfusion && cd ../wf-rules

# on-event 验证（ssh_brute，秒级出告警）
pkill -9 -f wfusion; rm -f data/alerts/* data/wfusion.log
wfusion run --config test/wfusion.toml --work-dir . &
sleep 3
wfgen send --scenario scenarios/ssh_brute_quick.wfg \
  --input <regenerated>.jsonl --ws schemas/auth.wfs --addr 127.0.0.1:9800
sleep 15
wc -l data/alerts/security.ndjson  # 期望 3000
```
