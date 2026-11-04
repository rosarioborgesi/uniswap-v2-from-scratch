// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title UQ112x112 — Fixed-Point Library
/// @notice Encodes uint112 values with 112 bits of fractional precision.
/// @dev A UQ112x112 value is a uint224 where the upper 112 bits are the integer
///      part and the lower 112 bits are the fractional part.
library UQ112x112 {
    uint224 constant Q112 = 2 ** 112;

    /// @notice Encode a uint112 as a UQ112x112 fixed-point value.
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    /// @notice Divide a UQ112x112 by a uint112, returning a UQ112x112.
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
