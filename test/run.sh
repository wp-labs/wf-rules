#!/usr/bin/env bash
set -euo pipefail

# wf-rules/test/run.sh — 规则验证启动脚本
# 从 test/ 目录运行，引用上层的 schemas/ + rules/

cd "$(dirname "${BASH_SOURCE[0]}")/.."  # cd to wf-rules/

echo "============================================"
echo "  wf-rules test: wfgen stream → wfusion"
echo "============================================"

cleanup() {
    [ -n "${WFUSION_PID:-}" ] && kill "$WFUSION_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p data/alerts data/logs

# 1. Start wfusion (loads schemas + rules from wf-rules/)
echo "1> wfusion: starting daemon..."
wfusion run --config test/wfusion.toml --work-dir . &
WFUSION_PID=$!
sleep 2
echo "   wfusion PID=$WFUSION_PID"

# 2. wfgen stream — continuous data generation
echo "2> wfgen: streaming scenarios to TCP :9800..."
echo "   Press Ctrl+C to stop"
echo ""
WFL_ARGS=""
for f in rules/*/*.wfl; do WFL_ARGS="$WFL_ARGS --wfl $f"; done
wfgen stream \
    --scenario-dir scenarios/ \
    --ws schemas/network.wfs --ws schemas/auth.wfs --ws schemas/http.wfs --ws schemas/dns.wfs --ws schemas/management.wfs --ws schemas/data.wfs \
    $WFL_ARGS \
    --addr 127.0.0.1:9800 \
    --interval 60 \
    --rate-sleep 200
