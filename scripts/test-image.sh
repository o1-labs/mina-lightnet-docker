#!/usr/bin/env bash

set -euo pipefail

# Integration test for Mina Lightnet Docker image
# Usage: ./scripts/test-image.sh <docker-image-name> [proof-level]
#
# Examples:
#   ./scripts/test-image.sh test-local/mina-local-network:develop-latest-lightnet none
#   ./scripts/test-image.sh test-local/mina-local-network:develop-latest-devnet full

CONTAINER_NAME="mina-lightnet-test"
DAEMON_PORT=8080
ACCOUNTS_MANAGER_PORT=8181
ARCHIVE_API_PORT=8282
POSTGRES_PORT=5432

DAEMON_URL="http://127.0.0.1:${DAEMON_PORT}/graphql"
ACCOUNTS_MANAGER_URL="http://127.0.0.1:${ACCOUNTS_MANAGER_PORT}"
ARCHIVE_API_URL="http://127.0.0.1:${ARCHIVE_API_PORT}"

PROOF_LEVEL="${2:-none}"

# Adjust timeouts based on proof level (full proofs are much slower)
if [[ "${PROOF_LEVEL}" == "full" ]]; then
  SYNC_MAX_ATTEMPTS=120
  SYNC_SLEEP=10
  TX_MAX_ATTEMPTS=60
  TX_SLEEP=10
else
  SYNC_MAX_ATTEMPTS=60
  SYNC_SLEEP=10
  TX_MAX_ATTEMPTS=30
  TX_SLEEP=10
fi

TESTS_PASSED=0
TESTS_FAILED=0

# --- Helpers ---

cleanup() {
  echo ""
  echo "=== Cleanup ==="
  echo "Stopping and removing container ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
}

trap cleanup EXIT

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  FAIL: $1"
}

graphql_query() {
  local url="$1"
  local query="$2"
  local payload
  payload=$(jq -nc --arg q "$query" '{query: $q}')
  curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$url" 2>/dev/null || echo ""
}

# --- Main ---

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <docker-image-name> [proof-level]"
  echo "  proof-level: none (default) or full"
  exit 1
fi

IMAGE="$1"

echo "=== Mina Lightnet Docker Integration Test ==="
echo "Image: ${IMAGE}"
echo "Proof level: ${PROOF_LEVEL}"
echo ""

# Step 1: Start the container
echo "=== Starting container ==="
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${DAEMON_PORT}:${DAEMON_PORT}" \
  -p "${ACCOUNTS_MANAGER_PORT}:${ACCOUNTS_MANAGER_PORT}" \
  -p "${ARCHIVE_API_PORT}:${ARCHIVE_API_PORT}" \
  -p "${POSTGRES_PORT}:${POSTGRES_PORT}" \
  --env NETWORK_TYPE=single-node \
  --env PROOF_LEVEL="${PROOF_LEVEL}" \
  --env RUN_ARCHIVE_NODE=true \
  --env LOG_LEVEL=Info \
  "${IMAGE}"

echo "Container started: ${CONTAINER_NAME}"
echo ""

# Step 2: Wait for network sync
echo "=== Waiting for network sync (max $((SYNC_MAX_ATTEMPTS * SYNC_SLEEP))s) ==="
synced=false
for attempt in $(seq 1 ${SYNC_MAX_ATTEMPTS}); do
  response=$(graphql_query "${DAEMON_URL}" "{ syncStatus }")
  if [[ "${response}" == *'"syncStatus":"SYNCED"'* ]]; then
    synced=true
    echo "Network synced after $((attempt * SYNC_SLEEP))s"
    break
  fi
  echo "  Attempt ${attempt}/${SYNC_MAX_ATTEMPTS}: not synced yet..."
  sleep ${SYNC_SLEEP}
done

if [[ "${synced}" != "true" ]]; then
  echo "FATAL: Network did not sync within $((SYNC_MAX_ATTEMPTS * SYNC_SLEEP))s"
  echo "Container logs (last 50 lines):"
  docker logs --tail 50 "${CONTAINER_NAME}" 2>&1 || true
  exit 1
fi
echo ""

# Step 3: Test services
echo "=== Testing Services ==="

# 3a. Mina Daemon
echo "[Mina Daemon]"
response=$(graphql_query "${DAEMON_URL}" "{ daemonStatus { syncStatus blockchainLength } }")
if [[ "${response}" == *'"syncStatus":"SYNCED"'* ]] && [[ "${response}" == *'"blockchainLength"'* ]]; then
  blockchain_length=$(echo "${response}" | jq -r '.data.daemonStatus.blockchainLength // empty')
  pass "Daemon is synced, blockchainLength=${blockchain_length}"
else
  fail "Daemon status query failed: ${response}"
fi

