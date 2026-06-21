# 数据输入契约 — wf-rules 规则库的前置要求

> 规则的正确性**完全依赖**上游数据治理质量。
> 本文档定义每个 window schema 的字段契约——wparse/wpl/oml 必须产出什么、什么格式、什么校验。

## 基本原则

1. **字段名必须匹配**：wparse 产出字段名 = schema 字段名，不允许多对一别名
2. **类型必须正确**：`ip` 类型字段不能是含端口的字符串，`digit` 必须可解析为整数
3. **枚举值必须归一**：`result` 只能是 `success/failed`（小写），不能是 SUCCESS/Failed/0/1
4. **时间必须可解析**：`event_time: time` 必须严格 ISO8601 或 Unix 纳秒时间戳
5. **非空约束**：规则引用频率最高的字段（sip/dip/event_time）不允许空值/缺省值

---

## conn_events（网络流）

| 字段 | 类型 | 必填 | 说明 | 校验 |
|------|------|:--:|------|------|
| `sip` | ip | ✅ | 源 IP（发起连接方） | 合法 IPv4/IPv6，不含端口 |
| `dip` | ip | ✅ | 目的 IP | 同上 |
| `dport` | digit | ✅ | 目的端口 | 1-65535 |
| `bytes` | digit | - | 总字节数 | ≥0 |
| `bytes_in` | digit | - | 入站字节 | ≥0 |
| `bytes_out` | digit | - | 出站字节 | ≥0 |
| `protocol` | chars | - | 传输协议 | `tcp` / `udp` / `icmp` |
| `action` | chars | - | 连接动作 | `syn` / `established` / `fin` / `reset` |
| `duration` | digit | - | 连接时长（秒） | ≥0 |
| `event_time` | time | ✅ | 事件时间 | ISO8601 或 Unix 纳秒时间戳 |

**枚举契约**：

| 字段 | 合法值 |
|------|--------|
| `action` | `syn`, `established`, `fin`, `reset` |
| `protocol` | `tcp`, `udp`, `icmp` |

**治理要点**：
- 扫描检测（port_scan）依赖 `dport` + `action == "syn"`——如果原始日志不区分 syn/established，扫描检测失效
- 横向移动（lateral_spread）依赖 `dport` 是远程管理端口（22/445/3389 等）
- C2 信标（beaconing）依赖 `bytes_out < 200` + `bytes_in < 500`——如果原始数据只给总字节不给方向字节，需补方向推导
- 数据外发（data_upload）依赖 `bytes_out >= 10000000`（10MB）——同上的方向问题

---

## auth_events（认证事件）

| 字段 | 类型 | 必填 | 说明 | 校验 |
|------|------|:--:|------|------|
| `sip` | ip | ✅ | 源 IP（登录发起方） | 合法 IPv4/IPv6 |
| `dip` | ip | - | 目标 IP（被登录主机） | 同上 |
| `dport` | digit | - | 目标端口 | 22(SSH)/445(SMB)/3389(RDP) |
| `service` | chars | - | 服务类型 | `ssh` / `smb` / `rdp` / `winlogon` / `vpn` |
| `user` | chars | - | 登录账户名 | 不含域前缀，小写归一 |
| `password_hash` | chars | - | 密码哈希 | 明文/ntlm/sha256——统一小写十六进制 |
| `result` | chars | ✅ | 认证结果 | `success` / `failed` |
| `logon_type` | digit | - | Windows 登录类型 | 2(交互)/3(网络)/10(远程) |
| `event_time` | time | ✅ | 事件时间 | ISO8601 或 Unix 纳秒时间戳 |

**枚举契约**：

| 字段 | 合法值 |
|------|--------|
| `result` | **`success`** / **`failed`**（小写，无其他变体） |
| `service` | `ssh`, `smb`, `rdp`, `winlogon`, `vpn` |

**治理要点**：
- `result` 是暴力破解/弱口令检测的核心字段——原始日志里可能是 `Accepted`/`Failed`/`Success`/`0`/`1`/`4625`，**必须归一**
- `password_hash` 是弱口令 Redis 查询的唯一 key——`external("password_check", e.password_hash)` 查 Redis SET `weak_passwords`。如果原始日志没有哈希字段，弱口令规则失效
- `user` 必须去域前缀（`DOMAIN\user` → `user`）+ 小写归一

