#!/usr/bin/env node
import { parseArgs } from "node:util";
import process from "node:process";
import { isAddress, createPublicClient, http, toRlp, keccak256, toHex } from "viem";
import type { Hex, PublicClient } from "viem";
import fs from "node:fs";


const {values, positionals} = parseArgs({
    options: {
        rpc: {type: "string"},
        account: {type: "string"},
        slot: {type: "string"},
        block: {type: "string"},
        output: {type: "string"},
    },
    allowPositionals: false
});


// -- Validations --

const rpc = values.rpc;
const account = values.account;
const slot = BigInt(values.slot as string);
const block = BigInt(Number(values.block));
const output = values.output;

assert(rpc, "RPC is required");
assert(account, "Account is required");
assert(slot, "Slot is required");
assert(block, "Block is required");


if(!isAddress(account as `0x${string}`)){
    fail("--account must be a valid EVM address");
}


const client = createPublicClient({
    transport: http(rpc),
})


async function main() {

    const blockHeader = await client.getBlock({
        blockNumber: block,
    });

    const rlpBlockHeader = _convertToRlpBlock(blockHeader);

    const expectedBlockHash = keccak256(rlpBlockHeader);

    if(expectedBlockHash !== blockHeader.hash){
        fail("Block hash mismatch");
    }

    const {stateRoot, rlpAccountProof, rlpStorageProof, slotValue} = await _getRlpStorageAndAccountProof(client, account as `0x${string}` , slot, block);

    if(stateRoot !== blockHeader.stateRoot){
        fail("State root mismatch");
    }

    const out = {
        blockNumber: toHex(blockHeader.number),
        blockHash: blockHeader.hash,
        stateRoot: stateRoot,
        account: account,
        slot: toHex(slot, {size: 32}),
        slotValue: slotValue,
        rlpBlockHeader: rlpBlockHeader,
        rlpAccountProof: rlpAccountProof,
        rlpStorageProof: rlpStorageProof,
        ...('sendRoot' in blockHeader && { sendRoot: (blockHeader as any).sendRoot }),
    }

    if(output){
        fs.writeFileSync(output, JSON.stringify(out, null, 2));
    } else {
        console.log(out);
    }
}

async function _getRlpStorageAndAccountProof(client: PublicClient , account: `0x${string}`, slot: bigint, block: bigint):
 Promise<{
    rlpAccountProof: Hex,
    rlpStorageProof: Hex,
    slotValue: Hex,
    stateRoot: Hex,
}> {
    const proof = await client.getProof({
        address: account,
        storageKeys: [toHex(slot, {size: 32})],
        blockNumber: block,
    })

    return {
        stateRoot: keccak256(proof.accountProof[0]),
        rlpAccountProof: toRlp(proof.accountProof),
        rlpStorageProof: toRlp(proof.storageProof[0].proof),
        slotValue: toHex(Number(proof.storageProof[0].value)),
    }
}

/**
   * Converts an RPC block response to RLP format.
   * Works up to the Pectra fork.
   * For reference on the block structure, see:
   * https://github.com/ethereum/go-ethereum/blob/35dd84ce2999ecf5ca8ace50a4d1a6abc231c370/core/types/block.go#L75-L109
   * @param rpcBlock The block response from the RPC
   * @returns The RLP encoded block
   */
function _convertToRlpBlock(rpcBlock: any): Hex {
    const encodeInt = (hex: string) => {
      const value = BigInt(hex)
      if (value === 0n) return '0x'
      return cleanHex(value.toString(16)) as Hex
    }

    const cleanHex = (hex: string) => {
      const clean = hex.replace(/^0x/, '')
      return `0x${clean.length % 2 === 0 ? clean : '0' + clean}` as Hex
    }

    const headerFields: Hex[] = [
      cleanHex(rpcBlock.parentHash),
      cleanHex(rpcBlock.sha3Uncles),
      cleanHex(rpcBlock.miner),
      cleanHex(rpcBlock.stateRoot),
      cleanHex(rpcBlock.transactionsRoot),
      cleanHex(rpcBlock.receiptsRoot),
      cleanHex(rpcBlock.logsBloom),
      encodeInt(rpcBlock.difficulty),
      encodeInt(rpcBlock.number),
      encodeInt(rpcBlock.gasLimit),
      encodeInt(rpcBlock.gasUsed),
      encodeInt(rpcBlock.timestamp),
      cleanHex(rpcBlock.extraData),
      cleanHex(rpcBlock.mixHash),
      cleanHex(rpcBlock.nonce)
    ]

    if (rpcBlock.baseFeePerGas)
      headerFields.push(encodeInt(rpcBlock.baseFeePerGas))
    if (rpcBlock.withdrawalsRoot)
      headerFields.push(cleanHex(rpcBlock.withdrawalsRoot))
    if (rpcBlock.blobGasUsed) headerFields.push(encodeInt(rpcBlock.blobGasUsed))
    if (rpcBlock.excessBlobGas != undefined)
      headerFields.push(encodeInt(rpcBlock.excessBlobGas))
    if (rpcBlock.parentBeaconBlockRoot)
      headerFields.push(cleanHex(rpcBlock.parentBeaconBlockRoot))
    if (rpcBlock.requestsHash)
      headerFields.push(cleanHex(rpcBlock.requestsHash))

    return toRlp(headerFields)
  }


function assert(cond: unknown, msg: string): asserts cond {
    if (!cond) fail(msg);
  }
  
function fail(msg: string) {
    console.error(`[storage-proof-generator] ${msg}`);
    process.exit(1);
}
main();
