import {
  Address,
  BlockTag,
  encodeAbiParameters,
  getContract,
  GetContractReturnType,
  Hash,
  Hex,
  hexToBigInt,
  keccak256,
  PublicClient,
} from 'viem'
import { IProverHelper } from './IProverHelper'
import { BaseProverHelper } from './BaseProverHelper'
import { childToParentProverAbi, iBufferAbi } from '../../wagmi/abi'

/**
 * ChildToParentProverHelper is a class that provides helper methods for interacting
 * with the child to parent IStateProver contract.
 *
 * It extends the BaseProverHelper class and implements the IProverHelper interface.
 *
 * buildInputForGetTargetBlockHash and buildInputForVerifyTargetBlockHash methods
 * are currently not implemented and return a hardcoded block hash.
 *
 * buildInputForVerifyStorageSlot is fully implemented and requires no changes
 * unless the prover's verifyStorageSlot function is modified.
 */
export class ChildToParentProverHelper
  extends BaseProverHelper
  implements IProverHelper
{
  readonly bufferAddress: Address = '0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071'
  readonly blockHashMappingSlot: bigint = 51n

  /**
   * @see IProverHelper.buildInputForGetTargetBlockHash
   */
  async buildInputForGetTargetBlockHash(): Promise<{
    input: Hex
    targetStateCommitment: Hash
  }> {
    const { targetStateCommitment, targetBlockNumber } =
      await this._findLatestAvailableTargetChainBlock(
        await this.homeChainClient.getBlockNumber()
      )
    return {
      input: encodeAbiParameters([{ type: 'uint256' }], [targetBlockNumber]),
      targetStateCommitment,
    }
  }

  async buildInputForGetTargetBlockHashByBlockNumber(blockNumber: bigint): Promise<{
    input: Hex
    targetStateCommitment: Hash
  }> {
    //// TODO

    return {
      input: encodeAbiParameters([{ type: 'uint256' }], [blockNumber]),
      targetStateCommitment: '0x' as `0x${string}`,
    }
  }

  /**
   * @see IProverHelper.buildInputForGetTargetBlockHash
   */
  async buildInputForVerifyTargetBlockHash(
    homeBlockHash: Hash
  ): Promise<{ input: Hex; targetStateCommitment: Hash }> {
    const homeBlockNumber = (
      await this.homeChainClient.getBlock({ blockHash: homeBlockHash })
    ).number
    const { targetStateCommitment, targetBlockNumber } =
      await this._findLatestAvailableTargetChainBlock(homeBlockNumber)

    const slot = hexToBigInt(
      keccak256(
        encodeAbiParameters(
          [{ type: 'uint256' }, { type: 'uint256' }],
          [targetBlockNumber, this.blockHashMappingSlot]
        )
      )
    )

    const rlpBlockHeader = await this._getRlpBlockHeader('home', homeBlockHash)
    const { rlpAccountProof, rlpStorageProof } =
      await this._getRlpStorageAndAccountProof(
        'home',
        homeBlockHash,
        this.bufferAddress,
        slot
      )

    const input = encodeAbiParameters(
      [
        { type: 'bytes' }, // block header
        { type: 'uint256' }, // target block number
        { type: 'bytes' }, // account proof
        { type: 'bytes' }, // storage proof
      ],
      [rlpBlockHeader, targetBlockNumber, rlpAccountProof, rlpStorageProof]
    )

    return {
      input,
      targetStateCommitment,
    }
  }

  /**
   * @see IProverHelper.buildInputForVerifyStorageSlot
   */
  async buildInputForVerifyStorageSlot(
    targetStateCommitment: Hash,
    account: Address,
    slot: bigint
  ): Promise<{ input: Hex; slotValue: Hash }> {
    const rlpBlockHeader = await this._getRlpBlockHeader(
      'target',
      targetStateCommitment
    )
    const { rlpAccountProof, rlpStorageProof, slotValue } =
      await this._getRlpStorageAndAccountProof(
        'target',
        targetStateCommitment,
        account,
        slot
      )
    
      console.log("BBB");

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

  async _findLatestAvailableTargetChainBlock(homeBlockNumber: bigint): Promise<{
    targetBlockNumber: bigint
    targetStateCommitment: Hash
  }> {
    const bufferContract = this._bufferContract()
    const targetBlockNumber = await bufferContract.read.newestBlockNumber({
      blockNumber: homeBlockNumber,
    })
    const targetStateCommitment = await bufferContract.read.parentChainBlockHash(
      [targetBlockNumber],
      { blockNumber: homeBlockNumber }
    )

    return {
      targetBlockNumber,
      targetStateCommitment,
    }
  }

  _bufferContract(): GetContractReturnType<typeof iBufferAbi, PublicClient> {
    return getContract({
      address: this.bufferAddress,
      abi: iBufferAbi,
      client: this.homeChainClient,
    })
  }
}