---

## http_events（HTTP 请求事件）

| 字段 | 类型 | 必填 | 说明 | 校验 |
|------|------|:--:|------|------|
| `sip` | ip | ✅ | 源 IP | 合法 IPv4/IPv6 |
| `dip` | ip | - | 目标 IP（Web 服务器） | 同上 |
| `method` | chars | ✅ | HTTP 方法 | `GET`/`POST`/`PUT`/`DELETE` 等 |
| `uri` | chars | - | 请求 URI 路径 | URL 解码后 |
| `status` | digit | - | HTTP 状态码 | 100-599 |
| `bytes_out` | digit | - | 响应字节数 | ≥0 |
| `user_agent` | chars | - | User-Agent 头 | 原始值 |
| `event_time` | time | ✅ | 事件时间 | ISO8601 或 Unix 纳秒时间戳 |

**治理要点**：
- `uri` 需保留完整路径含 query string（`/login.php?id=1' OR '1'='1`），用于 SQLi/路径遍历检测
- `status` 可能为空（wparse 解析失败时有默认值）

---

## dns_events（DNS 查询事件）

| 字段 | 类型 | 必填 | 说明 | 校验 |
|------|------|:--:|------|------|
| `sip` | ip | ✅ | 源 IP（发起 DNS 查询） | 合法 IPv4/IPv6 |
| `query` | chars | ✅ | 查询域名 | 小写 FQDN |
| `qtype` | chars | ✅ | 查询类型 | `A`/`AAAA`/`TXT`/`MX`/`CNAME` |
| `rcode` | chars | - | 响应码 | `NOERROR`/`NXDOMAIN`/`SERVFAIL` |
| `response` | chars | - | 解析结果（IP 列表或 TXT 内容） | 逗号分隔 |
| `bytes` | digit | - | DNS 报文大小 | ≥0 |
| `event_time` | time | ✅ | 事件时间 | ISO8601 或 Unix 纳秒时间戳 |

**治理要点**：
- `query` 需归一为小写 FQDN，去尾点（`www.example.com.`→`www.example.com`）
- DNS 隧道检测依赖 `qtype == "TXT"` + 超长 `query`——`query` 字段必须保留完整原始值
- `response` 可能是多个 IP（`1.2.3.4,5.6.7.8`）或长 TXT 内容

---

## management.wfs — ad_change_events / process_events

### ad_change_events（AD 变更审计）

| 字段 | 类型 | 必填 | 说明 | 校验 |
|------|------|:--:|------|------|
| `sip` | ip | ✅ | 操作发起 IP | 合法 IPv4/IPv6 |
| `user` | chars | ✅ | 操作者账户 | 去域前缀，小写 |
| `target_user` | chars | - | 目标账户 | 被创建/修改的账户名 |
| `target_group` | chars | - | 目标组 | 被加入的特权组名 |
| `action` | chars | ✅ | 操作类型 | `user_created` / `added_to_priv_group` / `user_deleted` / `password_reset` |
| `event_time` | time | ✅ | 事件时间 | ISO8601 或 Unix 纳秒时间戳 |

**枚举契约**：

| 字段 | 合法值 |
|------|--------|
| `action` | `user_created`, `added_to_priv_group`, `user_deleted`, `password_reset` |

**治理要点**：
- 新建账户检测（new_account）依赖 `action` 字段——如果原始日志不区分事件类型（全混在一起），规则失效
- `target_user` 带 `$` 后缀的隐藏账户（如 `svc_backup$`）是高危信号
- 需要 Windows EventLog 4720/4728/4732/4756 对应的 wpl 适配器

### process_events（进程创建事件）

