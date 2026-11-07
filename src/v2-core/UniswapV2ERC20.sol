// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IUniswapV2ERC20} from "./interfaces/IUniswapV2ERC20.sol";

/// @title UniswapV2ERC20
/// @notice LP token for Uniswap V2 pairs. ERC-20 with EIP-2612 permit.
/// @dev This is the base contract that UniswapV2Pair inherits from.
contract UniswapV2ERC20 is IUniswapV2ERC20 {
    // ============ ERC-20 Metadata ============
    string public constant name = "Uniswap V2";
    string public constant symbol = "UNI-V2";
    uint8 public constant decimals = 18;

    // ============ ERC-20 State ============
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ============ EIP-2612 Permit State ============
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    // ============ Constructor ============
    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    // ============ Internal Functions ============

    /// @dev Creates `value` tokens and assigns them to `to`.
    /// Increases totalSupply. Emits Transfer from address(0).
    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    /// @dev Destroys `value` tokens from `from`.
    /// Decreases totalSupply. Emits Transfer to address(0).
    function _burn(address from, uint256 value) internal {
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    /// @dev Sets `value` as the allowance of `spender` over `owner`'s tokens.
    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// @dev Moves `value` tokens from `from` to `to`.
    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    // ============ External Functions ============

    /// @notice Sets the allowance for `spender` to `value`.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @notice Transfers `value` tokens to `to`.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Transfers `value` tokens from `from` to `to`, using the caller's allowance.
    /// @dev If allowance is type(uint256).max, it is not decreased (gas optimization).
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    /// @notice EIP-2612: Approve by signature.
    /// @dev Allows a third party to submit an approval on behalf of the owner,
    ///      using an off-chain signature. Enables approve + action in one tx.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        require(deadline >= block.timestamp, "UniswapV2: EXPIRED");
        // Compute the EIP712 digest
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "Uniswap V2: INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }
}