# 3b. Accounts Manager
echo "[Accounts Manager]"
http_code=$(curl -s -o /dev/null -w "%{http_code}" "${ACCOUNTS_MANAGER_URL}/list-acquired-accounts" 2>/dev/null || echo "000")
if [[ "${http_code}" == "200" ]]; then
  pass "Accounts Manager is responding (HTTP ${http_code})"
else
  fail "Accounts Manager returned HTTP ${http_code}"
fi

# 3c. Archive Node API (may need retries as it depends on archive data being available)
echo "[Archive Node API]"
archive_ok=false
for attempt in $(seq 1 12); do
  response=$(graphql_query "${ARCHIVE_API_URL}" "{ __typename }")
  if [[ -n "${response}" ]] && [[ "${response}" != *'"errors"'* ]]; then
    archive_ok=true
    pass "Archive Node API is responding: ${response}"
    break
  fi
  echo "  Attempt ${attempt}/12: Archive Node API not ready yet (response: ${response})..."
  sleep 5
done
if [[ "${archive_ok}" != "true" ]]; then
  # Check if port is even reachable
  archive_http=$(curl -s -o /dev/null -w "%{http_code}" "${ARCHIVE_API_URL}" 2>/dev/null || echo "000")
  echo "  Archive API HTTP status: ${archive_http}"
  echo "  Container archive-node-api logs:"
  docker exec "${CONTAINER_NAME}" cat /root/logs/archive-node-api.log 2>/dev/null | tail -20 || true
  fail "Archive Node API query failed: ${response}"
fi

# 3d. PostgreSQL
echo "[PostgreSQL]"
pg_result=$(docker exec "${CONTAINER_NAME}" psql -U postgres -d archive -t -c "SELECT count(*) FROM blocks;" 2>/dev/null | tr -d ' \n' || echo "")
if [[ -n "${pg_result}" ]] && [[ "${pg_result}" =~ ^[0-9]+$ ]] && [[ "${pg_result}" -ge 0 ]]; then
  pass "PostgreSQL is responding, blocks count=${pg_result}"
else
  fail "PostgreSQL query failed: ${pg_result}"
fi

echo ""

# Step 4: Transaction lifecycle
echo "=== Transaction Lifecycle Test ==="

# 4a. Acquire sender account from accounts manager, then import and unlock on daemon
echo "[Acquiring sender account]"
sender_response=$(curl -s "${ACCOUNTS_MANAGER_URL}/acquire-account" 2>/dev/null || echo "")
if [[ -z "${sender_response}" ]] || ! echo "${sender_response}" | jq -e '.pk' >/dev/null 2>&1; then
  fail "Failed to acquire sender account: ${sender_response}"
  echo ""
  echo "=== Results ==="
  echo "Passed: ${TESTS_PASSED}"
  echo "Failed: ${TESTS_FAILED}"
  exit 1
fi
sender_pk=$(echo "${sender_response}" | jq -r '.pk')
echo "  Sender: ${sender_pk:0:20}..."

# Copy the encrypted key file into the container and import it into the daemon
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_PAIRS_DIR="${SCRIPT_DIR}/../configuration/key-pairs"
CONTAINER_KEYS_DIR="/root/imported_keys"
CONTAINER_KEY_PATH="${CONTAINER_KEYS_DIR}/${sender_pk}"
echo "  Copying key file into container..."
docker exec "${CONTAINER_NAME}" mkdir -p "${CONTAINER_KEYS_DIR}"
docker exec "${CONTAINER_NAME}" chmod 0700 "${CONTAINER_KEYS_DIR}"
docker cp "${KEY_PAIRS_DIR}/${sender_pk}" "${CONTAINER_NAME}:${CONTAINER_KEY_PATH}"
docker exec "${CONTAINER_NAME}" chmod 0600 "${CONTAINER_KEY_PATH}"
echo "  Importing sender key into daemon..."
import_response=$(graphql_query "${DAEMON_URL}" "mutation { importAccount(path: \"${CONTAINER_KEY_PATH}\", password: \"naughty blue worm\") { publicKey alreadyImported success } }")
echo "  Import response: ${import_response}"
echo "  Unlocking sender account..."
unlock_response=$(graphql_query "${DAEMON_URL}" "mutation { unlockAccount(input: { publicKey: \"${sender_pk}\", password: \"naughty blue worm\" }) { account { publicKey } } }")
echo "  Unlock response: ${unlock_response}"

# 4b. Acquire receiver account from accounts manager
echo "[Acquiring receiver account]"
receiver_response=$(curl -s "${ACCOUNTS_MANAGER_URL}/acquire-account" 2>/dev/null || echo "")
if [[ -z "${receiver_response}" ]] || ! echo "${receiver_response}" | jq -e '.pk' >/dev/null 2>&1; then
  fail "Failed to acquire receiver account: ${receiver_response}"
  echo ""
  echo "=== Results ==="
  echo "Passed: ${TESTS_PASSED}"
  echo "Failed: ${TESTS_FAILED}"
  exit 1
