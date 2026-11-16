// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {UniswapV2Pair} from "../../../src/v2-core/UniswapV2Pair.sol";
import {MockERC20} from "../MockERC20.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

contract SpotOracle is IPriceOracle {
    UniswapV2Pair public immutable pair;
    bool private immutable wethIsToken0;

    constructor(UniswapV2Pair _pair, MockERC20 weth) {
        pair = _pair;
        wethIsToken0 = pair.token0() == address(weth);
    }

    function reserves() public view returns (uint256 wethReserve, uint256 usdcReserve) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        return wethIsToken0 ? (r0, r1) : (r1, r0);
    }

    function quote(uint256 wethAmount) public view override returns (uint256 usdcAmount) {
        (uint256 w, uint256 u) = reserves();
        return wethAmount * u / w;
    }
}
