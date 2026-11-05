# Instant Withdrawal Queue

A vault whose withdrawal queue is paid the moment liquidity comes back. No keeper, no cron job, no user
pressing "claim". A Reactive Network contract watches the vault. When liquidity returns, it calls the vault
through a cross-chain callback, and the vault pays the queue in order.

Built for the Reactive Omni Buildathon, track **Every Second Counts**. Demo video (2 min): https://youtu.be/bQYzj3lHLnI

Measured on Base Sepolia: **liquidity returned -> queued withdrawal paid in 1-2 seconds (6-11 blocks)**, five
runs out of five. The table below gives every transaction.

## The problem

Lending vaults, liquid staking and yield vaults lend out most of their deposits. When a user withdraws
more than the vault holds, the request waits in a queue. Today someone has to notice that liquidity came
back and push the queue forward: a keeper bot, a cron job or the user clicking again. Keepers cost money,
go down, and skip small queues that are not worth their gas. Users wait minutes or hours for money that is
already sitting in the vault.

## How it works

```
 Base Sepolia                         Reactive Network (Lasna)                Base Sepolia
 ------------                         ------------------------                ------------
 InstantWithdrawalVault               QueueReactive                           callback proxy
   addLiquidity(amount)                 subscribed to LiquidityAdded            0x476F44b1...
   emits LiquidityAdded(  ----------->  react(log):                           |
     amount, idle, queuedTotal)           if queuedTotal > 0                  |
                                            requestCallback(settle) --------> settle(rvm, block, 25)
                                                                                pays the queue head first,
                                                                                emits WithdrawalPaid
```

- `src/InstantWithdrawalVault.sol` (destination chain). Deposits sit as idle liquidity until the owner lends part
  of them out (`deployLiquidity`). `requestWithdrawal` pays at once if idle liquidity covers it and nobody is
  waiting; otherwise it joins a FIFO queue. `addLiquidity` emits `LiquidityAdded(amount, idle, queuedTotal)`.
  `settle` pays from the head of the queue as far as idle liquidity reaches, at most `maxItems` per call, and
  records each request's wait in `WithdrawalPaid(id, user, amount, waitSeconds, waitBlocks)`.
- `src/QueueReactive.sol` (Reactive Network). Subscribes to `LiquidityAdded` on one vault. `react` decodes the
  event and requests a `settle` callback only when something is queued, so an idle vault costs nothing.
- `src/MockUSD.sol`. A 6-decimal test token with an open faucet `mint`, for the demo.

### Safety

- `settle` is `onlyServiceProvider`: only the Reactive callback proxy can call it.
- The proxy writes the calling reactive contract into the first argument. The vault checks it against
  `callbackSender`, which is set once by the owner, so another reactive contract cannot drive this vault.
- `react` is `onlySystem`, and it ignores logs from any other contract or topic.
- The queue is strictly first in, first out. A later small request never jumps a large one at the head, even
  when it would fit (`test_queueIsFifoEvenWhenALaterRequestWouldFit`).
- `maxItems` (25) bounds the gas of one callback. If liquidity covers more, the next `LiquidityAdded` continues.

## Deployed (testnet)

