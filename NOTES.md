# Reactive Omni Buildathon (DoraHacks), USD 5,500 paid in REACT

https://dorahacks.io/hackathon/reactive-omni-buildathon/detail . Read 5 Nov 2026. Submissions 5 Nov 16:00 - 6 Dec 00:00
Baku. 28 hackers registered on 5 Nov. Testnets only needed (Reactive Lasna + Unichain Sepolia / Base Sepolia).

## Tracks
- Every Second Counts (USD 2,000 + 250): low-latency DeFi on Unichain Sepolia (1 s blocks) or Base Sepolia (200 ms);
  latency numbers measured across the full loop (origin event -> Reactive -> callback) are asked for.
- Set It and Forget It (USD 2,000 + 250): a reactive contract useful to yourself; AI-written code welcome.
- Reactive Meets AI (USD 1,000): a neural network inside the running loop.
Judging 1-5 on execution (reactive transactions and callbacks on-chain, else not scored further), integration,
usefulness, craft. Submit: public repo, deployed addresses, transaction hashes showing the loop, video under 3 min.
Everything built during the event; prior work only as a dependency.

## Plan (after Apart, from 9 Nov)
Track Every Second Counts: a withdrawal queue that settles the moment liquidity allows (fewer entrants than
stop-loss), with measured loop latency per chain. Fallback: Set It and Forget It.
Emil: Register on the DoraHacks page (his account). Payout in REACT: check its liquidity before counting on it.

## Build state (5 Nov night)
- src/InstantWithdrawalVault.sol (destination, AbstractCallback), src/QueueReactive.sol (Lasna, AbstractReactive,
  subscribes to LiquidityAdded and requests a settle() callback), src/MockUSD.sol; test/Queue.t.sol 9/9 pass
  (Foundry 1.9.0 in WSL, solc 0.8.29, reactive-lib-omni and forge-std vendored in lib/).
- Testnet deployer 0xd73Df821B8a0ea33Eb8c3437f04342fECcD8D816, key only in the git-ignored .env. (A first key was
  printed to the session log by a parsing slip; it was never funded or used.)
- script/deploy.sh unichain|base: MockUSD, vault (0.01 ETH for callback debt), reactive on Lasna (2 lREACT), wiring.
- Needs test funds: Unichain Sepolia ETH and/or Base Sepolia ETH for the deployer, and lREACT (send Sepolia or Base
  Sepolia ETH to the Lasna faucet: 1 ETH = 100 lREACT; Base Sepolia faucet 0x2afaFD298b23b62760711756088F75B7409f5967).
- Then: a latency script (liquidity tx time vs settle tx time, both chains), README, video.
