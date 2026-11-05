#!/bin/bash
# End-to-end run on a deployed chain: queue a withdrawal, return liquidity, time how long the Reactive callback takes.
#   script/e2e.sh base   (reads deployed-base.env)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; . "./deployed-${1:-base}.env"; set +a
case "${1:-base}" in
  unichain) RPC=https://sepolia.unichain.org ;;
  base)     RPC=https://base-sepolia-rpc.publicnode.com ;;  # sepolia.base.org caps eth_getLogs at 200 blocks
esac
ME=$DEPLOYER_ADDRESS
tx() { cast send "$@" --rpc-url $RPC --private-key "$DEPLOYER_KEY" --json; }

tx "$USD" "mint(address,uint256)" "$ME" 1000000000 >/dev/null
tx "$USD" "approve(address,uint256)" "$VAULT" "$(cast max-uint)" >/dev/null
tx "$VAULT" "deposit(uint256)" 1000000000 >/dev/null
# Lend out everything but 100 mUSD, so a 300 mUSD withdrawal has to wait in the queue.
IDLE=$(cast call "$VAULT" "idle()(uint256)" --rpc-url $RPC | awk '{print $1}')
tx "$VAULT" "deployLiquidity(address,uint256)" "$ME" $((IDLE - 100000000)) >/dev/null
tx "$VAULT" "requestWithdrawal(uint256)" 300000000 >/dev/null
QUEUED=$(cast call "$VAULT" "queueLength()(uint256)" --rpc-url $RPC)
echo "queued: $QUEUED"
[ "$QUEUED" = "1" ] || { echo "expected one queued withdrawal"; exit 1; }

ADD=$(tx "$VAULT" "addLiquidity(uint256)" 300000000)
ADD_BLOCK=$(echo "$ADD" | grep -o '"blockNumber":"[^"]*"' | head -1 | cut -d'"' -f4)
ADD_TX=$(echo "$ADD" | grep -o '"transactionHash":"[^"]*"' | head -1 | cut -d'"' -f4)
ADD_TS=$(cast block $((ADD_BLOCK)) -f timestamp --rpc-url $RPC)
START=$(date +%s)
echo "liquidity added in block $((ADD_BLOCK)) at $ADD_TS"

while [ "$(cast call "$VAULT" "queueLength()(uint256)" --rpc-url $RPC)" != "0" ]; do
  [ $(( $(date +%s) - START )) -gt 600 ] && { echo "not settled after 600 s"; exit 1; }
  sleep 1
done
PAID=$(cast logs --from-block "$ADD_BLOCK" --address "$VAULT" "Settled(uint256,uint256,uint256,uint256)" --rpc-url $RPC --json)
SETTLE_BLOCK=$(echo "$PAID" | grep -o '"blockNumber":"[^"]*"' | head -1 | cut -d'"' -f4)
SETTLE_TX=$(echo "$PAID" | grep -o '"transactionHash":"[^"]*"' | head -1 | cut -d'"' -f4)
SETTLE_TS=$(cast block $((SETTLE_BLOCK)) -f timestamp --rpc-url $RPC)
SETTLE_FROM=$(cast tx "$SETTLE_TX" from --rpc-url $RPC)
WALL=$(( $(date +%s) - START ))
echo "settled in block $((SETTLE_BLOCK)) at $SETTLE_TS by $SETTLE_FROM"
echo "liquidity tx $ADD_TX"
echo "settle tx    $SETTLE_TX"
echo "liquidity -> payout: $((SETTLE_TS - ADD_TS)) s, $((SETTLE_BLOCK - ADD_BLOCK)) blocks (wall clock seen here: $WALL s)"
[ -f latency.csv ] || echo "chain,liquidity_block,settle_block,blocks,seconds,liquidity_tx,settle_tx" > latency.csv
echo "${1:-base},$((ADD_BLOCK)),$((SETTLE_BLOCK)),$((SETTLE_BLOCK - ADD_BLOCK)),$((SETTLE_TS - ADD_TS)),$ADD_TX,$SETTLE_TX" >> latency.csv
