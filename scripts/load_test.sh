#!/usr/bin/env bash
# scripts/load_test.sh
# Load test using oha (preferred) or apache ab as fallback.
# Install oha: https://github.com/hatoo/oha

set -euo pipefail

HOST="${HOST:-http://localhost:8080}"
DURATION="${DURATION:-30s}"
CONNECTIONS="${CONNECTIONS:-50}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Load Test — ${HOST}"
echo "  Duration: ${DURATION} | Connections: ${CONNECTIONS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_oha() {
  echo ""
  echo "▶ Testing /hodor/ ..."
  oha -z "${DURATION}" -c "${CONNECTIONS}" --no-tui "${HOST}/hodor/"

  echo ""
  echo "▶ Testing /bran/ ..."
  oha -z "${DURATION}" -c "${CONNECTIONS}" --no-tui "${HOST}/bran/"
}

run_ab() {
  # fallback: apache bench (simpler, no duration flag: use -n requests)
  REQUESTS="${REQUESTS:-5000}"
  echo ""
  echo "▶ Testing /hodor/ with ab ..."
  ab -n "${REQUESTS}" -c "${CONNECTIONS}" "${HOST}/hodor/"

  echo ""
  echo "▶ Testing /bran/ with ab ..."
  ab -n "${REQUESTS}" -c "${CONNECTIONS}" "${HOST}/bran/"
}

if command -v oha &>/dev/null; then
  run_oha
elif command -v ab &>/dev/null; then
  echo "oha not found, falling back to apache bench"
  run_ab
else
  echo "Neither oha nor ab found."
  echo "Install oha: cargo install oha  OR  brew install oha"
  echo "Install ab:  apt-get install apache2-utils"
  exit 1
fi

echo ""
echo "✅ Load test complete. Check Grafana at http://localhost:3000 for metrics."
