// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Uniswap solidity-lib/contracts/libraries/TransferHelper.sol for Solidity 0.8.35.
pragma solidity 0.8.35;

library TransferHelper {
    bytes4 private constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));

    // Sets how many tokens the spender can use from the calling contract's balance.
    // Accepts a successful token call that returns true or no data.
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(APPROVE_SELECTOR, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeApprove: approve failed'
        );
    }

    // Transfers tokens from the calling contract to the recipient.
    // Accepts a successful token call that returns true or no data.
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(TRANSFER_SELECTOR, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper::safeTransfer: transfer failed");
    }

    // Supports calling transferFrom on standard ERC-20 tokens that return a bool and on
    // nonstandard tokens like USDT that return nothing.
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::transferFrom: transferFrom failed"
        );
    }

    // Sends ETH to the recipient with empty calldata and reverts if the call fails.
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }

}