| 字段 | 类型 | 必填 | 说明 | 校验 |
|------|------|:--:|------|------|
| `sip` | ip | ✅ | 进程所在主机 IP | 合法 IPv4/IPv6 |
| `user` | chars | - | 执行进程的用户 | 去域前缀 |
| `process_name` | chars | ✅ | 进程名 | `svchost.exe` / `schtasks.exe` / `powershell.exe` |
| `process_path` | chars | - | 进程完整路径 | `C:\Windows\Temp\payload.exe` |
| `parent_process` | chars | - | 父进程名 | `services.exe` / `explorer.exe` |
| `command_line` | chars | - | 命令行参数 | 原始值，完整保留 |
| `action` | chars | ✅ | 操作类型 | `process_create` / `process_terminate` |
| `event_time` | time | ✅ | 事件时间 | ISO8601 或 Unix 纳秒时间戳 |

**治理要点**：
- 持久化检测（scheduled_task）依赖 `process_path` 在异常目录（`\temp\`、`\public\`、`\downloads\`）
- Sysmon EID 1 是主要数据源，EDR 平台对应事件也可以
- `command_line` 需要保留完整原始值（不截断、不编码转换）

---

## data.wfs — data_access_events

### data_access_events（数据访问审计）

| 字段 | 类型 | 必填 | 说明 | 校验 |
|------|------|:--:|------|------|
| `sip` | ip | ✅ | 访问来源 IP | 合法 IPv4/IPv6 |
| `user` | chars | ✅ | 操作用户 | 去域前缀，小写 |
| `action` | chars | ✅ | 操作类型 | `select` / `download` / `delete` / `insert` |
| `resource` | chars | - | 访问资源标识 | 表名/文件名/API 路径 |
| `row_count` | digit | - | 受影响行数 | ≥0 |
| `bytes_out` | digit | - | 传出字节数 | ≥0 |
| `event_time` | time | ✅ | 事件时间 | ISO8601 或 Unix 纳秒时间戳 |

**枚举契约**：

| 字段 | 合法值 |
|------|--------|
| `action` | `select`, `download`, `delete`, `insert` |

**治理要点**：
- 批量导出检测（data_bulk_export）依赖 `row_count` 和 `bytes_out` 的 `sum` 聚合
- 如果原始审计日志只给"执行了查询"不给行数/字节数，`row_count=0`→规则失效
- 来源多样（DB 审计日志 / 文件服务器审计 / API 网关日志），需要各自写 wpl 适配

---

## 告警输出 window

所有告警 window（`network_alerts`/`security_alerts`/`http_alerts`/`dns_alerts`/`management_alerts`/`insider_alerts`）的 `over = 0`，不进时间窗口——仅用于 schema 声明和 sink 路由。

---

## 校验清单

wparse 侧（wpl/oml 负责）：

- [ ] 每个源字段与目标 schema 字段一一对应映射
- [ ] `ip` 类型字段校验合法 IPv4/IPv6，拒绝含端口字符串
- [ ] `digit` 类型字段可解析为整数（`"22"`→`22`，`"N/A"`→拒绝）
- [ ] `result` 归一为 `success`/`failed`（小写二选一）
- [ ] `event_time` 归一为 Unix 纳秒时间戳或 ISO8601
- [ ] 所有必填字段非空
- [ ] `password_hash` 小写十六进制
- [ ] `logon_type` 可解析为整数（Windows 登录类型 2/3/10）
- [ ] `action` 枚举值在合法范围内（按 schema 的枚举契约）
- [ ] `row_count`、`bytes_out` 为 ≥0 的整数（data_access_events）
- [ ] `process_path` 保留完整原始路径（process_events）
- [ ] `command_line` 保留完整原始值，不截断（process_events）

wfusion 侧（.wfs schema 负责）：

- [ ] schema 字段名与 wpl 产出字段名完全一致
- [ ] 类型声明正确匹配 wpl 产出类型
- [ ] `over` 时间窗口合理（不短于检测阈值的时间跨度）

---

## 参考

- wf-rules 示例 schema → [schemas/](schemas/)
- wpl 适配样例 → [wpl-samples/](wpl-samples/)
- knowdb.toml 配置 → [../examples/wp-pipeline/kafka/wfusion/knowdb.toml](../warp-fusion/examples/wp-pipeline/kafka/wfusion/knowdb.toml)
