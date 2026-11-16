// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {UniswapV2Library} from "../../src/v2-periphery/libraries/UniswapV2Library.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

import {SpotOracle} from "../mocks/twap/SpotOracle.sol";
import {TwapOracle} from "../mocks/twap/TwapOracle.sol";
import {LendingMock} from "../mocks/twap/LendingMock.sol";
import {FlashLenderMock} from "../mocks/twap/FlashLenderMock.sol";
import {Attacker} from "../mocks/twap/Attacker.sol";

/// @notice 100 WETH / 100,000 USDC initially prices WETH at $1,000.
/// Compares the same atomic flash-loan attack against spot and TWAP lending pools.
contract TwapManipulationTest is Test {
    MockERC20 internal weth;
    MockERC20 internal usdc;
    UniswapV2Router02 internal router;
    SpotOracle internal spotOracle;
    TwapOracle internal twapOracle;
    LendingMock internal pool;
    FlashLenderMock internal lender;

    // This is the USDC amount needed to flash borrow to raise WETH's spot price from $1,000 to $3,000.
    uint256 constant FLASH_AMOUNT = 73_315_088_302;

    function setUp() public {
        weth = new MockERC20(address(this), 120 ether, 18);
        usdc = new MockERC20(address(this), 400_000 * 1e6, 6);

        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));

        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);

        // The pool WETH-USDC starts with 100,000 USDC and 100, WETH so WETH price is $1,000
        router.addLiquidity(
            address(weth),
            address(usdc),
            100 ether,
            100_000 * 1e6,
            100 ether,
            100_000 * 1e6,
            address(this),
            block.timestamp
        );

        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(address(weth), address(usdc)));
        
        spotOracle = new SpotOracle(pair, weth);
        twapOracle = new TwapOracle(pair, weth);
        
        lender = new FlashLenderMock(usdc);
        usdc.transfer(address(lender), 200_000 * 1e6);
    }

    // The test proves that the attacker can borrow about 15,000 USDC against collateral worth only about 10,000 USDC, by temporarily inflating WETH’s spot price.
    /// @notice Spot pricing allows an inflated loan during flash-loan price manipulation.
    function test_spotOracleAllowsFifteenThousandDuringFlashLoanAttack() public {
        pool = new LendingMock(weth, usdc, spotOracle);
        usdc.transfer(address(pool), 50_000 * 1e6);

        // Before the attack, the oracle values one WETH at exactly 1,000 USDC.
        assertEq(spotOracle.quote(1 ether), 1_000 * 1e6);

        Attacker attacker = new Attacker(router, pool, lender);
        weth.transfer(address(attacker), 10 ether);

        // Allow 30 minutes at the original pool price before the atomic attack.
        vm.warp(block.timestamp + 30 minutes);

        uint256 lenderBefore = usdc.balanceOf(address(lender));

        // What happens inside attacker.attack:
        // 1. Flash-borrows 73,315.088302 USDC.
        // 2. Swaps it for WETH, pushing WETH’s spot price to about $3,000.
        // 3. Deposits its original 10 WETH as collateral and borrows about 15,000 USDC using the inflated price.
        // 4. Sells the purchased WETH back, returning the price close to $1,000.
        // 5. Repays the flash loan plus its fee.
        attacker.attack(FLASH_AMOUNT);

        // Verify the attacker left 10 WETH as collateral.
        assertEq(pool.collateral(address(attacker)), 10 ether);

        // The flash lender has received its money back + fees
        // - lenderBefore includes the principal before it was lent out.
        // - FLASH_AMOUNT * 9 / 10_000 represents the the flash loans fees.
        assertEq(usdc.balanceOf(address(lender)), lenderBefore + FLASH_AMOUNT * 9 / 10_000);

        // Verify the price returned close to $1,000.
        // Here, the accepted price is $997–$1,003 per WETH
        assertApproxEqAbs(spotOracle.quote(1 ether), 1_000 * 1e6, 3 * 1e6);

        // Verify the inflated borrowing succeeded.
        // Spot pricing accepts $15,000 against 10 WETH during the $3,000 spike.
        assertApproxEqAbs(attacker.borrowed(), 15_000 * 1e6, 1);

        // Verify attackers debt is 15,000 USDC
        assertApproxEqAbs(pool.debt(address(attacker)), 15_000 * 1e6, 1);

        // Verify the remaining debt exceeds the collateral’s value.
        // 15,000 USDC debt > 10,000 USDC collateral value
        assertGt(pool.debt(address(attacker)), spotOracle.quote(10 ether));

        // Swap fees leave the spot price slightly above its starting value.
        // Swap fees leave the final price slightly higher, so 10 WETH is worth 10,025.407289 USDC
        // So we added 30 USDC of tolerance.
        assertApproxEqAbs(spotOracle.quote(10 ether), 10_000 * 1e6, 30 * 1e6);
    }

    // The test proves that the attacker can borrow about 5,000 USDC 
    // against collateral worth only about 10,000 USDC, and cannot inflate WETH’s spot price.
    /// @notice TWAP pricing preserves the borrowing limit during the same manipulation.
    function test_twapAllowsFiveThousandDuringFlashLoanAttack() public {
        pool = new LendingMock(weth, usdc, twapOracle);
        usdc.transfer(address(pool), 50_000 * 1e6);

        // Establish the normal TWAP over its required 30-minute observation period.
        vm.warp(block.timestamp + 30 minutes);
        twapOracle.update();
        // Before the attack, one WETH is worth $1,000, allowing one USDC base unit of rounding.
        assertApproxEqAbs(twapOracle.quote(1 ether), 1_000 * 1e6, 1);

        Attacker attacker = new Attacker(router, pool, lender);
        weth.transfer(address(attacker), 10 ether);

        uint256 lenderBefore = usdc.balanceOf(address(lender));

        // What happens inside attacker.attack:
        // 1. Flash-borrow USDC and buy WETH to push its spot price to about $3,000.
        // 2. Deposit the original 10 WETH as collateral and borrow against it.
        // 3. The saved TWAP stays near $1,000, so the 50% LTV limits borrowing to about $5,000.
        // 4. Sell the purchased WETH back and repay the flash loan plus its fee.
        attacker.attack(FLASH_AMOUNT);

        // Verify the attacker left 10 WETH as collateral.
        assertEq(pool.collateral(address(attacker)), 10 ether);

        // The flash lender has received its money back + fees
        // - lenderBefore includes the principal before it was lent out.
        // - FLASH_AMOUNT * 9 / 10_000 represents the the flash loans fees.
        assertEq(usdc.balanceOf(address(lender)), lenderBefore + FLASH_AMOUNT * 9 / 10_000);

        // Verify the price is close to $1,000.
        // Here, the accepted price is $997–$1,003 per WETH
        assertApproxEqAbs(twapOracle.quote(1 ether), 1_000 * 1e6, 1);

        // Verify the inflated borrowing didn't succeed
        // TWAP pricing accepts $5,000 against 10 WETH during the $3,000 spike.
        assertApproxEqAbs(attacker.borrowed(), 5_000 * 1e6, 1);

        // Verify the remaining debt is lower than the collateral’s value.
        // 5,000 USDC debt < 10,000 USDC collateral value
        assertLt(pool.debt(address(attacker)), twapOracle.quote(10 ether));
        // TWAP fixed-point rounding can leave the debt one USDC base unit below $5,000.
        assertApproxEqAbs(pool.debt(address(attacker)), 5_000 * 1e6, 1);

        assertApproxEqAbs(twapOracle.quote(10 ether), 10_000 * 1e6, 1);
    }
}
