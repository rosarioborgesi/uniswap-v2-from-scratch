// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";
import {UniswapV2Router02} from "../../src/v2-periphery/UniswapV2Router02.sol";
import {IUniswapV2Callee} from "../../src/v2-core/interfaces/IUniswapV2Callee.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAaveV1LendingPool} from "../mocks/MockAaveV1LendingPool.sol";

/// @dev Test-only liquidator. Borrows USDC and repays the same pair in seized WETH.
contract FlashSwapLiquidator is IUniswapV2Callee {
    UniswapV2Pair public immutable pair;
    MockAaveV1LendingPool public immutable pool;
    MockERC20 public immutable weth;
    MockERC20 public immutable usdc;

    constructor(UniswapV2Pair _pair, MockAaveV1LendingPool _pool) {
        pair = _pair;
        pool = _pool;
        weth = _pool.weth();
        usdc = _pool.usdc();
    }

    function liquidate(uint256 flashAmount, uint256 purchaseAmount) external {
        // 1. Find which token is USDC
        bool usdcIsToken0 = pair.token0() == address(usdc);
        // 2. Requesting USDC from the pair in eaxchange for WETH
        // Because data is nonempty, the pair then calls our uniswapV2Call()
        pair.swap(
            usdcIsToken0 ? flashAmount : 0, usdcIsToken0 ? 0 : flashAmount, address(this), abi.encode(purchaseAmount)
        );
        // 3. Only distribute profit (WETH) after swap has returned successfully.
        weth.transfer(msg.sender, weth.balanceOf(address(this)));
    }

    // runs after the pair sends the borrowed USDC, but before it checks repayment. 
    // It uses that window to liquidate the Aave position.
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        // 1. Validate the callback
        require(msg.sender == address(pair) && sender == address(this), "Invalid callback");
        
        // 2. Identify the borrowed USDC amount
        // amount0 and amount1 are the tokens the pair sent out. 
        // We select the USDC amount and check that no WETH was borrowed.
        bool usdcIsToken0 = pair.token0() == address(usdc);
        uint256 borrowed = usdcIsToken0 ? amount0 : amount1;
        require((usdcIsToken0 ? amount1 : amount0) == 0 && borrowed > 0, "Wrong flash asset");

        // 3. Calculate the WETH needed to repay Uniswap
        // getReserves() still returns the reserves from before the flash swap.
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 usdcReserve = usdcIsToken0 ? reserve0 : reserve1;
        uint256 wethReserve = usdcIsToken0 ? reserve1 : reserve0;
        // This formula calculates the WETH input required for the USDC output, 
        // including Uniswap’s 0.3% fee and price impact. 
        // The + 1 rounds up so repayment is sufficient.
        uint256 wethRepayment = wethReserve * borrowed * 1000 / ((usdcReserve - borrowed) * 997) + 1;

        // 4. Liquidate the Aave position
        usdc.approve(address(pool), borrowed);
        // false requests the underlying WETH rather than aTokens.
        pool.liquidationCall(address(weth), address(usdc), pool.borrower(), abi.decode(data, (uint256)), false);
        
        // 5. Check the result and repay the pair
        // Checks confirm all borrowed USDC was used.
        require(usdc.balanceOf(address(this)) == 0, "Unused flash funds");
        // Checks that the received collateral covers repayment with a profit.
        // The liquidator starts with zero WETH, so its balance is the collateral received from liquidation.
        require(weth.balanceOf(address(this)) > wethRepayment, "Unprofitable liquidation");

        // Direct transfer settles the original swap. A nested swap on this pair is locked.
        weth.transfer(address(pair), wethRepayment);
    }
}

