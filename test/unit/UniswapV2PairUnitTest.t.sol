// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockUSDT} from "../mocks/MockUSDT.sol";

contract UniswapV2PairHarness is UniswapV2Pair {
    function safeTransfer(address token, address to, uint256 value) external {
        _safeTransfer(token, to, value);
    }
}

///////////////////////////////////////
//            _safeTransfer          //
///////////////////////////////////////
contract UniswapV2PairSafeTransferTest is Test {
    UniswapV2PairHarness internal pair;
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        pair = new UniswapV2PairHarness();
    }

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
}
