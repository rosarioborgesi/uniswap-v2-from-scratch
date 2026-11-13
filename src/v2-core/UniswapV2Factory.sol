// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Uniswap v2-core/contracts/UniswapV2Factory.sol for Solidity 0.8.35.
pragma solidity 0.8.35;

import "./interfaces/IUniswapV2Factory.sol";
import "./UniswapV2Pair.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    /// @notice Creates a new trading pair for two tokens.
    /// @dev Uses CREATE2 for deterministic pair addresses. Tokens are sorted internally.
    /// @param tokenA One of the two tokens in the pair
    /// @param tokenB The other token in the pair
    /// @return pair The address of the newly created pair
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");

        // Sort tokens so token0 has the smaller address
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        // token0 must be != 0,
        // No need to check token1 because it is guaranteed > token0
        require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");

        // Require pair does not already exist
        require(getPair[token0][token1] == address(0), "UniswapV2: PAIR_EXISTS");

        // Deploy a new UniswapV2Pair using CREATE2
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // The pair address is determinist and is not random.
        // This saves gas fees instead of calling a mapping
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        // Initialize the pair with the two token addresses
        IUniswapV2Pair(pair).initialize(token0, token1);

        // Register the pair in both directions
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        // Add to the allPairs array
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /// @notice Sets the address that receives protocol fees.
    /// @param _feeTo The new fee recipient address
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    /// @notice Transfers governance to a new address.
    /// @param _feeToSetter The new governance address
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}
