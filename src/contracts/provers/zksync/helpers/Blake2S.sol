// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Blake2s {
    uint32 constant BLOCKBYTES = 64;
    uint32 constant OUTBYTES = 32;

    uint32 constant IV0 = 0x6A09E667;
    uint32 constant IV1 = 0xBB67AE85;
    uint32 constant IV2 = 0x3C6EF372;
    uint32 constant IV3 = 0xA54FF53A;
    uint32 constant IV4 = 0x510E527F;
    uint32 constant IV5 = 0x9B05688C;
    uint32 constant IV6 = 0x1F83D9AB;
    uint32 constant IV7 = 0x5BE0CD19;

    struct Hasher {
        bytes sigma;
        uint256[2] m;
    }

    function newHasher() internal pure returns (Hasher memory) {
        // Sigma table with values pre-multiplied by 4 (byte offsets into m)
        return Hasher(hex"0004080c1014181c2024282c3034383c38281020243c3418043000082c1c140c2c20300014083c3428380c181c0424101c240c0434302c380818142810003c202400141c0810283c38042c3018200c3408301828002c200c10341c143c3804243014043c38341028001c180c2408202c342c1c3830040c2414003c1020180828183c38242c0c00203008341c04102814280820101c1804143c2c24380c303400", [uint256(0), 0]);
    }

    function hash(Hasher memory hasher, bytes memory input) internal pure returns (bytes32) {
        // Initialize state: h[0] = IV0 ^ 0x01010000 ^ OUTBYTES, h[1..7] = IV[1..7]
        uint256 h1 = uint256(IV0 ^ 0x01010000 ^ OUTBYTES) 
                  | (uint256(IV1) << 32) 
                  | (uint256(IV2) << 64) 
                  | (uint256(IV3) << 96);
        uint256 h2 = uint256(IV4) 
                   | (uint256(IV5) << 32) 
                   | (uint256(IV6) << 64) 
                   | (uint256(IV7) << 96);
        uint256 len = input.length;
        uint256 t = 0;

        bytes memory sigma = hasher.sigma;
        uint256[2] memory m = hasher.m;
        uint256 m0;
        uint256 m1;

        unchecked {
            while (len > BLOCKBYTES) {
                t += BLOCKBYTES;
                assembly ("memory-safe") {
                    let ptr := add(add(input, 32), sub(t, 64))
                    m0 := mload(ptr)
                    m1 := mload(add(ptr, 32))
                }
                (h1, h2) = compress(sigma, m, m0, m1, h1, h2, uint64(t), false);
                len -= BLOCKBYTES;
            }

            assembly ("memory-safe") {
                let src := add(add(input, 32), t)
                switch gt(len, 32)
                case 0 {
                    m0 := and(mload(src), shl(shl(3, sub(32, len)), not(0)))
                    m1 := 0
                }
                default {
                    m0 := mload(src)
                    m1 := and(mload(add(src, 32)), shl(shl(3, sub(64, len)), not(0)))
                }
            }
            t += len;
            (h1, h2) = compress(sigma, m, m0, m1, h1, h2, uint64(t), true);
        }

        return hashFromState(h1, h2);
    }

    function hashFromState(uint256 h1, uint256 h2) private pure returns (bytes32) {
        uint256 x = (h1 << 128) | (h2 & MASK128);
        unchecked {
            x = ((x >> 64) & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) |
                ((x << 64) & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000);
            x = ((x >> 32) & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) |
                ((x << 32) & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000);
            x = ((x >> 16) & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) |
                ((x << 16) & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000);
            x = ((x >> 8) & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) |
                ((x << 8) & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00);
        }
        return bytes32(x);
    }

    // Mask for 4 lanes of 32-bit words (bits 0-127)
    uint256 constant MASK128 = (1 << 128) - 1;
    uint256 constant MASK32 = 0xFFFFFFFF;

    uint256 constant HIGHBIT = 0x80000000800000008000000080000000;

    // Packed add: add 4x32-bit lanes without cross-lane carry
    function add32x4(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            uint256 abLoSum = (a & ~HIGHBIT) + (b & ~HIGHBIT);
            uint256 abHiXor = (a ^ b) & HIGHBIT;
            return abLoSum ^ abHiXor;
        }
    }

    // Packed add of 3 values: a + b + c
    function add32x4_3(uint256 a, uint256 b, uint256 c) private pure returns (uint256) {
        unchecked {
            uint256 abcHiXor = (a ^ b ^ c) & HIGHBIT;

            uint256 aLo = a & ~HIGHBIT;
            uint256 bLo = b & ~HIGHBIT;
            uint256 cLo = c & ~HIGHBIT;

            uint256 abLoSum = aLo + bLo;
            uint256 abLo    = abLoSum & ~HIGHBIT;
            uint256 abHi    = abLoSum ^ abLo;

            return (abLo + cLo) ^ abHi ^ abcHiXor;
        }
    }

    function rotr32x4_16(uint256 x) private pure returns (uint256) {
        unchecked {
            uint256 right = (x >> 16) & 0x0000FFFF0000FFFF0000FFFF0000FFFF;
            uint256 left = (x << 16) & 0xFFFF0000FFFF0000FFFF0000FFFF0000;
            return right | left;
        }
    }

    function rotr32x4_12(uint256 x) private pure returns (uint256) {
        unchecked {
            uint256 right = (x >> 12) & 0x000FFFFF000FFFFF000FFFFF000FFFFF;
            uint256 left = (x << 20) & 0xFFF00000FFF00000FFF00000FFF00000;
            return right | left;
        }
    }

    function rotr32x4_8(uint256 x) private pure returns (uint256) {
        unchecked {
            uint256 right = (x >> 8) & 0x00FFFFFF00FFFFFF00FFFFFF00FFFFFF;
            uint256 left = (x << 24) & 0xFF000000FF000000FF000000FF000000;
            return right | left;
        }
    }

    function rotr32x4_7(uint256 x) private pure returns (uint256) {
        unchecked {
            uint256 right = (x >> 7) & 0x01FFFFFF01FFFFFF01FFFFFF01FFFFFF;
            uint256 left = (x << 25) & 0xFE000000FE000000FE000000FE000000;
            return right | left;
        }
    }

    // Rotate lanes left by 1: [0,1,2,3] -> [1,2,3,0]
    function rotl_lanes_1(uint256 x) private pure returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(16, x)
            mstore(0, x)
            result := mload(12)
        }
    }

    // Rotate lanes left by 2: [0,1,2,3] -> [2,3,0,1]
    function rotl_lanes_2(uint256 x) private pure returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(16, x)
            mstore(0, x)
            result := mload(8)
        }
    }

    // Rotate lanes left by 3: [0,1,2,3] -> [3,0,1,2]
    function rotl_lanes_3(uint256 x) private pure returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(16, x)
            mstore(0, x)
            result := mload(4)
        }
    }

    // G function on 4 parallel lanes
    function G4(uint256 a, uint256 b, uint256 c, uint256 d, uint256 x, uint256 y) 
        private pure returns (uint256, uint256, uint256, uint256) 
    {
        unchecked {
            a = add32x4_3(a, b, x);
            d = rotr32x4_16(d ^ a);
            c = add32x4(c, d);
            b = rotr32x4_12(b ^ c);
            a = add32x4_3(a, b, y);
            d = rotr32x4_8(d ^ a);
            c = add32x4(c, d);
            b = rotr32x4_7(b ^ c);
            return (a, b, c, d);
        }
    }

    // Pack 4 message words into lanes
    function packM(uint32 m0, uint32 m1, uint32 m2, uint32 m3) private pure returns (uint256) {
        return uint256(m0) | (uint256(m1) << 32) | (uint256(m2) << 64) | (uint256(m3) << 96);
    }

    // Byte-swap within each 32-bit lane (8 lanes)
    function bswap32x8(uint256 x) private pure returns (uint256) {
        unchecked {
            uint256 mask0 = 0x000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF;
            uint256 mask1 = 0x0000FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF00;
            uint256 mask2 = 0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000;
            uint256 mask3 = 0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000;
            return ((x & mask0) << 24) | ((x & mask1) << 8) | ((x & mask2) >> 8) | ((x & mask3) >> 24);
        }
    }

    // Get m[sigma[r * 16 + i]] where sigma values are pre-multiplied by 4
    function getWordBySigma(uint256[2] memory m, bytes memory sigma, uint256 r, uint256 i) private pure returns (uint32 result) {
        assembly ("memory-safe") {
            // offset = sigma[r * 16 + i] (already multiplied by 4)
            let offset := shr(248, mload(add(add(sigma, 32), add(shl(4, r), i))))
            result := shr(224, mload(add(m, offset)))
        }
    }

    function compress(bytes memory sigma, uint256[2] memory m, uint256 m0, uint256 m1, uint256 h1, uint256 h2, uint64 t, bool isFinal) 
        private pure returns (uint256, uint256) 
    {
        m[0] = bswap32x8(m0);
        m[1] = bswap32x8(m1);

        // Initialize working vector v as 4 rows
        // row0 = v[0..3] = h[0..3]
        // row1 = v[4..7] = h[4..7]
        // row2 = v[8..11] = IV[0..3]
        // row3 = v[12..15] = IV[4..7] ^ (t, t>>32, final, 0)
        uint256 row0 = h1;
        uint256 row1 = h2;
        uint256 row2 = uint256(IV0) | (uint256(IV1) << 32) | (uint256(IV2) << 64) | (uint256(IV3) << 96);
        
        uint32 v12 = uint32(t) ^ IV4;
        uint32 v13 = uint32(t >> 32) ^ IV5;
        uint32 v14 = isFinal ? (type(uint32).max ^ IV6) : IV6;
        uint32 v15 = IV7;
        uint256 row3 = uint256(v12) | (uint256(v13) << 32) | (uint256(v14) << 64) | (uint256(v15) << 96);

        unchecked {
            // 10 rounds
            for (uint256 r = 0; r < 10; r++) {
                // Column Gs: G(v[0,4,8,12]), G(v[1,5,9,13]), G(v[2,6,10,14]), G(v[3,7,11,15])
                // x = m[sigma(r,0)], m[sigma(r,2)], m[sigma(r,4)], m[sigma(r,6)] for the 4 column Gs
                // y = m[sigma(r,1)], m[sigma(r,3)], m[sigma(r,5)], m[sigma(r,7)]
                uint256 mx = packM(getWordBySigma(m, sigma, r, 0), getWordBySigma(m, sigma, r, 2), getWordBySigma(m, sigma, r, 4), getWordBySigma(m, sigma, r, 6));
                uint256 my = packM(getWordBySigma(m, sigma, r, 1), getWordBySigma(m, sigma, r, 3), getWordBySigma(m, sigma, r, 5), getWordBySigma(m, sigma, r, 7));
                
                (row0, row1, row2, row3) = G4(row0, row1, row2, row3, mx, my);
                
                // Rotate rows for diagonal layout
                row1 = rotl_lanes_1(row1);
                row2 = rotl_lanes_2(row2);
                row3 = rotl_lanes_3(row3);
                
                // Diagonal Gs
                // After rotation, lane i of each row gives us the diagonal elements
                // x = m[sigma(r,8)], m[sigma(r,10)], m[sigma(r,12)], m[sigma(r,14)]
                // y = m[sigma(r,9)], m[sigma(r,11)], m[sigma(r,13)], m[sigma(r,15)]
                mx = packM(getWordBySigma(m, sigma, r, 8), getWordBySigma(m, sigma, r, 10), getWordBySigma(m, sigma, r, 12), getWordBySigma(m, sigma, r, 14));
                my = packM(getWordBySigma(m, sigma, r, 9), getWordBySigma(m, sigma, r, 11), getWordBySigma(m, sigma, r, 13), getWordBySigma(m, sigma, r, 15));
                
                (row0, row1, row2, row3) = G4(row0, row1, row2, row3, mx, my);
                
                // Rotate back to column layout
                row1 = rotl_lanes_3(row1);
                row2 = rotl_lanes_2(row2);
                row3 = rotl_lanes_1(row3);
            }
        }

        // Finalize: h[i] ^= v[i] ^ v[i+8]
        h1 = h1 ^ row0 ^ row2;
        h2 = h2 ^ row1 ^ row3;

        return (h1, h2);
    }
}

function blake2s(bytes memory input) pure returns (bytes32) {
    return Blake2s.hash(Blake2s.newHasher(), input);
}
