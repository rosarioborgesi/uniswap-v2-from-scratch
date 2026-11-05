// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";

/// @title UniswapV2Pair — State and Initialization
/// @notice Core AMM pair contract. Inherits the LP token (UniswapV2ERC20).
/// @dev This section covers state layout, initialization, safe transfers, and the reentrancy lock.
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using UQ112x112 for uint224;

    // ============ Constants ============
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    // ============ State Variables ============
    address public factory;
    address public token0;
    address public token1;

    // Stores the two reserves and a timestamp in a single slot (112 + 112 + 32 = 256 bit).
    // They are updated by the _update function. So they are updated when: mint, burn, swap or sync are called
    uint112 private reserve0; // Stored snapshot of token0 balance 
    uint112 private reserve1; // Stored snapshot of token1 balance
    uint32 private blockTimestampLast; // block.timestamp of the latest _update call % 2**32

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;

    // ============ Constructor ============
    constructor() {
        factory = msg.sender;
    }

    // ============ Reentrancy Guard ============

    /// @dev Prevents reentrancy. Sets unlocked to 0 before execution, 1 after.
    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // ============ View Functions ============

    /// @notice Returns the current reserves and the last block timestamp.
    /// @return _reserve0 The reserve of token0
    /// @return _reserve1 The reserve of token1
    /// @return _blockTimestampLast The timestamp of the last reserve update
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // ============ Internal Functions ============

    /// @dev Safe ERC-20 transfer that handles tokens which do not return a bool.
    /// @param token The token contract address
    /// @param to The recipient address
    /// @param value The amount to transfer
    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED");
    }

    // ============ Initialization ============

    /// @notice Called once by the factory at deploy time. Sets the two token addresses.
    /// @param _token0 Address of the first token in the pair
    /// @param _token1 Address of the second token in the pair
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    // ============ Reserve Update ============

    /// @dev Update reserves and, on the first call of each block, accumulate price.
    /// @param balance0 Current balance of token0 in the pair -> IERC20(token0).balanceOf(address(this))
    /// @param balance1 Current balance of token1 in the pair -> IERC20(token1).balanceOf(address(this))
    /// @param _reserve0 Previous reserve of token0 (from storage) -> this is updated by _update
    /// @param _reserve1 Previous reserve of token1 (from storage) -> this is updated by _update
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) internal {
        // Require balance0 and balance1 each fit in uint112
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "UniswapV2: OVERFLOW");

        // Truncate block.timestamp to uint32 (modulo 2^32)
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);

        // Calculate timeElapsed since last update inside unchecked
        uint32 timeElapsed;
        // (unchecked preserves the original uint32 wrapping behavior)
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }

        // If timeElapsed > 0 AND both reserves are nonzero, accumulate prices
        // _reserve0 and _reserve1 must not be zero otherwise we would be dividing for zero.
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // Use an unchecked block because overflow is intentional:
            unchecked {
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }

        // Store the new reserves (cast balances to uint112)
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        // Store the new block timestamp
        blockTimestampLast = blockTimestamp;

        // Emit Sync(reserve0, reserve1)
        emit Sync(reserve0, reserve1);
    }

    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        return (uint256(0), uint256(0));
    }

    function mint(address to) external returns (uint256 liquidity) {
        return uint256(0);
    }

    function skim(address to) external {}

    function sync() external {}

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external {}
}
