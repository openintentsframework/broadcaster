// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {RLP} from "../../contracts/libraries/RLP.sol";

contract RLPTest is Test {


    function setUp() public {
        
    }

    function test_rlp_encode() public {

        bytes memory buffer = "dog";

        bytes memory encoded = RLP.encode(buffer);

        assertEq(encoded.length, 4);
        assertEq(encoded[0], bytes1(0x83));
        assertEq(encoded[1], bytes1("d"));
        assertEq(encoded[2], bytes1("o"));
        assertEq(encoded[3], bytes1("g"));
    }

    function 
}
