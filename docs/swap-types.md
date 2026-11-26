# Swap Types

Read each function name as “swap what I send for what I receive.” The word `Exact` tells you which amount you choose in advance. Each row is a separate one-hop example using the pools from the [router integration tests](../test/integration/RouterIntegrationTest.t.sol).

| Function | Example instruction | What happens in the test pool |
| --- | --- | --- |
| `swapExactTokensForTokens` | “Spend **exactly 1,000 A**. I’ll accept at least 2,000 B.” | You spend 1,000 A and receive 2,000 B. |
| `swapTokensForExactTokens` | “Buy **exactly 2,000 B**. Spend at most 1,001 A.” | You receive 2,000 B. The router pulls 1,000 A plus one base unit of A. |
| `swapExactETHForTokens` | “Spend **exactly 1 ETH**. I’ll accept at least 195 A.” | You spend 1 ETH and receive 200 A. |
| `swapTokensForExactETH` | “Buy **exactly 1 ETH**. Spend at most 1,010 A.” | You receive 1 ETH. The router pulls 1,000 A plus one base unit of A. |
| `swapExactTokensForETH` | “Spend **exactly 1,000 A**. I’ll accept at least 0.99 ETH.” | You spend 1,000 A and receive 1 ETH. |
| `swapETHForExactTokens` | “Buy **exactly 200 A**. I’ll send up to 2 ETH.” | You send 2 ETH. The router spends 1 ETH plus 1 wei, delivers 200 A, and refunds the rest to you. |

**“What can I get for this amount?”** Choose an exact-input swap. You fix what you spend and set the minimum output with `amountOutMin`.

**“What will it cost to buy this amount?”** Choose an exact-output swap. You fix what you receive and cap the input with `amountInMax` for tokens or `msg.value` for ETH.

In both cases, the swap reverts if the pool price can’t meet your limit.
