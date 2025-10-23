import {
  Address,
  encodeAbiParameters,
  getContract,
  GetContractEventsReturnType,
  GetContractReturnType,
  Hash,
  Hex,
  hexToBigInt,
  keccak256,
  PublicClient,
} from 'viem'
import { IProverHelper } from './IProverHelper'
import { BaseProverHelper } from './BaseProverHelper'
import { iOutboxAbi, parentToChildProverAbi } from '../../wagmi/abi'

export class ParentToChildProverHelper
  extends BaseProverHelper
  implements IProverHelper
{
  // todo: document
  public readonly defaultLogBlockRangeSize = 10_000n
  public readonly defaultMaxLogLookback = 1_000_000n

  constructor(
    public readonly proverAddress: Address,
    homeChainClient: PublicClient,
    targetChainClient: PublicClient
  ) {
    super(homeChainClient, targetChainClient)
  }

  /**
   * @see IProverHelper.buildInputForGetTargetBlockHash
   */
  async buildInputForGetTargetBlockHash(): Promise<{
    input: Hex
    targetBlockHash: Hash
  }> {
    const { targetBlockHash, sendRoot } =
      await this._findLatestAvailableTargetChainBlock(
        await this.homeChainClient.getBlockNumber()
      )
    return {
      input: encodeAbiParameters([{ type: 'bytes32' }], [sendRoot]),
      targetBlockHash,
    }
  }

  async buildInputForGetTargetBlockHashByBlockNumber(blockNumber: bigint): Promise<{
    input: Hex
    targetBlockHash: Hash
  }> {
    console.log("blockNumber", blockNumber);

    // const targetBlock = await this.targetChainClient.getBlock({ blockNumber });
    // console.log("targetBlock", targetBlock);
    // // @ts-ignore
    // console.log("sendRoot", targetBlock.sendRoot);

    const { targetBlockHash, sendRoot } =  await this._findLatestAvailableTargetChainBlock(blockNumber);

    return {
      // @ts-ignore
      input: encodeAbiParameters([{ type: 'bytes32' }], [sendRoot]),
      targetBlockHash: targetBlockHash,
    }
  }

  /**
   * @see IProverHelper.buildInputForVerifyTargetBlockHash
   */
  async buildInputForVerifyTargetBlockHash(
    homeBlockHash: Hash
  ): Promise<{ input: Hex; targetBlockHash: Hash }> {
    const { targetBlockHash, sendRoot } =
      await this._findLatestAvailableTargetChainBlock(
        (await this.homeChainClient.getBlock({ blockHash: homeBlockHash }))
          .number
      )

    const slot = hexToBigInt(
      keccak256(
        encodeAbiParameters(
          [{ type: 'bytes32' }, { type: 'uint256' }],
          [sendRoot, await this._proverContract().read.rootsSlot()]
        )
      )
    )

    const rlpBlockHeader = await this._getRlpBlockHeader('home', homeBlockHash)
    const { rlpAccountProof, rlpStorageProof } =
      await this._getRlpStorageAndAccountProof(
        'home',
        homeBlockHash,
        await this._proverContract().read.outbox(),
        slot
      )

    const input = encodeAbiParameters(
      [
        { type: 'bytes' }, // block header
        { type: 'bytes32' }, // send root
        { type: 'bytes' }, // account proof
        { type: 'bytes' }, // storage proof
      ],
      [rlpBlockHeader, sendRoot, rlpAccountProof, rlpStorageProof]
    )

    

    return {
      input,
      targetBlockHash,
    }
  }

  /**
   * @see IProverHelper.buildInputForVerifyStorageSlot
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
    
    console.log("get proof BBB");

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
   * Find the latest target chain block hash that is available as of the given home block number.
   * @param homeBlockNumber home chain block number to search up to
   * @param overrides Optional parameters to control the log query size and maximum lookback
   * @returns The latest target chain block hash and the corresponding send root
   */
  async _findLatestAvailableTargetChainBlock(
    homeBlockNumber: bigint,
    overrides?: { logBlockRangeSize?: bigint; maxLogLookback?: bigint }
  ): Promise<{
    sendRoot: Hash
    targetBlockHash: Hash
  }> {
    const logBlockRangeSize =
      overrides?.logBlockRangeSize ?? this.defaultLogBlockRangeSize
    const maxLogLookback =
      overrides?.maxLogLookback ?? this.defaultMaxLogLookback

    if (logBlockRangeSize < 1n || maxLogLookback < 1n) {
      throw new Error(`logBlockRangeSize and maxLogLookback must be at least 1`)
    }

    const outboxContract = await this._outboxContract()

    let fromBlock = homeBlockNumber - logBlockRangeSize + 1n
    let latestEvent:
      | GetContractEventsReturnType<typeof iOutboxAbi, 'SendRootUpdated'>[0]
      | null = null
    while (
      latestEvent === null &&
      fromBlock > homeBlockNumber - logBlockRangeSize
    ) {
      const toBlock = fromBlock + logBlockRangeSize - 1n
      const events = await outboxContract.getEvents.SendRootUpdated(
        {},
        {
          fromBlock,
          toBlock,
        }
      )

      if (events.length > 0) {
        latestEvent = events[events.length - 1]
      }

      fromBlock -= logBlockRangeSize
    }

    if (!latestEvent) {
      throw new Error(
        'No SendRootUpdated event found, consider increasing maxLogLookback'
      )
    }

    return {
      sendRoot: latestEvent.args.outputRoot!,
      targetBlockHash: latestEvent.args.l2BlockHash!,
    }
  }

  _proverContract(): GetContractReturnType<
    typeof parentToChildProverAbi,
    PublicClient
  > {
    return getContract({
      address: this.proverAddress,
      abi: parentToChildProverAbi,
      client: this.homeChainClient,
    })
  }

  async _outboxContract(): Promise<
    GetContractReturnType<typeof iOutboxAbi, PublicClient>
  > {
    return getContract({
      address: await this._proverContract().read.outbox(),
      abi: iOutboxAbi,
      client: this.homeChainClient,
    })
  }
}
