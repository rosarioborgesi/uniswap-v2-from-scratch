// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UniswapV2ERC20} from "../../src/v2-core/UniswapV2ERC20.sol";

contract UniswapV2ERC20UnitTest is Test {
    UniswapV2ERC20 internal token;
    uint256 internal constant OWNER_PRIVATE_KEY = 0xA11CE;
    uint256 internal constant VALUE = 10 ether;
    address internal owner;
    address internal spender;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new UniswapV2ERC20();
        owner = vm.addr(OWNER_PRIVATE_KEY);
        spender = makeAddr("spender");
        vm.warp(1 days);
    }

    ////////////////////////////////
    //            permit          //
    ////////////////////////////////
    function test_PermitWithValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(OWNER_PRIVATE_KEY, 0, deadline);

        // A third party (the test contract) can submit the owner's signed approval.
        token.permit(owner, spender, VALUE, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), VALUE);
        assertEq(token.nonces(owner), 1);
    }

    function test_PermitRevertsWhenDeadlineExpired() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(OWNER_PRIVATE_KEY, 0, deadline);
        vm.warp(deadline + 1);

        vm.expectRevert(bytes("UniswapV2: EXPIRED"));
        token.permit(owner, spender, VALUE, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.nonces(owner), 0);
    }

    function test_PermitRevertsWhenSignatureReplayed() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(OWNER_PRIVATE_KEY, 0, deadline);
        token.permit(owner, spender, VALUE, deadline, v, r, s);
        assertEq(token.allowance(owner, spender), VALUE);
        assertEq(token.nonces(owner), 1);

        // The same signature still contains nonce 0, which has been consumed.
        vm.expectRevert(bytes("Uniswap V2: INVALID_SIGNATURE"));
        token.permit(owner, spender, VALUE, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), VALUE);
        assertEq(token.nonces(owner), 1);
    }

    function test_PermitRevertsWhenSignedByWrongSigner() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(0xB0B, 0, deadline);

        vm.expectRevert(bytes("Uniswap V2: INVALID_SIGNATURE"));
        token.permit(owner, spender, VALUE, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.nonces(owner), 0);
    }

    function _signPermit(uint256 privateKey, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        // Recreate the EIP-712 digest
        bytes32 structHash = keccak256(abi.encode(token.PERMIT_TYPEHASH(), owner, spender, VALUE, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        // The owner signes the digest
        return vm.sign(privateKey, digest);
    }
}
