// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TwapOracle} from "../mocks/twap/TwapOracle.sol";

/// @notice Run with `forge test --match-contract TwapOracleTest -vv` to see the price timeline.
contract TwapOracleTest is Test {
    MockERC20 internal weth;
    MockERC20 internal usdc;
    UniswapV2Pair internal pair;
    TwapOracle internal twapOracle;
    uint256 internal start;

    function setUp() public {
        start = block.timestamp;
        weth = new MockERC20(address(this), 100 ether, 18);
        usdc = new MockERC20(address(this), 200_000 * 1e6, 6);
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        pair = UniswapV2Pair(factory.createPair(address(weth), address(usdc)));

        // 100 WETH / 100,000 USDC: one WETH costs 1,000 USDC.
        weth.transfer(address(pair), 100 ether);
        usdc.transfer(address(pair), 100_000 * 1e6);
        pair.mint(address(this));

        twapOracle = new TwapOracle(pair, weth);
    }

    function test_requiresThirtyMinutesBeforeFirstQuote() public {
        vm.expectRevert(bytes("Oracle not ready"));
        twapOracle.quote(1 ether);

        vm.warp(start + 30 minutes - 1);
        vm.expectRevert(bytes("Window not elapsed"));
        twapOracle.update();

        vm.warp(start + 30 minutes);
        twapOracle.update();
        _assertTwap(1_000);
    }

    function test_priceRisesOverSuccessiveObservationWindows() public {
        // t=30: the first 30 minutes at 1,000 USDC/WETH establish the initial TWAP.
        vm.warp(start + 30 minutes);
        twapOracle.update();
        _assertTwap(1_000);

        // t=45: halfway through the next window, spot doubles.
        vm.warp(start + 45 minutes);
        _doubleSpotPrice();
        _assertTwap(1_000);

        vm.expectRevert(bytes("Window not elapsed"));
        twapOracle.update();

        // t=60: elapsed time alone does not change the saved quote.
        vm.warp(start + 60 minutes);
        _assertTwap(1_000);
        twapOracle.update();
        // (1,000 * 15 minutes + 2,000 * 15 minutes) / 30 minutes = 1,500.
        _assertTwap(1_500);

        // t=90: the next interval spent all 30 minutes at the new spot price.
        vm.warp(start + 90 minutes);
        twapOracle.update();
        _assertTwap(2_000);
    }

    function _doubleSpotPrice() internal {
        // A donation + sync creates an exact price step for this oracle test.
        // This isolates time weighting from swap fees and trade sizing.
        // sync() accumulates the OLD price up to now, then records the new reserves.
        usdc.transfer(address(pair), 100_000 * 1e6);
        pair.sync();
    }

    function _assertTwap(uint256 expectedUsdcPerWeth) internal view {
        // Q112 fixed-point division may round down by one USDC base unit (0.000001 USDC).
        assertApproxEqAbs(twapOracle.quote(1 ether), expectedUsdcPerWeth * 1e6, 1);
    }
}
