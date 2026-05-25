#!/usr/bin/env bash
# scripts/smoke_test.sh
# Quick functional tests against the running stack.

set -euo pipefail

HOST="${HOST:-http://localhost:8080}"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local url="$2"
  local expected_status="${3:-200}"

  status=$(curl -s -o /dev/null -w "%{http_code}" "${url}")
  if [ "$status" -eq "$expected_status" ]; then
    echo "  ✅ PASS: ${desc} (${status})"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: ${desc} — expected ${expected_status}, got ${status}"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Smoke Tests against ${HOST}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Hodor tests
check "hodor root endpoint" "${HOST}/hodor/"
check "hodor health endpoint" "${HOST}/hodor/health"
check "hodor ready endpoint" "${HOST}/hodor/ready"

# Bran tests
check "bran root endpoint" "${HOST}/bran/"
check "bran health endpoint" "${HOST}/bran/health/"
check "bran ready endpoint" "${HOST}/bran/ready/"
check "bran can reach hodor" "${HOST}/bran/reach-hodor/"

# Verify response contains correct service field
echo ""
echo "Verifying response bodies..."

hodor_svc=$(curl -s "${HOST}/hodor/" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('service','MISSING'))")
bran_svc=$(curl -s "${HOST}/bran/" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('service','MISSING'))")

[ "$hodor_svc" = "hodor" ] && echo "  ✅ PASS: hodor returns service=hodor" && PASS=$((PASS+1)) || echo "  ❌ FAIL: hodor service field" && FAIL=$((FAIL+1))
[ "$bran_svc" = "bran" ] && echo "  ✅ PASS: bran returns service=bran" && PASS=$((PASS+1)) || echo "  ❌ FAIL: bran service field" && FAIL=$((FAIL+1))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
