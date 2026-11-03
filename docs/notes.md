# Notes

## UniswapV2ERC20
[UniswapV2ERC20.sol (line 102)](../src/v2-core/UniswapV2ERC20.sol) implements an ERC-20 LP token extended with EIP-2612 permit.

`permit` lets the token owner authorize an allowance by signing an off-chain message, instead of submitting an approve transaction. Anyone can submit that signature on-chain and pay the gas. This is the extension defined by EIP-2612.