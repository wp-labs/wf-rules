# WPL 适配样例 — 原始日志 → wf-rules 标准字段

这里展示每种数据源如何通过 wpl（Warp Parse Lang）把原始日志映射到 [wf-rules 的标准 schema 字段](../schemas/)。

每个样例包含：
- 原始日志的一行示例
- WPL 解析规则（指定日志字段顺序和命名）
- OML 包声明（指定产出的解析后字段集合）
- 产出字段与 schema 的对照验证

## 使用方式

```bash
# 在 wparse 项目中放入这些文件后运行
wparse batch -p -n 10000
```

---

## 样例列表

| 样例 | 数据源 | schema | 覆盖规则 |
|------|--------|--------|---------|
| [nginx_to_http.wpl](nginx_to_http.wpl) | nginx 访问日志 | http_events | sqli_probe, uri_scan |
| [ssh_authlog_to_auth.wpl](ssh_authlog_to_auth.wpl) | SSH auth.log | auth_events | ssh_brute_force, weak_password_redis, password_spraying |
| [netflow_to_conn.wpl](netflow_to_conn.wpl) | NetFlow/IPFIX | conn_events | port_scan, lateral_spread, beaconing, data_upload |

---

## 治理检查

写 wpl 时对照 [DATA_CONTRACT.md](../DATA_CONTRACT.md) 的字段表：

- [ ] 每个 schema 必填字段都有对应 WPL 字段产出
- [ ] `ip` 字段不含端口（wpl 的 `ip:name` 会自动处理）
- [ ] `digit` 字段可解析为数字
- [ ] 枚举字段产出的值在合法范围内（如 `result` 只能是 `success`/`failed`）
- [ ] `event_time` 用 `time/clf:event_time` 或 `time/iso8601:event_time` 产出为 time 类型
- [ ] `password_hash` 字段小写十六进制（wpl 字符串原样通过，需在 wpl 内转小写或上游保证）