// Test scenario:
// 1. Borrower deposits 1 WETH at $4,000 and borrows 2,500 USDC on the Aave V1 mock.
// 2. WETH falls to $3,000, making the position liquidatable at the 80% liquidation threshold.
// 3. Uniswap V2 pair holds 100 WETH / 300,000 USDC, giving a spot price of $3,000 per WETH.
// 4. Liquidator flash borrows 1,250 USDC from the Uniswap V2 pair.
// 5. Liquidator requests repayment of the full 2,500 USDC debt, but Aave V1's 50% cap
//    limits actual repayment to 1,250 USDC.
// 6. Liquidator receives approximately 0.4375 WETH, including the 5% liquidation bonus.
// 7. Liquidator repays the pair with approximately 0.419669 WETH and sends the remaining
//    0.017831 WETH to the keeper as profit—about $53.49 before gas.
contract FlashSwapLiquidationTest is Test {
    MockERC20 weth;
    MockERC20 usdc;
    UniswapV2Pair pair;
    MockAaveV1LendingPool pool;
    FlashSwapLiquidator liquidator;
    address borrower = makeAddr("borrower");
    address keeper = makeAddr("keeper");
    address feeCollector = makeAddr("feeCollector");

    uint256 constant WETH_RESERVE = 100 ether;
    uint256 constant USDC_RESERVE = 300_000e6;
    uint256 constant DEBT = 2_500e6;
    uint256 constant FLASH_AMOUNT = DEBT / 2;

    function setUp() public {
        weth = new MockERC20(address(this), 101 ether, 18);
        usdc = new MockERC20(address(this), USDC_RESERVE + DEBT, 6);
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        UniswapV2Router02 router = new UniswapV2Router02(address(factory), address(weth));

        // Seed the UniswapV2 pool with 300,000 USDC and 100 WETH -> So the WETH price is 3,000 $
        weth.approve(address(router), WETH_RESERVE);
        usdc.approve(address(router), USDC_RESERVE);
        router.addLiquidity(
            address(weth),
            address(usdc),
            WETH_RESERVE,
            USDC_RESERVE,
            WETH_RESERVE,
            USDC_RESERVE,
            makeAddr("liquidityProvider"),
            block.timestamp
        );
        pair = UniswapV2Pair(factory.getPair(address(weth), address(usdc)));

        pool = new MockAaveV1LendingPool(weth, usdc, borrower, feeCollector);
        pool.setWethPrice(4_000e6); // WETH price is $ 4,000
        // Supply the mock with USDC liquidity to lend to the borrower.
        usdc.transfer(address(pool), DEBT);
        weth.transfer(borrower, 1 ether);

        // 1. Borrower deposits 1 WETH at $4,000 and receives a 2,500 USDC loan.
        vm.startPrank(borrower);
        weth.approve(address(pool), 1 ether);
        pool.deposit(1 ether);
        pool.borrow(DEBT);
        vm.stopPrank();

        liquidator = new FlashSwapLiquidator(pair, pool);
    }

    function test_flashSwapLiquidatesCappedDebtAndRepaysInCollateral() public {
        // 2. WETH falls to $3,000, the position becomes liquidatable.
        pool.setWethPrice(3_000e6);
        assertLt(pool.healthFactor(), 1 ether); // HF < 1 -> the position is now liquidatable

        // 3. Keeper liquidates the unhealthy position
        // Requesting the full debt demonstrates Aave's 50% repayment cap.
        vm.prank(keeper);
        liquidator.liquidate(FLASH_AMOUNT, DEBT);

        // What happens when we call liquidator.liquidate?
        // The liquidator contract starts with zero USDC and zero WETH

        // Step	                Token movement	
        // Flash borrow	        Uniswap pair → liquidator: 1,250 USDC
        // Liquidate	        Liquidator → Aave V1: 1,250 USDC
        // Receive collateral	Aave V1 → liquidator: ≈0.4375 WETH
        // Repay flash swap	    Liquidator → Uniswap pair: ≈0.419669 WETH
        // Distribute profit	Liquidator → keeper: ≈0.017831 WETH

        // The liquidator finishes with zero USDC and zero WETH

        // Aave receives 1,250 USDC and the borrower's remaining debt is 1,250 USDC.
        assertEq(usdc.balanceOf(address(pool)), FLASH_AMOUNT);
        // The borrower initially owes 2,500 USDC, and the liquidator repays 1,250 USDC—50% of that debt
        assertEq(pool.debt(), DEBT - FLASH_AMOUNT);

        // The liquidator receives ~0.4375 WETH and repays ~0.419669 WETH.
        uint256 repayment = WETH_RESERVE * FLASH_AMOUNT * 1000 / ((USDC_RESERVE - FLASH_AMOUNT) * 997) + 1;
        assertEq(weth.balanceOf(address(pair)), WETH_RESERVE + repayment); // 100 ether + 0.419669 WETH = 100.419669 WETH
        assertEq(usdc.balanceOf(address(pair)), USDC_RESERVE - FLASH_AMOUNT); // 300,000 USDC - 1250 USDC = 298,750 USDC

        // 1,250 USDC / 3,000 USDC per WETH, plus a 5% liquidation bonus.
        // Integer division before applying the bonus rounds the result down by one wei.
        uint256 seizedCollateral = FLASH_AMOUNT * 1 ether / pool.wethPrice() * 105 / 100;
        // The remaining ~0.017831 WETH (~$53.49 before gas) goes to the keeper.
        assertEq(weth.balanceOf(keeper), seizedCollateral - repayment);
    }
}
