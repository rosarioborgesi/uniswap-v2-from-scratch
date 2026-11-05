// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockUSDT} from "../mocks/MockUSDT.sol";

contract UniswapV2PairHarness is UniswapV2Pair {
    function update(uint256 balance0, uint256 balance1) external {
        (uint112 oldReserve0, uint112 oldReserve1,) = getReserves();
        _update(balance0, balance1, oldReserve0, oldReserve1);
    }

    function safeTransfer(address token, address to, uint256 value) external {
        _safeTransfer(token, to, value);
    }
}

contract UniswapV2PairUnitTest is Test {
    UniswapV2PairHarness internal pair;
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        pair = new UniswapV2PairHarness();
    }

    ///////////////////////////////////////
    //            _safeTransfer          //
    ///////////////////////////////////////
    function test_SafeTransferCanTransferERC20() public {
        MockERC20 token = new MockERC20(address(pair), 100);

        pair.safeTransfer(address(token), recipient, 40);

        assertEq(token.balanceOf(address(pair)), 60);
        assertEq(token.balanceOf(recipient), 40);
    }

    function test_SafeTransferCanTransferUSDT() public {
        MockUSDT token = new MockUSDT(address(pair), 100);

        pair.safeTransfer(address(token), recipient, 40);

        assertEq(token.balanceOf(address(pair)), 60);
        assertEq(token.balanceOf(recipient), 40);
    }

    /////////////////////////////////
    //            _update          //
    /////////////////////////////////
    function test_FirstUpdateStoresReservesAndTimestampAndEmitsSync() public {
        vm.warp(100);
        
        pair.update(10, 20);

        (uint112 reserve0, uint112 reserve1, uint32 timestamp) = pair.getReserves();
        assertEq(reserve0, 10);
        assertEq(reserve1, 20);
        assertEq(timestamp, 100);
        assertEq(pair.price0CumulativeLast(), 0);
        assertEq(pair.price1CumulativeLast(), 0);
    }

    function test_UpdateAccumulatesPricesUsingPreviousReserves() public {
        uint256 q112 = uint256(1) << 112;

        vm.warp(100);
        pair.update(10, 20);

        // The first ten seconds use the old reserves (10, 20).
        vm.warp(110);
        pair.update(40, 10);

        // Calculate the expected cumulative price increases over 10 seconds, using the previous reserves (10, 20)
        // For price0, the ratio is reserve1 / reserve0:
        // 20 / 10 = 2
        // Encoded price (2 * q112) × elapsed seconds (10):
        uint256 expectedPrice0 = 2 * q112 * 10;

        // For price1, the ratio is the inverse, reserve0 / reserve1:
        // 10 / 20 = 0.5
        // Encoded price (q112 / 2) × elapsed seconds (10):
        uint256 expectedPrice1 = (q112 / 2) * 10;
        assertEq(pair.price0CumulativeLast(), expectedPrice0);
        assertEq(pair.price1CumulativeLast(), expectedPrice1);

        (uint112 reserve0, uint112 reserve1, uint32 timestamp) = pair.getReserves();
        assertEq(reserve0, 40);
        assertEq(reserve1, 10);
        assertEq(timestamp, 110);

        // The next four seconds use (40, 10), adding to the existing totals.
        vm.warp(114);
        pair.update(40, 10);

        // Between timestamps 110 and 114, the reserves are (40, 10) and 4 seconds pass:
        // Price0: reserve1 / reserve0 = 10 / 40 = 0.25. 
        // Its encoded value is q112 / 4, time elapsed 4 seconds, so we add (q112 / 4) * 4.
        uint256 expectedPrice0AfterSecondInterval = expectedPrice0 + (q112 / 4) * 4;

        // Price1: reserve0 / reserve1 = 40 / 10 = 4. 
        // Its encoded value is 4 * q112, time elapsed 4 seconds, so we add 4 * q112 * 4.
        uint256 expectedPrice1AfterSecondInterval = expectedPrice1 + 4 * q112 * 4;        
        
        assertEq(pair.price0CumulativeLast(), expectedPrice0AfterSecondInterval);
        assertEq(pair.price1CumulativeLast(), expectedPrice1AfterSecondInterval);
    }
}
