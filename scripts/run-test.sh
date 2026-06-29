#!/usr/bin/env bash
# =====================================================================
# run-test.sh  (Linux / macOS / CI agents)
# Non-GUI JMeter runner with HTML dashboard generation.
#
# Usage:
#   ./scripts/run-test.sh SmokeTest qa
#   ./scripts/run-test.sh LoadTest  perf -Jusers=200 -Jrampup=120 -Jduration=900
# =====================================================================
set -euo pipefail

PLAN="${1:?Usage: run-test.sh <Plan> <Env> [-Jkey=val ...]}"
ENV="${2:-qa}"
shift 2 || true
EXTRA_PROPS=("$@")

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_ID="${PLAN}-${ENV}-${STAMP}"
JMX="${ROOT}/jmx/${PLAN}.jmx"
ENV_FILE="${ROOT}/config/env/${ENV}.properties"
USER_PROPS="${ROOT}/config/user.properties"
RESULT_DIR="${ROOT}/results/${RUN_ID}"
REPORT_DIR="${ROOT}/reports/${RUN_ID}"
JTL="${RESULT_DIR}/results.jtl"
LOG="${RESULT_DIR}/jmeter.log"

[[ -f "$JMX" ]]      || { echo "Plan not found: $JMX"; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "Env file not found: $ENV_FILE"; exit 1; }
mkdir -p "$RESULT_DIR"

JMETER="${JMETER_HOME:+$JMETER_HOME/bin/}jmeter"

echo "=== Performance Run: ${RUN_ID} ==="
"$JMETER" -n \
  -t "$JMX" \
  -q "$ENV_FILE" \
  -p "$USER_PROPS" \
  -l "$JTL" \
  -j "$LOG" \
  -e -o "$REPORT_DIR" \
  -Jtestdata_file="${ROOT}/data/testdata.csv" \
  "${EXTRA_PROPS[@]}"

echo "HTML dashboard: ${REPORT_DIR}/index.html"
