// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IUniswapV2ERC20} from "./interfaces/IUniswapV2ERC20.sol";

// Implements an ERC-20 LP token extended with EIP-2612 permit
/// @title UniswapV2ERC20
/// @notice ERC-20 liquidity provider (LP) token for Uniswap V2 pairs with EIP-2612 approvals by signature.
/// @dev UniswapV2Pair inherits this contract to mint and burn LP tokens.
contract UniswapV2ERC20 is IUniswapV2ERC20 {
    /////////////////////////////////////////
    //            State Variables          //
    /////////////////////////////////////////
    // ============ ERC-20 Metadata ============
    /// @notice The LP token name.
    string public constant name = "Uniswap V2";

    /// @notice The LP token symbol.
    string public constant symbol = "UNI-V2";

    /// @notice The number of decimal places used to display LP token amounts.
    uint8 public constant decimals = 18;

    // ============ ERC-20 State ============
    /// @notice The total supply of LP tokens in base units.
    uint256 public totalSupply;

    /// @notice The LP token balance of each account in base units.
    mapping(address => uint256) public balanceOf;

    /// @notice The amount of LP tokens each spender can transfer on behalf of an owner, in base units.
    /// @dev The outer key is the owner and the inner key is the spender.
    mapping(address => mapping(address => uint256)) public allowance;

    // ============ EIP-2612 Permit State ============
    /// @notice The EIP-712 domain separator used to verify permit signatures.
    /// @dev Computed at deployment from the token name, version, chain ID, and contract address.
    bytes32 public DOMAIN_SEPARATOR;

    /// @notice The EIP-712 type hash for permit messages.
    /// @dev The Keccak-256 hash of `Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)`.
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice The nonce each owner must use in their next permit signature.
    /// @dev Each successful permit increments the owner's nonce to prevent replay.
    mapping(address => uint256) public nonces;

    ///////////////////////////////////
    //            Functions          //
    ///////////////////////////////////
    /// @dev Initializes the EIP-712 domain separator with version `1`.
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

    ////////////////////////////////////////////
    //            Internal Functions          //
    ////////////////////////////////////////////
    /// @dev Increases `totalSupply` and the recipient's balance. Emits `Transfer` from the zero address.
    /// @param to The account to credit.
    /// @param value The amount of LP tokens to mint in base units.
    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    /// @dev Decreases `totalSupply` and the source account's balance. Emits `Transfer` to the zero address.
    /// @param from The account to debit.
    /// @param value The amount of LP tokens to burn in base units.
    function _burn(address from, uint256 value) internal {
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    /// @dev Replaces the spender's allowance and emits `Approval`.
    /// @param owner The account granting the allowance.
    /// @param spender The account authorized to spend the owner's LP tokens.
    /// @param value The new allowance in base units.
    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// @dev Moves LP tokens between account balances and emits `Transfer`.
    /// @param from The account to debit.
    /// @param to The account to credit.
    /// @param value The amount of LP tokens to transfer in base units.
    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    ////////////////////////////////////////////
    //            External Functions          //
    //////////////////////////////////////////// 
    /// @notice Sets the amount of LP tokens `spender` may transfer from the caller's balance.
    /// @param spender The account authorized to spend the caller's LP tokens.
    /// @param value The new allowance in base units. Use `type(uint256).max` for unlimited allowance.
    /// @return True on success.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @notice Transfers LP tokens from the caller's balance to `to`.
    /// @param to The recipient of the LP tokens.
    /// @param value The amount to transfer in base units.
    /// @return True on success.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Transfers LP tokens from `from` to `to` using the caller's allowance.
    /// @dev Deducts the transfer amount from finite allowances. Reverts if the balance or allowance is insufficient.
    /// @param from The account whose LP tokens are transferred.
    /// @param to The recipient of the LP tokens.
    /// @param value The amount to transfer in base units.
    /// @return True on success.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    /// @notice Sets `spender`'s allowance using an EIP-2612 signature from `owner`. Anyone may submit the signature.
    /// @dev Verifies the signature against the owner's current nonce and this contract's EIP-712 domain separator.
    ///      A successful call increments the nonce and emits `Approval`.
    /// @param owner The LP token holder who signed the approval.
    /// @param spender The account authorized to spend the owner's LP tokens.
    /// @param value The new allowance in base units.
    /// @param deadline The last valid block timestamp for the signature, in Unix seconds.
    /// @param v The recovery identifier of the signature.
    /// @param r The R component of the signature.
    /// @param s The S component of the signature.
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
