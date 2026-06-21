# 任务进展 — 2026-06-21（更新于 22:30）

## 目标

修复 `wf-rules/test/run.sh` 测试不产生告警的问题。

## 总体状态（最新）

| 环节 | 状态 |
|------|------|
| wfusion 启动 | OK |
| wfgen → wfusion 数据流 | OK（单帧 30000 行成功 decode + route）|
| Arrow IPC 解码 / 窗口路由 | OK |
| 规则匹配（match 引擎）| OK（ssh_brute_force 3000 次命中）|
| 告警序列化 `to_data_record` | OK（0 个 `alert export error`）|
| 告警下发 `alert_tx → alert_task` | OK（3000 条到达 dispatcher）|
| **告警 sink 输出文件** | **OK — `data/alerts/security.ndjson` 3000 条，字段完整（sip/dip/user/alert_type）** |

> 端到端已打通。验证样本：`sip=10.0.0.1 dip=172.32.101.104 user=root type=ssh_brute_force`。

## 已完成的修复

### 1. wf-rules 配置修复（已提交）

| 修改 | 说明 |
|------|------|
| `test/sinks/` → `sink.d/` 结构 | daemon 模式兼容，删除 `business.d/`、`infra.d/`、`connectors/` |
| 6 个 `.wfs` schema `stream` 名对齐 window 名 | `netflow`→`conn_events`, `auth`→`auth_events`, 等 |
| `port_scan.wfl` yield 补全字段 | 添加 `dip`、`total_bytes` |
| `port_scan_quick.wfg`、`ssh_brute_quick.wfg` | 新增快速测试场景 |
| `attack_chain.wfg` | 移除（bind alias 语法不兼容，改名 `.bak`） |

### 2. warp-fusion — wfgen 重构（已提交）

| 修改 | 说明 |
|------|------|
| `tcp_send.rs` 重写 | `TcpStream` + 手动 Arrow IPC → `TcpArrowSink`（`wp-core-connectors 0.5.5`） |
| RFC6587 帧格式修复 | 4B 二进制 header → ASCII `"<len> <payload>"`（匹配 wfusion `framing="len"`） |
| `cmd_stream/send/bench/gen` async 化 | `#[tokio::main]` + `.await` |
| `wfusion/main.rs` | 添加 `.await` 到 wfgen async 调用 |
| 依赖升级 | `wp-core-connectors` 0.5.2 → 0.5.5 |

### 3. 数据管线验证

```
wfgen → TcpArrowSink → TCP → wfusion tcp_src → DataSourceBatchSource → Router → Window
  ✅       ✅          ✅       ✅               ✅                    ✅      ✅
```

日志确认：`frame decoded stream="auth_events" rows=30000`，`route report delivered=1`

## 已解决 — 告警序列化报错（`invalid ip literal ""`）

### 历史错误

```
alert export error: data format error
detail: invalid ip literal ""
```

### 根因（已被 wp-reactor commit `ac9a83e` 修复，且在集成层验证通过）

**`e.dip` 在 yield 求值时返回空字符串的完整链路**：

1. `collect_bind_tracking_aliases()` 不处理纯字段引用（如 `e.dip`：`Expr::Field(FieldRef::Qualified("e","dip"))`），只处理 series 函数（如 `count(e)`）→ `tracked_bind_aliases` 为空
2. `should_track_bind_alias("e")` 返回 `false`（`e` 被 `on event` step 使用且不在 tracked set 中）→ alias state 不收集字段值
3. `snapshot_bind_data()` 创建的 `BindData` 中 `field_values` 为空
4. `build_eval_context()` 将 bind_data 字段存为 `_bind_e_field_dip`（带前缀）→ 无数据可暴露
5. `eval_yield_expr_with_score("e.dip", ctx)` 中 `ctx.fields.get("dip")` 找不到 → 返回 `None` → 兜底为 `Value::Str("")`
6. `parse_ip_value("")` → `"invalid ip literal \"\""` → 告警被丢弃

**验证结果**：重建二进制后 `to_data_record()` 对 3000 条告警全部成功，0 个序列化错误。

### wp-reactor 修复代码（已提交，4 文件）

