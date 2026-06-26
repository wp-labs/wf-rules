# 任务进展 — 2026-06-26

## 总体状态

| 环节 | 状态 |
|------|------|
| wfusion 启动 + sink 构建 | ✅ |
| wfgen → wfusion 数据流 | ✅ |
| Arrow IPC 解码 / 窗口路由 | ✅ |
| on-event 规则告警（ssh_brute）| ✅ 3000 条/30000 事件 |
| close 模式规则告警（port_scan）| ✅ quick/batch: 450 alerts；gen+send TCP: 450 alerts |
| wfadm init（project 脚手架）| ✅ rules/conf/normal 三种 scope 测试通过 |

---

## wfadm 状态

| 命令 | 状态 |
|------|------|
| `wfadm init` | ✅ 从 `docker/default_setting/` 嵌入模板，支持 `--mode rules/conf/normal`，`--repo` stub |
| `wfadm check` | ✅ 校验 conf/、rules/、schemas/、scenarios/、connectors/、sinks/ 完整性 |
| `wfadm sink` | ✅ 校验所有 sink TOML 配置合法性 |
| `wfadm self-update` | ✅ 从 GitHub Releases 下载最新 wfusion 二进制（ureq + tar.gz）|

---

## 遗留问题 / 后续 TODO

### 低优先级

1. **剩余 0.12-0.14s 性能拆分**：JSON/frame 解码、window route / async channel、sink 写入、close flush / executor context。

2. **字段级追踪：仅收集引用字段（方案 B）**：当前 `collect_alias_event` 按 `tracked_bind_fields` / `tracked_plain_fields` 收集，可以进一步只收集 yield 表达式实际引用的字段。

3. **`collected_values` 无界增长**（同 `field_values` 模式）：当前有 cap，但方案 B 更彻底。

4. **`derive_legacy_injects` 保留 entity clustering 信息**：上游 wp-reactor 兼容性问题。

5. **TCP daemon 联调受 sandbox 限制**：稳定可用性检查使用 `test/smoke.sh`（batch/file source）。

### 已完成

- `max_memory` 增量缓存（避免每事件全量遍历实例）
- `distinct` typed `ValueKey`
- `field_values` cap（`MAX_TRACKED_FIELD_VALUES = 1024`，`push_capped` 辅助函数）
- ALERT_CHANNEL_CAPACITY: 100000 → 2048
- 启动 guard：`total_routes == 0 && default_sinks.is_empty()` → exit 1
- Dispatch guard：per-target warn when route miss
- Cancel token 修复：`rule_cancel.child_token()` → `cancel.child_token()`
- blackhole sink 注册（wp-reactor 内置）

### 工作区状态提醒

- `wf-rules/rules/*` 多个文件已移动到 `backup/`，不要自动恢复。
- `wf-rules/0` 是未跟踪文件，来源未确认。

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

# 重建（改 wp-reactor / warp-fusion 后必须）
cd ../warp-fusion && cargo build --release && cp target/release/wfusion ~/bin/wfusion && cd ../wf-rules

# 规则库可用性检查：生成 port_scan_quick，batch 回放，断言 network alert
test/smoke.sh
```
