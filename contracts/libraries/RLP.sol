// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Memory} from "openzeppelin/utils/Memory.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

library RLP {


    struct Item {
        uint256 length;
        Memory.Pointer ptr;
    }



    function encode(bytes memory buffer) internal pure returns (bytes memory item){
        if (buffer.length == 1){
            if(uint8(buffer[0]) < 0x7f){
                return buffer;
            }

            // concat `0x81` and the buffer
            return bytes.concat(bytes1(uint8(0x81)), buffer);

        }

        if(buffer.length <= 55){
            return bytes.concat(bytes1(uint8(0x80 + buffer.length)), buffer);
        }

        uint256 hexSize = Math.log256(buffer.length) +1;

        bytes memory prefix = abi.encodePacked(0xb7 + hexSize, buffer.length);

        bytes.concat(prefix, buffer);
    }

    function encode(bytes[] memory list) internal pure returns (bytes memory item){
    }

    function encodeLength(uint256 length, uint64 offset) internal pure returns (bytes memory){
        if(length <= 55){
            return abi.encodePacked(bytes32(length + offset));
        }


        
    }

    function _toBinary(uint256 x) internal pure returns (uint256 y){

    }



}