# Changelog

## [Unreleased]

### Fixed

- **Sink 配置**：将所有 sink 配置统一到 `sink.d/` 目录（wfusion daemon 模式兼容）
- **Schema 修复**：将 6 个 `.wfs` 文件的 `stream` 名与 window 名对齐
  - `network.wfs`: `netflow` → `conn_events`
  - `auth.wfs`: `auth` → `auth_events`
  - `http.wfs`: `http` → `http_events`
  - `dns.wfs`: `dns` → `dns_events`
  - `management.wfs`: `ad_audit` → `ad_change_events`, `process` → `process_events`
  - `data.wfs`: `data` → `data_access_events`
- **规则修复**：`port_scan.wfl` yield 补全 `dip`、`total_bytes` 字段

### Added

- **测试场景**：新增 `port_scan_quick.wfg`、`ssh_brute_quick.wfg` 快速测试场景
- **`.gitignore`**：忽略 `data/` 目录

### Changed

- **日志级别**：`test/wfusion.toml` 改为 `debug` 以便排查
