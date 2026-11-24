// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Uniswap solidity-lib/contracts/libraries/TransferHelper.sol for Solidity 0.8.35.
pragma solidity 0.8.35;

/// @title TransferHelper
/// @notice Provides helpers for ERC-20 approvals, ERC-20 transfers, and ETH transfers.
library TransferHelper {
    bytes4 private constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));

    /// @notice Sets the spender's allowance for tokens owned by the calling contract.
    /// @dev Accepts a successful call with empty return data or return data that decodes to `true`. Reverts otherwise.
    /// @param token The ERC-20 token contract.
    /// @param to The spender whose allowance is set.
    /// @param value The new allowance in base units of the token.
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

    /// @notice Transfers tokens from the calling contract to the recipient.
    /// @dev Accepts a successful call with empty return data or return data that decodes to `true`. Reverts otherwise.
    /// @param token The ERC-20 token contract.
    /// @param to The recipient of the tokens.
    /// @param value The amount to transfer in base units of the token.
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(TRANSFER_SELECTOR, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper::safeTransfer: transfer failed");
    }

    /// @notice Transfers tokens from the specified owner to the recipient using `transferFrom`.
    /// @dev Accepts a successful call with empty return data or return data that decodes to `true`. Reverts otherwise.
    /// @param token The ERC-20 token contract.
    /// @param from The account whose tokens are transferred.
    /// @param to The recipient of the tokens.
    /// @param value The amount to transfer in base units of the token.
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::transferFrom: transferFrom failed"
        );
    }

    /// @notice Sends ETH from the calling contract to the recipient.
    /// @dev Uses empty calldata and reverts if the call fails.
    /// @param to The recipient of the ETH.
    /// @param value The amount of ETH to send in wei.
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }

}