fi
receiver_pk=$(echo "${receiver_response}" | jq -r '.pk')
echo "  Receiver: ${receiver_pk:0:20}..."

# 4c. Check sender balance
echo "[Checking sender balance]"
response=$(graphql_query "${DAEMON_URL}" "{ account(publicKey: \"${sender_pk}\") { balance { total } nonce } }")
sender_balance=$(echo "${response}" | jq -r '.data.account.balance.total // empty')
sender_nonce=$(echo "${response}" | jq -r '.data.account.nonce // empty')
if [[ -n "${sender_balance}" ]]; then
  pass "Sender balance: ${sender_balance}, nonce: ${sender_nonce}"
else
  fail "Could not query sender balance: ${response}"
fi

# 4d. Send payment
echo "[Sending payment]"
send_mutation="mutation { sendPayment(input: { from: \"${sender_pk}\", to: \"${receiver_pk}\", amount: \"1000000000\", fee: \"100000000\" }) { payment { id hash } } }"
send_response=$(graphql_query "${DAEMON_URL}" "${send_mutation}")
tx_hash=""
if [[ -n "${send_response}" ]] && [[ "${send_response}" != *'"errors"'* ]]; then
  tx_hash=$(echo "${send_response}" | jq -r '.data.sendPayment.payment.hash // empty')
  if [[ -n "${tx_hash}" ]]; then
    pass "Payment sent, hash: ${tx_hash}"
  else
    fail "Payment sent but no hash returned: ${send_response}"
  fi
else
  fail "sendPayment mutation failed: ${send_response}"
fi

# 4e. Wait for transaction to appear in archive
if [[ -n "${tx_hash}" ]]; then
  echo "[Waiting for transaction in archive (max $((TX_MAX_ATTEMPTS * TX_SLEEP))s)]"
  tx_found=false
  for attempt in $(seq 1 ${TX_MAX_ATTEMPTS}); do
    # Query archive PostgreSQL directly for the transaction hash
    tx_count=$(docker exec "${CONTAINER_NAME}" psql -U postgres -d archive -t -c "SELECT count(*) FROM user_commands WHERE hash = '${tx_hash}';" 2>/dev/null | tr -d ' \n' || echo "0")
    if [[ "${tx_count}" =~ ^[0-9]+$ ]] && [[ "${tx_count}" -gt 0 ]]; then
      tx_found=true
      pass "Transaction found in archive DB (hash: ${tx_hash})"
      break
    fi
    echo "  Attempt ${attempt}/${TX_MAX_ATTEMPTS}: transaction not in archive yet..."
    sleep ${TX_SLEEP}
  done

  if [[ "${tx_found}" != "true" ]]; then
    fail "Transaction not found in archive within $((TX_MAX_ATTEMPTS * TX_SLEEP))s"
  fi

  # 4f. Verify via Archive Node API
  echo "[Verifying archive API has blocks]"
  response=$(graphql_query "${ARCHIVE_API_URL}" "{ blocks(limit: 1) { stateHash } }")
  if [[ -n "${response}" ]] && [[ "${response}" != *'"errors"'* ]] && [[ "${response}" == *'"blocks"'* ]]; then
    pass "Archive API reports blocks available"
  else
    fail "Archive API final check failed: ${response}"
  fi
fi

# 4g. Release acquired accounts
echo "[Releasing acquired accounts]"
sender_sk=$(echo "${sender_response}" | jq -r '.sk')
curl -s -X PUT -H "Content-Type: application/json" \
  -d "{\"pk\":\"${sender_pk}\",\"sk\":\"${sender_sk}\"}" \
  "${ACCOUNTS_MANAGER_URL}/release-account" >/dev/null 2>&1 || true
receiver_sk=$(echo "${receiver_response}" | jq -r '.sk')
curl -s -X PUT -H "Content-Type: application/json" \
  -d "{\"pk\":\"${receiver_pk}\",\"sk\":\"${receiver_sk}\"}" \
  "${ACCOUNTS_MANAGER_URL}/release-account" >/dev/null 2>&1 || true

pass "Acquired accounts released"

echo ""
echo "=== Results ==="
echo "Passed: ${TESTS_PASSED}"
echo "Failed: ${TESTS_FAILED}"

if [[ ${TESTS_FAILED} -gt 0 ]]; then
  echo ""
  echo "INTEGRATION TEST FAILED"
  exit 1
else
  echo ""
  echo "ALL INTEGRATION TESTS PASSED"
  exit 0
fi
