// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {UniswapV2Pair} from "../../../src/v2-core/UniswapV2Pair.sol";
import {MockERC20} from "../MockERC20.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/// @title WETH/USDC TWAP Oracle
/// @notice Values WETH in USDC using an average price over at least 30 minutes.
/// @dev Test-only adaptation of Uniswap V2's simple oracle.
contract TwapOracle is IPriceOracle {
    /// @notice Minimum time between price updates.
    uint256 public constant PERIOD = 30 minutes;

    uint256 private constant Q112 = 2 ** 112;

    /// @notice Pool used as the price source.
    UniswapV2Pair public immutable pair;

    bool private immutable wethIsToken0;

    /// @notice Cumulative price recorded at the previous observation.
    uint256 public cumulativeLast;

    /// @notice Time of the previous observation.
    uint32 public timestampLast;

    /// @notice Average price calculated by the latest update.
    uint256 public average;

    /// @notice Sets the pool and records the starting price observation.
    /// @param _pair Funded WETH/USDC pool.
    /// @param weth WETH token in the pool.
    constructor(UniswapV2Pair _pair, MockERC20 weth) {
        pair = _pair;
        wethIsToken0 = pair.token0() == address(weth);
        (cumulativeLast, timestampLast) = currentCumulative();
    }

    /// @notice Returns the pool's WETH and USDC reserves, in that order.
    function reserves() public view returns (uint256 wethReserve, uint256 usdcReserve) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        return wethIsToken0 ? (r0, r1) : (r1, r0);
    }

    /// @notice Returns the cumulative price and timestamp as of the current block.
    function currentCumulative() public view returns (uint256 cumulative, uint32 timestamp) {
        cumulative = wethIsToken0 ? pair.price0CumulativeLast() : pair.price1CumulativeLast();
        timestamp = uint32(block.timestamp);
        (,, uint32 lastUpdate) = pair.getReserves();
        (uint256 w, uint256 u) = reserves();
        // Preserve V2's intentional timestamp and accumulator wrapping.
        unchecked {
            cumulative += (u * Q112 / w) * uint32(timestamp - lastUpdate);
        }
    }

    /// @notice Saves the average price since the previous observation.
    /// @dev Requires at least 30 minutes; later updates average over a longer interval.
    function update() external {
        (uint256 cumulative, uint32 timestamp) = currentCumulative();
        uint32 elapsed;
        unchecked {
            elapsed = timestamp - timestampLast;
        }
        require(elapsed >= PERIOD, "Window not elapsed");
        unchecked {
            average = (cumulative - cumulativeLast) / elapsed;
        }
        cumulativeLast = cumulative;
        timestampLast = timestamp;
    }

    /// @notice Values WETH in USDC using the latest average price.
    /// @dev Requires a successful price update first.
    /// @param wethAmount WETH amount with 18 decimals.
    /// @return usdcAmount USDC value with 6 decimals.
    function quote(uint256 wethAmount) public view override returns (uint256 usdcAmount) {
        require(average != 0, "Oracle not ready");
        return wethAmount * average / Q112;
    }
}
