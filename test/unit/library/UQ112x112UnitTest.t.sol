// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UQ112x112} from "../../../src/v2-core/libraries/UQ112x112.sol";

contract UQ112x112UnitTest is Test {
    // Solidity uses integers here. To represent fractions, the library stores:
    // stored value = real value * Q112, where Q112 = 2^112.
    // Thus Q112 means 1, 2 * Q112 means 2, and Q112 / 2 means 0.5.
    uint224 constant Q112 = 2 ** 112;

    function test_EncodeZero() public pure {
        assertEq(UQ112x112.encode(0), 0);
    }

    function test_EncodeTwo() public pure {
        uint224 encoded = UQ112x112.encode(2);

        assertEq(encoded, 2 * Q112);
        // Dividing by Q112 recovers the original whole number.
        assertEq(encoded / Q112, 2);
    }

    function test_SixDividedByTwoIsThree() public pure {
        // Encode the numerator; the denominator stays an ordinary integer.
        uint224 result = UQ112x112.uqdiv(UQ112x112.encode(6), 2);

        assertEq(result, 3 * Q112);
    }

    function test_OneDividedByTwoIsOneHalf() public pure {
        // Ordinary integer division loses the fraction: 1 / 2 = 0.
        uint112 one = 1;
        assertEq(one / 2, 0);

        // Encoding first preserves it: (1 * Q112) / 2 represents 0.5.
        uint224 result = UQ112x112.uqdiv(UQ112x112.encode(one), 2);

        assertEq(result, Q112 / 2);
    }

    function test_FiveDividedByTwoIsTwoAndOneHalf() public pure {
        uint224 result = UQ112x112.uqdiv(UQ112x112.encode(5), 2);

        // 2.5 consists of a whole part (2) and a fractional part (0.5).
        assertEq(result, 2 * Q112 + Q112 / 2);
    }

    function test_OneDividedByThreeRoundsDown() public pure {
        uint224 result = UQ112x112.uqdiv(UQ112x112.encode(1), 3);

        // Unlike 0.5, 1/3 cannot be represented exactly in binary.
        // Q112 / 3 rounds down; its integer remainder is 1.
        assertEq(result, Q112 / 3);
        assertEq(result * 3, Q112 - 1);
    }

    function test_DivideTwoDecimalNumbersWithManyResultDecimals() public pure {
        // Calculate 1.23 / 0.70 = 1.757142857142857142...
        uint112 numerator = 123;
        uint112 denominator = 70;
        uint224 result = UQ112x112.uqdiv(UQ112x112.encode(numerator), denominator);

        assertEq(result, uint256(123) * Q112 / 70);
    }
}