| 文件 | 修改 | 单测 |
|------|------|------|
| `wf-lang/compiler/mod.rs` | `collect_bind_tracking_aliases` 增加 `Expr::Field(FieldRef::Qualified/Bracketed)` 分支，提取别名 `e` 到 `tracked_bind_aliases` | ✅ 4/4 |
| `wf-engine/executor/context.rs` | `build_eval_context` 从 step_data + bind_data 暴露纯字段名（非前缀格式） | ✅ 1/1 |
| `wf-lang/compiler/tests/mod.rs` | 4 个新测试 | ✅ |
| `wf-engine/executor/context.rs` 测试 | 1 个新测试 | ✅ |

## 已解决 — 告警 sink 从未被构建（原根因：sinks 目录布局错误）

### 历史现象

- `ssh_brute_force` 命中 3000 次，`execute_match_with_joins` 全部 `Ok(Some(record))`
- `alert_task` 收到 3000 条并全部调用 `dispatcher.dispatch("security_alerts", ...)`
- 但 `data/alerts/` 为空，日志无任何 sink 写入错误

### 根因

`load_sink_config`（`wf-config/src/sink/io.rs`）期望的目录布局是分层结构，但 `test/sinks/` 被前一次 AI 改动全部拍平进了 `sink.d/`：

```
期望布局：                      实际（错误）布局：
sinks/                          sinks/
├── connectors/sink.d/*.toml    └── sink.d/  ← 全部塞这里
├── business.d/*.toml               ├── connectors.toml
├── infra.d/default.toml            ├── network.toml / security.toml ...
├── infra.d/error.toml              ├── default.toml
└── defaults.toml                   └── error.toml
```

结果：`business.d/` 不存在 → `bundle.business` 为空；`infra.d/` 不存在 → `bundle.infra_default` 为 None；`find_connector_dir` 查找 `<ancestor>/connectors/sink.d` 也查不到 → connectors 为空。**一个 sink 都建不出来。**

### 修复（`wf-rules/test/sinks/`）

按 `warp-fusion/examples/close_demo/sinks/` 的参考布局归位：

```
test/sinks/
├── connectors/sink.d/file.toml   ← 原 sink.d/connectors.toml
├── business.d/{network,security,insider,dns,http,management}.toml
├── infra.d/{default,error}.toml
└── defaults.toml
```

### 验证

- 启动日志出现 8 个 `building sink:` 行（6 业务 + 2 infra）
- `data/alerts/security.ndjson` 3000 行，`sip/dip/user/alert_type` 字段完整
- 0 个 `alert export error`
- wf-engine（229）+ wf-config 测试全过，无回归

### 健壮性增强（防再次静默失败 + 限定内存）

加了四项改动（本次问题如果早有它们，1 秒就能暴露）：

1. **启动期守卫 — 启动失败**（`wf-runtime/src/sink_build.rs` `build_sink_dispatcher`）：若 `total_routes == 0 && default_sinks.is_empty()`（没有任何 sink 能接收告警），返回 `Err(RuntimeReason::Bootstrap)`，wfusion 直接以 exit code 1 退出，日志报 `fail! doing=engine-bootstrap`。负向测试确认会退出。`error_sinks`/`monitor_sinks` 不计入——它们只在别的 sink 失败时/指标路径才被用到。**纯管道拓扑不豁免**（已确认需求）。
2. **下发期守卫（按 yield_target 去重）**（`wf-runtime/src/alert_task.rs`）：`dispatch` 返回 `matched=0` 且无 default sink 时，`log::warn!` 提示该 `yield_target` 告警被丢弃。用 `HashSet` 去重，同一 target 只警告一次（负向测试：3000 条告警到无路由 target 只出 1 行 warn，而非 3000 行）。
3. **`SinkDispatcher::has_no_default_sinks()`**（`wf-engine/src/sink/dispatch.rs`）：暴露 default sink 是否为空，供下发守卫查询。
4. **tracked `field_values` 限定上限（alias + close step 统一）**（`wf-engine/src/match_engine/match_engine/step.rs`）：`collect_alias_event` 和 `collect_event_fields` 原先都对每个事件的全字段无界累积，高频窗口会 OOM。现在共用 `MAX_TRACKED_FIELD_VALUES=1024` 常量 + `push_capped` 辅助函数（软上限 2×，超限才 trim，push 摊还 O(1)）。— yield 字段解析（`.last()`）不受影响；L3 的 `collect_set/last` 在有界样本上工作；`first/stddev/percentile` 变为近似（已记录权衡）。**关键澄清**：close step 的阈值判定（count/sum/min/max/distinct）走独立累加器，不碰 `field_values`；join 走 `windows.snapshot()`，也不碰。所以封顶只影响 yield/L3，不影响匹配语义。单测 `collect_alias_event_caps_field_values_and_keeps_most_recent` + `collect_event_fields_caps_branch_field_values_and_keeps_most_recent` 验证。
5. **`ALERT_CHANNEL_CAPACITY` 64 → 2048**（`wf-runtime/src/alert_task.rs`）：原调试期被改到 100000（几乎无界），改回 2048，背压靠 `send().await`。本次负载下验证无 `channel full`。
6. **wfgen 不再静默吞 WFL 编译错误**（`warp-fusion/crates/wfgen/src/cmd_stream.rs`）：`Err(_e)` 改为 `Err(e)`，警告消息带上实际错误详情，避免"注入没生效却查不出原因"。

