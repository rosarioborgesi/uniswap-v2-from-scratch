// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {UniswapV2ERC20} from "../src/v2-core/UniswapV2ERC20.sol";

// Only minting is added for setup; approve, permit and transferFrom are inherited.
contract PermitDemoToken is UniswapV2ERC20 {
    function mint(address to, uint256 value) external {
        _mint(to, value);
    }
}

contract PermitDemoRouter {
    UniswapV2ERC20 public immutable token;

    constructor(UniswapV2ERC20 token_) {
        token = token_;
    }

    function transfer(address owner, address recipient, uint256 value) public {
        token.transferFrom(owner, recipient, value);
    }

    function approveAndTransfer(address owner, address recipient, uint256 value) external {
        // Inside token.approve, msg.sender is THIS ROUTER, not owner!
        // This sets allowance[router][router], leaving allowance[owner][router] at 0.
        token.approve(address(this), value);
        transfer(owner, recipient, value);
    }

    function permitAndTransfer(
        address owner,
        address recipient,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Both token calls execute within the single transaction to this function.
        token.permit(owner, address(this), value, deadline, v, r, s);
        transfer(owner, recipient, value);
    }
}

contract PermitTest is Test {
    PermitDemoToken internal token;
    PermitDemoRouter internal router;
    uint256 internal constant OWNER_KEY = 0xA11CE;
    uint256 internal constant VALUE = 10 ether;
    address internal owner;
    address internal recipient;

    function setUp() public {
        owner = vm.addr(OWNER_KEY);
        recipient = makeAddr("recipient");
        token = new PermitDemoToken();
        router = new PermitDemoRouter(token);
        token.mint(owner, VALUE);
    }

    function test_Approve_TwoSeparateTransactions() public {
        // TX 1: the owner approves the router directly.
        vm.prank(owner);
        token.approve(address(router), VALUE);

        // TX 2: the router transfers the owner's tokens.
        vm.prank(owner);
        router.transfer(owner, recipient, VALUE);

        assertEq(token.balanceOf(recipient), VALUE);
    }

    function test_ApproveAndTransfer_OneTransaction_Reverts() public {
        // ONE transaction fails: approve inside the router approves the router's
        // own tokens. The router still has no allowance to spend the owner's tokens.
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(owner);
        router.approveAndTransfer(owner, recipient, VALUE);

        assertEq(token.balanceOf(recipient), 0);
    }

    function test_PermitAndTransfer_OneTransaction() public {
        uint256 deadline = block.timestamp + 1 hours;
        // Sign off-chain: no transaction needed.
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(deadline);

        address relayer = makeAddr("relayer");
        // ONE transaction: the router submits the signature and transfers tokens.
        // The relayer can submit the signed permit on the user's behalf.
        vm.prank(relayer);
        router.permitAndTransfer(owner, recipient, VALUE, deadline, v, r, s);

        assertEq(token.balanceOf(recipient), VALUE);
    }

    function _signPermit(uint256 deadline) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(token.PERMIT_TYPEHASH(), owner, address(router), VALUE, token.nonces(owner), deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(OWNER_KEY, digest);
    }
}
