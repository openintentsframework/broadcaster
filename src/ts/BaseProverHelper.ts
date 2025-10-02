import { Address, Hash, Hex, PublicClient, toHex, toRlp } from 'viem'

/**
 * BaseProverHelper is a base class for prover helpers that provides common functionality
 * for interacting prover contracts.
 *
 * It provides methods to get RLP encoded block headers and storage/account proofs.
 */
export abstract class BaseProverHelper {
  constructor(
    readonly homeChainClient: PublicClient,
    readonly targetChainClient: PublicClient
  ) {}

  /**
   * Retrieves the RLP encoded block header for a given block hash.
   * @param chain target or home chain
   * @param blockHash Block hash to retrieve the block header for
   * @returns The RLP encoded block header
   * @throws Error if the block is not found
   */
  protected async _getRlpBlockHeader(
    chain: 'target' | 'home',
    blockHash: Hash
  ): Promise<Hex> {
    const client =
      chain === 'target' ? this.targetChainClient : this.homeChainClient
    const block: any = await client.transport.request({
      method: 'eth_getBlockByHash',
      params: [blockHash, false],
    })

    if (!block) {
      throw new Error('Block not found')
    }

    return this._convertToRlpBlock(block)
  }

  /**
   *
   * @param chain target or home chain
   * @param blockHash Block hash to generate proofs against
   * @param account Account to generate a proof for
   * @param slot Storage slot to generate a proof for
   * @returns The RLP encoded account proof, storage proof, and the slot value
   * @throws Error if the block is not found
   */
  protected async _getRlpStorageAndAccountProof(
    chain: 'target' | 'home',
    blockHash: Hash,
    account: Address,
    slot: bigint
  ): Promise<{ rlpAccountProof: Hex; rlpStorageProof: Hex; slotValue: Hash }> {
    const client =
      chain === 'target' ? this.targetChainClient : this.homeChainClient
    const block = await client.getBlock({
      blockHash,
      includeTransactions: false,
    })

    if (!block) {
      throw new Error('Block not found')
    }

    const proof = await client.getProof({
      address: account,
      storageKeys: [toHex(slot, { size: 32 })],
      blockNumber: block.number,
    })

    const slotValue = toHex(proof.storageProof[0].value, { size: 32 })
    const rlpAccountProof = toRlp(proof.accountProof)
    const rlpStorageProof = toRlp(proof.storageProof[0].proof)

    return {
      rlpAccountProof,
      rlpStorageProof,
      slotValue,
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
  protected _convertToRlpBlock(rpcBlock: any): Hex {
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
      cleanHex(rpcBlock.nonce),
    ]

    if (rpcBlock.baseFeePerGas)
      headerFields.push(encodeInt(rpcBlock.baseFeePerGas))
    if (rpcBlock.withdrawalsRoot)
      headerFields.push(cleanHex(rpcBlock.withdrawalsRoot))
    if (rpcBlock.blobGasUsed) headerFields.push(encodeInt(rpcBlock.blobGasUsed))
    if (rpcBlock.excessBlobGas)
      headerFields.push(encodeInt(rpcBlock.excessBlobGas))
    if (rpcBlock.parentBeaconBlockRoot)
      headerFields.push(cleanHex(rpcBlock.parentBeaconBlockRoot))
    if (rpcBlock.requestsHash)
      headerFields.push(cleanHex(rpcBlock.requestsHash))

    return toRlp(headerFields)
  }
}
