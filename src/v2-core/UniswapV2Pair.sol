// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";

/// @title UniswapV2Pair — State and Initialization
/// @notice Core AMM pair contract. Inherits the LP token (UniswapV2ERC20).
/// @dev This section covers state layout, initialization, safe transfers, and the reentrancy lock.
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    // ============ Constants ============
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    // ============ State Variables ============
    address public factory;
    address public token0;
    address public token1;

    // Stores the two reserves and a timestamp in a single slot,. Accessible via getReserves
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

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
        // TODO: Require unlocked == 1 ("UniswapV2: LOCKED")
        require(unlocked == 1, "UniswapV2: LOCKED");
        // TODO: Set unlocked = 0
        unlocked = 0;
        // TODO: Execute function body (_)
        _;
        // TODO: Set unlocked = 1
        unlocked = 1;
    }

    // ============ View Functions ============

    /// @notice Returns the current reserves and the last block timestamp.
    /// @return _reserve0 The reserve of token0
    /// @return _reserve1 The reserve of token1
    /// @return _blockTimestampLast The timestamp of the last reserve update
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        // TODO: Return the three stored values (reserve0, reserve1, blockTimestampLast)
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // ============ Internal Functions ============

    /// @dev Safe ERC-20 transfer that handles tokens which do not return a bool.
    /// @param token The token contract address
    /// @param to The recipient address
    /// @param value The amount to transfer
    function _safeTransfer(address token, address to, uint256 value) private {
        // TODO: Execute a low-level call using abi.encodeWithSelector(SELECTOR, to, value)
        //       (bool success, bytes memory data) = token.call(...)
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        // TODO: Require success AND (data is empty OR decoded as true)
        //       require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED")
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED");
    }

    // ============ Initialization ============

    /// @notice Called once by the factory at deploy time. Sets the two token addresses.
    /// @param _token0 Address of the first token in the pair
    /// @param _token1 Address of the second token in the pair
    function initialize(address _token0, address _token1) external {
        // TODO: Require msg.sender == factory ("UniswapV2: FORBIDDEN")
        require(msg.sender == factory, "UniswapV2: FORBIDDEN");
        // TODO: Set token0 = _token0
        token0 = _token0;
        // TODO: Set token1 = _token1
        token1 = _token1;
    }
}
