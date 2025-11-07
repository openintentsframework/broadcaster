import {
  Address,
  encodeAbiParameters,
  Hash,
  Hex,
} from 'viem'
import { IProverHelper } from '../IProverHelper'
import { BaseProverHelper } from '../BaseProverHelper'

/**
 * ChildToParentProverHelper for Optimism
 * 
 * This helper generates proofs for the Optimism ChildToParentProver contract.
 * It reads L1 block hashes from the L1Block predeploy on Optimism.
 * 
 * Optimism L1Block predeploy: 0x4200000000000000000000000000000000000015
 * L1 block hash storage slot: 2
 */
export class OptimismChildToParentProverHelper
  extends BaseProverHelper
  implements IProverHelper
{
  readonly l1BlockPredeploy: Address = '0x4200000000000000000000000000000000000015'
  readonly l1BlockHashSlot: bigint = 2n  // hash is at slot 2

  /**
   * Build input for getTargetBlockHash()
   * For Optimism, this reads the L1Block predeploy directly, so input can be empty
   */
  async buildInputForGetTargetBlockHash(): Promise<{
    input: Hex
    targetBlockHash: Hash
  }> {
    // Read the L1 block hash directly from the L1Block predeploy
    const targetBlockHash = await this.homeChainClient.getStorageAt({
      address: this.l1BlockPredeploy,
      slot: `0x${this.l1BlockHashSlot.toString(16)}` as Hex,
    }) as Hash

    // getTargetBlockHash() on Optimism doesn't need any input
    // It reads the predeploy directly
    return {
      input: '0x' as Hex,
      targetBlockHash,
    }
  }

  /**
   * Build input for verifyTargetBlockHash()
   * This requires Merkle proofs of the L1Block predeploy's storage
   */
  async buildInputForVerifyTargetBlockHash(
    homeBlockHash: Hash
  ): Promise<{ input: Hex; targetBlockHash: Hash }> {
    const homeBlockNumber = (
      await this.homeChainClient.getBlock({ blockHash: homeBlockHash })
    ).number

    // Read the L1 block hash from the predeploy at this specific block
    const targetBlockHash = await this.homeChainClient.getStorageAt({
      address: this.l1BlockPredeploy,
      slot: `0x${this.l1BlockHashSlot.toString(16)}` as Hex,
      blockNumber: homeBlockNumber,
    }) as Hash

    // Get the RLP-encoded block header
    const rlpBlockHeader = await this._getRlpBlockHeader('home', homeBlockHash)

    // Get Merkle proofs for the L1Block predeploy storage
    const { rlpAccountProof, rlpStorageProof } =
      await this._getRlpStorageAndAccountProof(
        'home',
        homeBlockHash,
        this.l1BlockPredeploy,
        this.l1BlockHashSlot
      )

    // Encode: (bytes blockHeader, bytes accountProof, bytes storageProof)
    const input = encodeAbiParameters(
      [
        { type: 'bytes' }, // block header
        { type: 'bytes' }, // account proof
        { type: 'bytes' }, // storage proof
      ],
      [rlpBlockHeader, rlpAccountProof, rlpStorageProof]
    )

    return {
      input,
      targetBlockHash,
    }
  }

  /**
   * Build input for verifyStorageSlot()
   * This verifies a storage slot on the target chain (Ethereum L1)
   */
  async buildInputForVerifyStorageSlot(
    targetBlockHash: Hash,
    account: Address,
    slot: bigint
  ): Promise<{ input: Hex; slotValue: Hash }> {
    const rlpBlockHeader = await this._getRlpBlockHeader(
      'target',
      targetBlockHash
    )
    const { rlpAccountProof, rlpStorageProof, slotValue } =
      await this._getRlpStorageAndAccountProof(
        'target',
        targetBlockHash,
        account,
        slot
      )

    // Encode: (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    const input = encodeAbiParameters(
      [
        { type: 'bytes' }, // block header
        { type: 'address' }, // account
        { type: 'uint256' }, // slot
        { type: 'bytes' }, // account proof
        { type: 'bytes' }, // storage proof
      ],
      [rlpBlockHeader, account, slot, rlpAccountProof, rlpStorageProof]
    )

    return { input, slotValue }
  }

  /**
   * Build input for getTargetBlockHashByBlockNumber()
   * Gets the target block hash at a specific home chain block number
   */
  async buildInputForGetTargetBlockHashByBlockNumber(
    blockNumber: bigint
  ): Promise<{ input: Hex; targetBlockHash: Hash }> {
    // Read the L1 block hash from the predeploy at the specified block number
    const targetBlockHash = await this.homeChainClient.getStorageAt({
      address: this.l1BlockPredeploy,
      slot: `0x${this.l1BlockHashSlot.toString(16)}` as Hex,
      blockNumber,
    }) as Hash

    // For Optimism, getTargetBlockHashByBlockNumber() doesn't need input
    // It reads the predeploy directly at the given block
    return {
      input: '0x' as Hex,
      targetBlockHash,
    }
  }
  
}

