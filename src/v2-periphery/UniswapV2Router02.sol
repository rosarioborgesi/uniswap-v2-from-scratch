// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IUniswapV2Factory} from "../v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

/// @notice Partial Router02 port: token liquidity, exact-input swaps, and price/output quotes only.
contract UniswapV2Router02 is IUniswapV2Router02 {
    /////////////////////////////////////////
    //            State Variables          //
    /////////////////////////////////////////
    address public immutable override factory;
    address public immutable override WETH;

    ///////////////////////////////////
    //            Modifiers          //
    ///////////////////////////////////
    // Check the deadline
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    ///////////////////////////////////
    //            Functions          //
    ///////////////////////////////////
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    /// @dev Only accept ETH via fallback from the WETH contract.
    receive() external payable {
        require(msg.sender == WETH, "UniswapV2Router: ONLY_WETH");
    }

    ////////////////////////////////////////////
    //            External Functions          //
    //////////////////////////////////////////// 
    /// @notice Adds liquidity to a token pair and mints LP tokens to the recipient.
    /// @dev Creates the pair if needed and uses both desired amounts when both reserves are zero.
    /// Otherwise, uses the reserve ratio to quote one token amount and checks it against its minimum.
    /// The caller must approve the router to spend the amounts transferred from their balance.
    /// @param tokenA Address of the first token.
    /// @param tokenB Address of the second token.
    /// @param amountADesired Maximum amount of tokenA to deposit.
    /// @param amountBDesired Maximum amount of tokenB to deposit.
    /// @param amountAMin Minimum amount of tokenA if its amount is quoted from the reserves.
    /// @param amountBMin Minimum amount of tokenB if its amount is quoted from the reserves.
    /// @param to Recipient of the LP tokens.
    /// @param deadline Latest block timestamp at which the transaction can succeed.
    /// @return amountA Amount of tokenA transferred from the caller.
    /// @return amountB Amount of tokenB transferred from the caller.
    /// @return liquidity Amount of LP tokens minted to the recipient.
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Calculate the deposit amounts and create the pair if it doesn't exist
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // Compute the pair address
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // Transfer amountA of tokenA from msg.sender to pair
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        // Transfer amountB of tokenB from msg.sender to pair (The router doesn't hold any tokens)
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // Mint LP tokens to to
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    /// @notice Adds liquidity to a token/WETH pair using ETH and mints LP tokens to the recipient.
    /// @dev Creates the pair if needed. When both reserves are zero, uses `amountTokenDesired` and `msg.value`.
    /// Otherwise, quotes one amount from the reserves and checks it against its minimum.
    /// The caller must approve the router to spend the token amount used. The router wraps the ETH used
    /// into WETH and refunds any excess ETH to `msg.sender`.
    /// @param token Address of the ERC-20 token paired with WETH.
    /// @param amountTokenDesired Maximum amount of the token to deposit.
    /// @param amountTokenMin Minimum token amount if it is quoted from the reserves.
    /// @param amountETHMin Minimum ETH amount in wei if it is quoted from the reserves.
    /// @param to Recipient of the LP tokens.
    /// @param deadline Latest block timestamp at which the transaction can succeed.
    /// @return amountToken Amount of the token transferred from the caller.
    /// @return amountETH Amount of ETH in wei wrapped and deposited as WETH.
    /// @return liquidity Amount of LP tokens minted to the recipient.
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        // Calculate the deposit amounts and create the pair if it doesn't exist
        (amountToken, amountETH) = _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        // Compute the pair address
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // transfers amountToken of the ERC-20 token from caller to the pair
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        // Wrap amountETH into WETH
        IWETH(WETH).deposit{value: amountETH}();
        // Transfer amountETH of WETH to the pair
        // The router doesn't hold any ETH
        TransferHelper.safeTransfer(WETH, pair, amountETH);
        // The pair then mints LP tokens to to
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund excess ETH
        if(msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    /// @notice Redeems LP tokens for a proportional share of both underlying tokens.
    /// @dev The caller must approve the router to transfer `liquidity` LP tokens to the pair.
    /// The pair burns its LP token balance and sends both underlying tokens to `to`.
    /// Reverts if either withdrawal amount is below its minimum or the deadline has passed.
    /// @param tokenA Address of the first underlying token.
    /// @param tokenB Address of the second underlying token.
    /// @param liquidity Amount of LP tokens to transfer from the caller, in base units.
    /// @param amountAMin Minimum withdrawal amount of tokenA, in its base units.
    /// @param amountBMin Minimum withdrawal amount of tokenB, in its base units.
    /// @param to Recipient of both underlying tokens.
    /// @param deadline Latest block timestamp at which the transaction can succeed.
    /// @return amountA Amount of tokenA withdrawn from the pair.
    /// @return amountB Amount of tokenB withdrawn from the pair.
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        // Compute the pair address
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // Transfer LP tokens (liquidity) from msg.sender to the pair
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        // Burn the LP tokens and withdraw the underlying assets
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        // Put the amounts in the caller’s order
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        // Enforce the minimums
        require(amountA >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
    }

    /// @notice Redeems token/WETH LP tokens for the underlying ERC-20 token and native ETH.
    /// @dev The caller must approve the router to spend `liquidity` LP tokens. The router receives both assets,
    /// unwraps the WETH, and sends the token and ETH to `to`.
    /// Reverts if either withdrawal amount is below its minimum or the deadline has passed.
    /// @param token Address of the ERC-20 token paired with WETH.
    /// @param liquidity Amount of LP tokens to transfer from the caller, in base units.
    /// @param amountTokenMin Minimum token amount withdrawn from the pair, in the token's base units.
    /// @param amountETHMin Minimum ETH amount to withdraw, in wei.
    /// @param to Recipient of the token and ETH.
    /// @param deadline Latest block timestamp at which the withdrawal can succeed.
    /// @return amountToken Amount of the ERC-20 token withdrawn from the pair.
    /// @return amountETH Amount of native ETH sent to the recipient, in wei.
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        // Redeem the LP tokens
        //  address(this) receives amountToken (ERC-20) and amountETH (WETH)
        (amountToken, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        // Transfer ERC-20 amountToken to the recipient (to)
        TransferHelper.safeTransfer(token, to, amountToken);
        // Unwrap WETH
        IWETH(WETH).withdraw(amountETH);
        // Send ETH to recipient
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /// @notice Redeems LP tokens for both underlying tokens using a signed permit.
    /// @dev The permit must name the caller as owner and the router as spender. It uses the pair's EIP-712 domain
    /// and the caller's current nonce. If the withdrawal reverts, the permit approval and nonce update revert too.
    /// @param tokenA Address of the first underlying token.
    /// @param tokenB Address of the second underlying token.
    /// @param liquidity Amount of LP tokens to transfer from the caller, in base units.
    /// @param amountAMin Minimum withdrawal amount of tokenA, in its base units.
    /// @param amountBMin Minimum withdrawal amount of tokenB, in its base units.
    /// @param to Recipient of both underlying tokens.
    /// @param deadline Latest block timestamp at which both the permit and withdrawal can succeed.
    /// @param approveMax Set to `true` to sign for an unlimited allowance or `false` to sign for exactly `liquidity`.
    /// @param v Recovery identifier of the permit signature.
    /// @param r R component of the permit signature.
    /// @param s S component of the permit signature.
    /// @return amountA Amount of tokenA withdrawn from the pair.
    /// @return amountB Amount of tokenB withdrawn from the pair.
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        // Find the pair
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // Determine approval value: if approveMax, use type(uint256).max, else use liquidity
        uint256 value = approveMax ? type(uint256).max : liquidity;
        // Apply the signed approval
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // Remove liquidity
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /// @notice Redeems token/WETH LP tokens for the underlying ERC-20 token and native ETH using a signed permit.
    /// @dev The permit uses the pair's EIP-712 domain and the caller's current nonce, with the caller as owner and
    /// the router as spender. If the withdrawal reverts, the permit approval and nonce update revert too.
    /// @param token Address of the ERC-20 token paired with WETH.
    /// @param liquidity Amount of LP tokens to transfer from the caller, in base units.
    /// @param amountTokenMin Minimum token amount withdrawn from the pair, in the token's base units.
    /// @param amountETHMin Minimum ETH amount to withdraw, in wei.
    /// @param to Recipient of the token and ETH.
    /// @param deadline Latest block timestamp at which both the permit and withdrawal can succeed.
    /// @param approveMax Set to `true` to sign for an unlimited allowance or `false` to sign for exactly `liquidity`.
    /// @param v Recovery identifier of the permit signature.
    /// @param r R component of the permit signature.
    /// @param s S component of the permit signature.
    /// @return amountToken Amount of the ERC-20 token withdrawn from the pair, in the token's base units.
    /// @return amountETH Amount of native ETH sent to the recipient, in wei.
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
        // Compute pair address using UniswapV2Library.pairFor(factory, token, WETH)
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // Determine approval value: if approveMax, use type(uint256).max, else use liquidity
        uint256 value = approveMax ? type(uint256).max : liquidity;
        // Apply the signed approval
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // Remove liquidity
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // "I want to spend exactly 1 ETH, give me as much USDC as possible" 
    /// @notice Swaps an exact amount of the input token along the given path and sends the final output to `to`.
    /// @dev The caller must approve the router to spend `amountIn` of `path[0]`.
    /// Reverts if the quoted final output is below `amountOutMin`.
    /// @param amountIn Exact amount of the input token to transfer from the caller.
    /// @param amountOutMin Minimum acceptable amount of the final output token.
    /// @param path Ordered token addresses from input to output. Each consecutive pair must have liquidity.
    /// The path must contain at least two tokens.
    /// @param to Recipient of the final output token.
    /// @param deadline Latest block timestamp at which the transaction can succeed.
    /// @return amounts Token amounts in path order, from the initial input through each swap's output.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        // 1. Calculate the output at each hop.
        // The router uses each pair’s reserves to calculate how much the swap will produce.
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // If the final amount is below amountOutMin, the transaction reverts
        require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        // 2. Transfers the input tokens in the first pair.
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 3. Executes each hop
        // The first pair already has the input tokens, 
        // so _swap tells it how much of the next token to send out. 
        // Each intermediate pair sends its output directly to the next pair, 
        // and the last pair sends its output to to.
        _swap(amounts, path, to);
    }

    ////////////////////////////////////////////
    //            Internal Functions          //
    ////////////////////////////////////////////
    /// @notice Determines the token amounts to deposit and creates the pair if it does not exist.
    /// @dev Returns both desired amounts when both reserves are zero. Otherwise, uses one desired amount
    /// and quotes the other from the reserves, reverting if the quoted amount is below its minimum.
    /// @param tokenA Address of the first token.
    /// @param tokenB Address of the second token.
    /// @param amountADesired Maximum amount of tokenA to deposit.
    /// @param amountBDesired Maximum amount of tokenB to deposit.
    /// @param amountAMin Minimum amount of tokenA if its amount is quoted from the reserves.
    /// @param amountBMin Minimum amount of tokenB if its amount is quoted from the reserves.
    /// @return amountA Amount of tokenA to deposit.
    /// @return amountB Amount of tokenB to deposit.
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            // If both reserves are zero, use both desired amounts.
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // Existing pair, the pool has liquidity
            // Try using all of token A.
            uint256 amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // If that would require too much B, use all of token B
                uint256 amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // Executes a swap across one or more Uniswap pairs.
    /// @notice Executes swaps along a token path and sends the final output to `_to`.
    /// @dev The caller must transfer `amounts[0]` to the first pair before calling.
    /// Each intermediate pair sends its output directly to the next pair.
    /// @param amounts Token amounts in path order, starting with the initial input amount.
    /// @param path Ordered token addresses, with at least two tokens and one amount per token.
    /// @param _to Recipient of the final output token.
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            // 1. Identify the tokens for this hop
            // At index i, the input token is path[i], and the output token is path[i + 1]
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            // The amount to send out is amounts[i + 1]
            uint256 amountOut = amounts[i + 1];
            // 2. Set the correct output field
            // The pair’s swap function takes separate amount0Out and amount1Out arguments.
            // If the input is token0, _swap sets amount1Out.
            // Otherwise, it sets amount0Out. The other field is zero.
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            // 3. Choose where the output goes 
            // On an intermediate hop, 
            // the current pair sends its output directly to the next pair, 
            // where it becomes the input for that hop.
            // On the last hop, the pair sends the output to _to.
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            // 4. Call the pair and repeat
            // The router calls pair.swap with empty callback data.
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /////////////////////////////////////////////////////////////////
    //            External & Public View & Pure Functions          //
    /////////////////////////////////////////////////////////////////
    /// @notice Returns the reserve-ratio equivalent of amountA, excluding swap fees and price impact.
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        virtual
        override
        returns (uint256 amountB)
    {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }
}
