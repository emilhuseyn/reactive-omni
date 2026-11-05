# DoraHacks submission draft (Emil presses Submit for Review)

Before submitting: repo public (Emil's call), video uploaded to YouTube as unlisted (Emil), link both below.

## Create new Build

- **Name:** Instant Withdrawal Queue
- **Tagline:** A vault whose withdrawal queue is paid the moment liquidity comes back. No keeper.
- **Logo:** `video/logo.png`
- **Track:** Every Second Counts
- **GitHub:** https://github.com/emilhuseyn/reactive-omni
- **Demo video:** <YouTube link>
- **Tags:** Reactive Network, DeFi, Base, Solidity

**Description:**

Lending and yield vaults lend out most of their deposits, so a large withdrawal waits in a queue. Today
someone has to notice that liquidity came back and push the queue forward: a keeper bot, a cron job or the
user clicking again. Keepers cost money, go down, and skip queues too small to be worth their gas, while the
money already sits in the vault.

Instant Withdrawal Queue removes that step. The vault on Base Sepolia emits `LiquidityAdded(amount, idle,
queuedTotal)` whenever liquidity returns. `QueueReactive` on Reactive Lasna is subscribed to that event; when
something is queued it requests a callback, and the vault's `settle()` pays the queue strictly first in, first
out, at most 25 requests per callback.

Measured on Base Sepolia, five runs out of five: liquidity returned to queued withdrawal paid in 1-2 seconds
(6-11 blocks), every payout sent by Reactive Network and listed as a confirmed callback on Reactscan.

Safety: `settle()` is `onlyServiceProvider` and checks that the reactive contract named by the proxy is ours
(set once); `react()` is `onlySystem` and ignores other contracts and topics; an idle vault requests no
callbacks. Nine Foundry tests, with a mock of the Reactive system contract, cover the queue order, partial
liquidity, access control and the callback payload.

## Organizer questions

**Deployed contract addresses, and which network (Reactive mainnet or Lasna)?**

Lasna testnet. QueueReactive (reactive contract, Lasna 5318007): 0xA0327B3C2e4297d1d18B70414bbe91BDeF2b684B.
InstantWithdrawalVault (callback contract, Base Sepolia 84532): 0x6A9B129a673C4d2416A9959505C4EAEE501781f1.
MockUSD test token (Base Sepolia): 0xA0327B3C2e4297d1d18B70414bbe91BDeF2b684B (same address as the reactive
contract because both were the deployer's first deployment on their chain).

**Transaction hashes showing the full loop, from origin event to callback.**

Run 5: origin `addLiquidity` on Base Sepolia 0x330ee609ab6184df8e52c38994773a48a65523ed2096257453bcedd488312ffb
-> callback `settle` on Base Sepolia 0xfd00804317e86a18fae521e7844ad7658871dd8cb5ac5bcb8a4baa17b59c760e
(listed on Reactscan as a confirmed callback of QueueReactive, request tx 0x19c0b8...a31a69d7).
Run 4: 0x3a47fc157b2a225e410efd47268fb5e9fb88563a0c62202d52254190afb04b6f -> 0x1ac19907769b15a9b0f9325646aef135ec0233bbd5a070a5e3ae04a6cbf44d4c.
Run 1: 0xdecbb45cfb6b684b2fccd8722b8de31644a27f78ecc434eb33cf28a93a44c682 -> 0x59f53f950ddad0e7c9b1672fc402efbd0cabfa244e974854b209fae4ddf190a2.
All five runs are in latency.csv and the README.

**For Every Second Counts: what full-loop latency did you measure, and how?**

1-2 seconds, 6-11 Base Sepolia blocks, from the origin transaction to the payout, in 5 of 5 runs.
`script/e2e.sh` queues a 300 mUSD withdrawal against 100 mUSD of idle liquidity, returns 300 mUSD with
`addLiquidity`, then polls the vault until the queue is empty. Latency = block timestamp of the `Settled`
event minus block timestamp of the `addLiquidity` transaction (one-second resolution), plus the block count.
So it covers origin event, Reactive Network, callback delivery and the payout itself.

**Was this your first time building with Reactive? Your first smart contract?**

First time building with Reactive. Not my first smart contract.

**What was the hardest part of building with Reactive?**

Getting the callback authorization right: the proxy overwrites the first argument of the payload with the
reactive contract's address, so `settle` has to take that address as its first parameter and check it
against the one reactive contract allowed to drive the vault. Unit-testing `react()` without the network
also took a mock of the system contract at 0x8888...8888.

**How did you hear about the buildathon?**

DoraHacks hackathon listings.

**Looking for teammates:** No