### 后续低优先 TODO

- **【低】方案 B：只收集被引用的字段**。当前 `collect_alias_event`/`collect_event_fields` 仍对**每个事件的全部字段**累积（只是加了条数封顶）。更彻底的优化是：从 plan 预算出每个 step/alias 实际被 yield/score/entity/L3 引用的字段名，只收集这些字段（如 `sip`/`dip`/`user`），不收集 `password_hash`/`logon_type` 等无用字段。收益：内存再降一个数量级，且被引用字段可保持更高精度。代价：要扩 `MatchPlan`/`StepPlan` 结构携带"每 step 引用字段集"、改 `collect_*` 签名，牵连多个手搓 MatchPlan 的测试。本次先做方案 A（条数封顶）堵住 OOM，方案 B 待有高吞吐/精度需求时再做。
- **【低】`collected_values`（branch 配置字段的 L3 主路径）同款无界增长**。`update_measure` 里 `bs.collected_values.push(val)` 每事件累加、无封顶。它是单字段所以比 `field_values` 轻，但严格说也该封顶。可复用 `push_capped` / `MAX_TRACKED_FIELD_VALUES`。
- **【低】blackhole sink 注册**。`wp-core-connectors` 已内置 `BlackHoleFactory`（kind=`blackhole`），但 wfusion 的 `register.rs::register_connectors()` 只注册了 kafka（file 由 wp-reactor 的 `bootstrap.rs` 单独 `factory_registry.register(FileFactory)` 注册）。要让纯管道拓扑用 blackhole 作逃生口，需在注册流程里加 `BlackHoleFactory`。

### 临时诊断代码（已清理）

> 此前在 `rule_task.rs` / `alert_task.rs` 加的 `[TEMP-DIAG]` 临时 `log::warn!` 已全部移除，代码恢复原状。

## 已解决 — `event_time` 被当作纳秒（实为陈旧测试数据）

### 现象

旧测试数据 `/tmp/wfgen_out3/ssh_send.jsonl` 中 `"event_time": 1782025837`（Unix 秒≈2026）和 `"_timestamp": "1970-..."`（epoch），wfusion 的 `extract_event_time` 按约定把整数当**纳秒**读，于是变成 1970。

### 根因

**不是代码 bug，是陈旧数据。** 约定是「整数纳秒」：
- `wfgen/datagen/stream_gen.rs`：`ts.timestamp_nanos_opt()`（纳秒）✓
- `wf-engine/alert/types.rs::parse_time_value`：接受「RFC3339 文本或整数纳秒」✓
- `wf-engine/match_engine/mod.rs::extract_event_time`：直接按 i64 纳秒用 ✓

当前 wfgen 重新生成的数据正确：`"event_time":1782054549657648542`、`"_timestamp":"2026-06-21T15:09:09.657Z"`。旧文件是更早版本的 wfgen（输出秒 + epoch）生成的。

### 修复

重新生成测试数据（无需改代码）：

```bash
cd wf-rules
wfgen gen --scenario scenarios/ssh_brute_quick.wfg \
  --ws schemas/auth.wfs --wfl rules/02-initial_access/ssh_brute_force.wfl \
  --out /tmp/wfgen_out4
```

### 验证

