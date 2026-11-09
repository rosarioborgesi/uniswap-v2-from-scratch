// SPDX-License-Identifier: GPL-3.0-or-later
// swap adapted from Uniswap v2-core/contracts/UniswapV2Pair.sol for Solidity 0.8.35.
pragma solidity 0.8.35;

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";
import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";
import {Math} from "./libraries/Math.sol";

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

    /// @dev If time has elapsed since the last update and both previous reserves are nonzero,
    /// adds each price derived from those reserves multiplied by the elapsed seconds to its cumulative accumulator.
    /// Then records the supplied balances as reserves, stores the current timestamp modulo 2^32.
    /// @param balance0 Current token0 balance of the pair; must fit in uint112.
    /// @param balance1 Current token1 balance of the pair; must fit in uint112.
    /// @param _reserve0 Recorded token0 reserve before this update, used to calculate the price over the elapsed interval.
    /// @param _reserve1 Recorded token1 reserve before this update, used to calculate the price over the elapsed interval.
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

    // ============ Protocol Fee ============

    /// @dev If fees are enabled, mint LP tokens representing one-sixth of the growth in sqrt(k).
    /// @param _reserve0 Reserve of token0 before the current liquidity event
    /// @param _reserve1 Reserve of token1 before the current liquidity event
    /// @return feeOn Whether the factory has enabled protocol fees
    function _mintFee(uint112 _reserve0, uint112 _reserve1) internal returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;

        if (feeOn) {
            if (_kLast != 0) {
                // Widen before multiplying; Solidity 0.8 checks arithmetic for overflow.
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast);
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // ============ Mint Function ============

    /// @notice Mints LP tokens to `to`. Tokens must be transferred to the pair before calling.
    /// @param to The address to receive LP tokens
    /// @return liquidity The amount of LP tokens minted
    function mint(address to) external lock returns (uint256 liquidity) {
        // Important distinction
        // - Reserves are the balances recorded during the previous update
        // - Balances are the tokens the pair actually holds now.

        // 1. Calculate how much was deposited
        // Read current reserves
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        // Read actual token balances of this contract
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Calculate amounts deposited
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        // 2. Settle any protocol fee
        // May mint LP tokens to the factory’s feeTo address,
        bool feeOn = _mintFee(_reserve0, _reserve1);

        // Read totalSupply AFTER _mintFee (it may have changed totalSupply)
        uint256 _totalSupply = totalSupply;

        // 3. Calculate the depositor’s LP tokens
        if (_totalSupply == 0) {
            // First deposit
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock minimum, this makes share inflation attacks more expensive.
        } else {
            // Subsequent deposits
            liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }

        // 4. Mint and record the new state
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");

        // Mint LP tokens to the recipient (increases LP totalSupply and balanceOf[to])
        _mint(to, liquidity);

        // _update records the new reserves and updates the cumulative price accounting.
        _update(balance0, balance1, _reserve0, _reserve1);

        // If protocol fees are enabled, kLast is then set to the new reserve product
        // as the baseline for future fee calculations.
        if (feeOn) {
            kLast = uint256(reserve0) * reserve1;
        }

        emit Mint(msg.sender, amount0, amount1);
    }

    // ============ Burn Function ============

    /// @notice Burns LP tokens and sends proportional amounts of both tokens to `to`.
    /// @dev LP tokens must be transferred to the pair before calling this function.
    /// @param to The address to receive the withdrawn tokens
    /// @return amount0 The amount of token0 withdrawn
    /// @return amount1 The amount of token1 withdrawn
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        // Read current reserves
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        // Read token addresses into local variables (gas optimization)
        address _token0 = token0;
        address _token1 = token1;

        // Read actual token balances of this contract
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));

        // Read LP token balance sent to this contract (the amount to burn)
        uint256 liquidity = balanceOf[address(this)];

        // Call _mintFee and capture the return value
        bool feeOn = _mintFee(_reserve0, _reserve1);

        // Read totalSupply AFTER _mintFee (it may have changed totalSupply)
        uint256 _totalSupply = totalSupply;

        // Calculate proportional withdrawal amounts
        amount0 = liquidity * balance0 / _totalSupply;
        amount1 = liquidity * balance1 / _totalSupply;

        // Require both amounts > 0
        require(amount0 > 0 && amount1 > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");

        // Burn the LP tokens from this contract
        _burn(address(this), liquidity);

        // Transfer both tokens to the recipient
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);

        // Read new balances after transfer
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        // Update reserves
        _update(balance0, balance1, _reserve0, _reserve1);

        // If feeOn, store kLast = uint256(reserve0) * reserve1
        if (feeOn) {
            kLast = uint256(reserve0) * reserve1;
        }

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function skim(address to) external {}

    function sync() external {}

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
            require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * 1000 ** 2, "UniswapV2: K");
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
}
