// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "./IERC20.sol";

// Includes the complete EIP-2612 interface
interface IUniswapV2ERC20 is IERC20 {
    function name() external pure override returns (string memory);
    function symbol() external pure override returns (string memory);
    function decimals() external pure override returns (uint8);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint256);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
}