| Contract | Chain | Address |
|---|---|---|
| InstantWithdrawalVault | Base Sepolia (84532) | [0x6A9B129a673C4d2416A9959505C4EAEE501781f1](https://sepolia.basescan.org/address/0x6A9B129a673C4d2416A9959505C4EAEE501781f1) |
| MockUSD | Base Sepolia (84532) | [0xA0327B3C2e4297d1d18B70414bbe91BDeF2b684B](https://sepolia.basescan.org/address/0xA0327B3C2e4297d1d18B70414bbe91BDeF2b684B) |
| QueueReactive | Reactive Lasna (5318007) | [0xA0327B3C2e4297d1d18B70414bbe91BDeF2b684B](https://lasna.reactscan.net/address/0xA0327B3C2e4297d1d18B70414bbe91BDeF2b684B?screen=callbacks) |

MockUSD and QueueReactive share an address because both were the deployer's first contract on their chain.

## Measured latency

`script/e2e.sh base` deposits, lends out everything but 100 mUSD, requests a 300 mUSD withdrawal (it is
queued), returns 300 mUSD with `addLiquidity`, and waits for the queue to empty. Latency is the block
timestamp of the `Settled` event minus the block timestamp of the `addLiquidity` transaction, so it covers
the whole loop: origin event, Reactive Network, callback, payout. Run on 6 Nov 2026 (`latency.csv`):

| Run | Blocks | Seconds | addLiquidity tx | settle tx (callback) |
|---|---|---|---|---|
| 1 | 7 | 2 | [0xdecbb45c...](https://sepolia.basescan.org/tx/0xdecbb45cfb6b684b2fccd8722b8de31644a27f78ecc434eb33cf28a93a44c682) | [0x59f53f95...](https://sepolia.basescan.org/tx/0x59f53f950ddad0e7c9b1672fc402efbd0cabfa244e974854b209fae4ddf190a2) |
| 2 | 10 | 2 | [0x0276880c...](https://sepolia.basescan.org/tx/0x0276880c9edaaf7b0447be262ddd3eafd6d796b20f3a1acf59d417f3e94fb7a8) | [0x814d51da...](https://sepolia.basescan.org/tx/0x814d51daaa0d9a4d8afd16e565f7b16b44fb3582e35bfd7b833ff94f47ee575b) |
| 3 | 11 | 2 | [0x69695bec...](https://sepolia.basescan.org/tx/0x69695bec2a04a7669e8a46c307ac1d80cb550b658c6be45ed7dba15c9e0dbcad) | [0x4d5a6b94...](https://sepolia.basescan.org/tx/0x4d5a6b94bbc376dc910f83437b27ff862055e0e55390dadb32bca708af2b24e9) |
| 4 | 10 | 2 | [0x3a47fc15...](https://sepolia.basescan.org/tx/0x3a47fc157b2a225e410efd47268fb5e9fb88563a0c62202d52254190afb04b6f) | [0x1ac19907...](https://sepolia.basescan.org/tx/0x1ac19907769b15a9b0f9325646aef135ec0233bbd5a070a5e3ae04a6cbf44d4c) |
| 5 | 6 | 1 | [0x330ee609...](https://sepolia.basescan.org/tx/0x330ee609ab6184df8e52c38994773a48a65523ed2096257453bcedd488312ffb) | [0xfd008043...](https://sepolia.basescan.org/tx/0xfd00804317e86a18fae521e7844ad7658871dd8cb5ac5bcb8a4baa17b59c760e) |

Block timestamps have one-second resolution, so "1" and "2" mean "within that second". Every settle
transaction appears as a confirmed callback of QueueReactive on
[Reactscan](https://lasna.reactscan.net/address/0xA0327B3C2e4297d1d18B70414bbe91BDeF2b684B?screen=callbacks),
with the Lasna request transaction that produced it.

## Run it

Requires [Foundry](https://getfoundry.sh). `lib/` vendors `reactive-lib` and `forge-std`.

```bash
forge test                      # 9 tests, with a mock of the Reactive system contract
cp .env.example .env            # DEPLOYER_ADDRESS, DEPLOYER_KEY (testnet only)
script/deploy.sh base           # or: unichain. Writes deployed-base.env
script/e2e.sh base              # one full loop; appends a row to latency.csv
```

The deployer needs Base Sepolia (or Unichain Sepolia) ETH, about 0.011, and about 1.6 lREACT on Lasna
(send Sepolia ETH to the Lasna faucet `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`, 1 ETH = 100 lREACT).
Each callback cost QueueReactive about 0.02 lREACT in this run.

## Limits

- One vault per reactive contract, and a test token. A real vault would plug in its own asset and lending
  logic; the queue and the callback do not change.
- A request is paid in full or waits. Partial payment of the head request is left out on purpose, to keep
  the order simple.
- Liquidity that reaches the vault by a plain token transfer, without `addLiquidity`, does not trigger a
  settlement until the next `LiquidityAdded`.

## License

MIT
