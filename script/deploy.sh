#!/bin/bash
# Deploy the demo on one destination chain plus its reactive contract on Lasna, then wire them together.
#   source .env; script/deploy.sh unichain   (or: base)
# Needs DEPLOYER_KEY funded with Unichain Sepolia (or Base Sepolia) ETH for the vault and lREACT on Lasna.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
case "${1:-unichain}" in
  unichain) RPC=https://sepolia.unichain.org; CHAIN=1301; PROXY=0x775c9B990ADe401060B78D0e98684eEf8d2466C1 ;;
  base)     RPC=https://sepolia.base.org;     CHAIN=84532; PROXY=0x476F44b11F5C942c58f4c8E3d0300E5710743585 ;;
  *) echo "unichain or base"; exit 1 ;;
esac
LASNA=https://lasna-rpc.rnk.dev/
addr() { grep -o 'Deployed to: 0x[0-9a-fA-F]\{40\}' | awk '{print $3}'; }

USD=$(forge create src/MockUSD.sol:MockUSD --rpc-url $RPC --private-key "$DEPLOYER_KEY" --broadcast | addr)
VAULT=$(forge create src/InstantWithdrawalVault.sol:InstantWithdrawalVault --rpc-url $RPC --private-key "$DEPLOYER_KEY" \
  --broadcast --value 0.01ether --constructor-args "$USD" "$PROXY" | addr)
REACTIVE=$(forge create src/QueueReactive.sol:QueueReactive --rpc-url $LASNA --private-key "$DEPLOYER_KEY" \
  --broadcast --value 1.5ether --constructor-args "$CHAIN" "$VAULT" | addr)
cast send "$VAULT" "setCallbackSender(address)" "$REACTIVE" --rpc-url $RPC --private-key "$DEPLOYER_KEY" >/dev/null
printf 'CHAIN=%s\nUSD=%s\nVAULT=%s\nREACTIVE=%s\n' "$CHAIN" "$USD" "$VAULT" "$REACTIVE" | tee "deployed-$1.env"
