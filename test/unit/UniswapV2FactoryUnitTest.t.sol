// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/v2-core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/v2-core/UniswapV2Pair.sol";

contract UniswapV2FactoryUnitTest is Test {


    ////////////////////////////////////
    //            createPair          //
    ////////////////////////////////////
    function test_CreatePair() public {
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        address token0 = address(1);
        address token1 = address(2);

        // Pass tokens in reverse order to demonstrate sorting.
        address pair = factory.createPair(token1, token0);

        // The deployed pair is initialized with the sorted tokens.
        // The token with the numerically smaller address is token0, and the larger is token1
        assertEq(UniswapV2Pair(pair).token0(), token0);
        assertEq(UniswapV2Pair(pair).token1(), token1);

        // The factory registers the pair in both directions and in its array.
        assertEq(factory.getPair(token0, token1), pair);
        assertEq(factory.getPair(token1, token0), pair);
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
    }

    // This demonstrates that CREATE2 makes pair addresses independent of deployment order, 
    // while standard CREATE addresses depend on it.
    function test_CreatePairAddressDoesNotDependOnDeploymentOrder() public {
        UniswapV2Factory factory = new UniswapV2Factory(address(this));
        address token0 = address(1);
        address token1 = address(2);

        // Predict A/B before any pairs exist. CREATE2 uses no deployment nonce:
        // address = last20bytes(keccak256(0xff ++ factory ++ salt ++ initCodeHash)).
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 initCodeHash = keccak256(type(UniswapV2Pair).creationCode); // never changes
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", address(factory), salt, initCodeHash)))));

        // Standard CREATE would use the factory's current nonce.
        address createAddressBefore = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        // Deploy unrelated C/D first. Contract creation advances the factory's nonce,
        // even though this deployment itself uses CREATE2.
        factory.createPair(address(3), address(4));

        address createAddressAfter = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));
        assertNotEq(createAddressBefore, createAddressAfter);

        // A/B still deploys at the original prediction despite C/D being created first.
        assertEq(factory.createPair(token0, token1), predicted);
    }
}