用新数据跑，告警 `__wfu_fired_at` 已是 `2026-06-21T15:09:11.907Z`（不再是 1970），3000 条告警字段完整，0 错误。时间窗口/close 语义现在也正确。

## 历史备选方向（已无需继续）

1. ~~调试 `should_track_bind_alias` / `collect_alias_event` 与 match engine 的交互~~ — 误报，实为陈旧二进制
2. ~~不依赖 compiler fix，在 `build_eval_context` 中从 step_data.field_values 取字段~~ — 不再需要，compiler fix + context fix 已工作
3. ~~向上游提报 `should_track_bind_alias` bug~~ — 经回归测试 `tracked_alias_same_as_branch_source_still_matches` 验证，该函数行为正确，无需提报

## 关键路径

| 项目 | 路径 |
|------|------|
| wf-rules | `/Users/zuowenjian/devspace/rust/wfusion/wf-rules/` |
| warp-fusion workspace | `/Users/zuowenjian/devspace/rust/wfusion/warp-fusion/` |
| warp-fusion Cargo.toml | `warp-fusion/Cargo.toml`（用本地路径 `path = "../wp-reactor/crates/wf-engine"` 等） |
| wp-reactor（修复代码） | `/Users/zuowenjian/devspace/rust/wfusion/wp-reactor/` |
| wfusion binary | `/Users/zuowenjian/bin/wfusion`（debug build，需从 `warp-fusion/target/debug/wfusion` copy） |
| wp-core-connectors issue | https://github.com/wp-labs/wp-core-connectors/issues/15 |

## 测试数据

| 文件 | 说明 |
|------|------|
| `/tmp/wfgen_out3/ssh_send.jsonl` | ssh_brute_force 测试数据（30000 事件，sip=10.0.0.1，timestamps spread） |
| `/tmp/wfgen_out/port_scan_fixed.jsonl` | port_scan 测试数据 |
| `scenarios/ssh_brute_quick.wfg` | ssh brute force 快速场景 |
| `scenarios/port_scan_quick.wfg` | port scan 快速场景 |

## 快速测试命令

> 注意：路径根目录是 `/Users/zuowenjian/devspace/rust/wfusion`（带 f），进度文档早期版本误写为 `wusion`。

```bash
cd /Users/zuowenjian/devspace/rust/wfusion/wf-rules

# 重建二进制（修改 wp-reactor 后必须）
cd ../warp-fusion && cargo build && cp target/debug/wfusion /Users/zuowenjian/bin/wfusion && cd ../wf-rules

# 清理 + 启动 wfusion
pkill -f 'wfusion run' 2>/dev/null; sleep 1
rm -f data/alerts/* data/wfusion.log
wfusion run --config test/wfusion.toml --work-dir . > /dev/null 2>&1 &
sleep 3

# 发送 ssh_brute_force 测试数据（30000 事件，单帧）
wfgen send --scenario scenarios/ssh_brute_quick.wfg --input /tmp/wfgen_out3/ssh_send.jsonl \
  --ws schemas/auth.wfs --addr 127.0.0.1:9800
sleep 6

# 检查结果
grep -c 'alert export error' data/wfusion.log   # 期望 0
grep 'ssh_brute_force.*batch summary' data/wfusion.log  # 期望 matched=3000
ls -la data/alerts/   # 当前为空（sink 未构建问题）
```

## 本次调试的关键结论

1. **二进制陈旧是最大陷阱**：wp-reactor 的修复（commit `ac9a83e`）+ wf-runtime 的 `ALERT_CHANNEL_CAPACITY` 改动都需要重建 `warp-fusion`。每次改 wp-reactor 后必须 `cargo build` 并 `cp` 到 `~/bin/wfusion`。
2. **match 引擎逻辑正确**：`should_track_bind_alias` + `collect_alias_event` + compiler fix 在单元测试和集成层都工作正常，ssh_brute_force（纯 `on event`）的 `e.dip`/`e.user` 字段能正确解析。
3. **`event_time` 约定是整数纳秒**：旧测试数据输出的是 Unix 秒 + epoch `_timestamp`（更早版本 wfgen 的产物），导致 wfusion 按 1.78ns 解释。重新生成数据后 `fired_at` 恢复为 2026。代码侧无 bug。
4. **告警链路最后一公里断了**：数据、匹配、序列化、channel 全通，唯独 sink 构建环节缺失。
