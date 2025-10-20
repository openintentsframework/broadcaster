const RLP = require('rlp');
const { ethers } = require("ethers");

async function verifyCancunToCurrentHash() {

    // 1. Get the full block

    const block = {
        parentHash: "0x1e9c639e9b29486266f7e41b0def33287c5c26ae35bb0f7f6737d7fdeb4a1ed3",
        sha3Uncles: "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
        miner: "0x25941dC771bB64514Fc8abBce970307Fb9d477e9",
        stateRoot: "0xcbdb57934e557e2e6a38a5c6aa70bb8a7d0f9700160d928b28a5f04f1de971d1",
        transactionsRoot: "0x82a99363ce8da6eb8ad62254faa538f3735ab98bb8ec7623001dc7dfc26f0bf5",
        receiptsRoot: "0x7605f9bacc57fed2bc64f7f9811bb7ce858c17621895435fadb82aed4195bf3d",
        logsBloom: "0x002200040282e40000901112ac4080050b0030000400111000008104408205500a19000000810325008a400000b5008043031018c2928ca2801010a25829199092c0a802012e01414008610a002840221d1010c0014008000002048ac00498000203010c232148c10920a005a09128028a0889c020581134009090101000204002c2802200501404200010000204c4820104848f0080d40f8171004004200c8622480402100802800884100120204808204000811100080920f428a22030010342108002050080000445004008024050109440102000f8110044350a4400203050509c168840242084021008a0018000223a02000a0900409080024202004841",
        difficulty: 0n,
        number: 9043403n,
        gasLimit: 59941351n,
        gasUsed: 7545006n,
        timestamp: 1755911328n,
        extraData: "0xd883010f0b846765746888676f312e32342e32856c696e7578",
        mixHash: "0x1e51d45b5109e05249b12823031e12efc6bd3d594abf51178207570ff3c341ec",
        nonce: "0x0000000000000000",
        baseFeePerGas: 2558257n,
        withdrawalsRoot: "0x57f125b7c33933258d27cf8f90a0e856bf9ad73790eb4889f06cc41fa8ec1fad",
        blobGasUsed: 262144n,
        excessBlobGas: 0n,
        parentBeaconBlockRoot: "0xf89f3fe12da24f2018b32b060312cc0756e7772184683c0c7bf024c80bceccc0",
        requestsHash: "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    };
    
    // 2. Make array with only block header items.
    const blockHeader = [
        block.parentHash, 
        block.sha3Uncles,
        block.miner,
        block.stateRoot,
        block.transactionsRoot,
        block.receiptsRoot,
        block.logsBloom,
        block.difficulty,
        block.number,
        block.gasLimit,
        block.gasUsed,
        block.timestamp,
        block.extraData,
        block.mixHash,
        block.nonce,
        block.baseFeePerGas,
        block.withdrawalsRoot,
        block.blobGasUsed,
        block.excessBlobGas,
        block.parentBeaconBlockRoot,
        block.requestsHash,
    ];

    // 3. RLP encode the block header, turning it into uint8 array.
    const encodedHeader = RLP.encode(blockHeader); 

    // 4. Convert encoded header to a Buffer and then to hex so we can hash it.
    const encodedHeaderHex = Buffer.from(encodedHeader).toString('hex'); 

    // 5. Hash the encodedHex to verify block hash
    const recreatedBlockHash = ethers.utils.keccak256('0x' + encodedHeaderHex);
    console.log(recreatedBlockHash); 

}
verifyCancunToCurrentHash();