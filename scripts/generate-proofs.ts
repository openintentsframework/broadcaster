import hre from 'hardhat'
import {
  Address,
  createPublicClient,
  GetContractReturnType,
  Hash,
  Hex,
  http,
  PublicClient,
  toHex,
  encodeAbiParameters,
  getContract,
  keccak256,
  hexToBigInt,
  encodePacked
} from 'viem'
import { reset } from '@nomicfoundation/hardhat-toolbox-viem/network-helpers.js'
import { BaseProverHelper } from '../src/ts/BaseProverHelper.ts'
import { iBufferAbi } from '../wagmi/abi.ts'

export class BroadcasterProverHelper 
    extends BaseProverHelper
{
    
  readonly bufferAddress: Address = '0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071'

  async buildInputForGetTargetBlockHash(): Promise<{
        input: Hex
        targetBlockHash: Hash
      }> {
        const { targetBlockHash, targetBlockNumber } =
          await this._findLatestAvailableTargetChainBlock(
            await this.homeChainClient.getBlockNumber()
          )
        return {
          input: encodeAbiParameters([{ type: 'uint256' }], [targetBlockNumber]),
          targetBlockHash,
        }
      }

      async buildInputForVerifyTargetBlockHash(
        homeBlockHash: Hash,
        message: Hash,
        publisher: Address,
      ): Promise<{ input: Hex; targetBlockHash: Hash }> {
        const homeBlockNumber = (
          await this.homeChainClient.getBlock({ blockHash: homeBlockHash })
        ).number
        const { targetBlockHash, targetBlockNumber } =
          await this._findLatestAvailableTargetChainBlock(homeBlockNumber)
    
        const slot = hexToBigInt(
          keccak256(
            encodeAbiParameters(
              [{ type: 'bytes32' }, { type: 'address' }],
              [message, publisher]
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
          targetBlockHash,
        }
      }

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
        targetBlockHash: Hash
      }> {
        const bufferContract = this._bufferContract()
        const targetBlockNumber = await bufferContract.read.newestBlockNumber({
          blockNumber: homeBlockNumber,
        })
        const targetBlockHash = await bufferContract.read.parentChainBlockHash(
          [targetBlockNumber],
          { blockNumber: homeBlockNumber }
        )
    
        return {
          targetBlockNumber,
          targetBlockHash,
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

async function initialSetup(
  homeUrl: string,
  targetUrl: string,
  //forkBlockNumber: bigint
) {
  await reset(homeUrl)
  const homeClient = await hre.viem.getPublicClient()
  //patchHardhatClient(homeClient, homeUrl)
  const targetClient = createPublicClient({
    transport: http(targetUrl),
  })
  return {
    homeClient,
    targetClient,
  }
}

function patchHardhatClient(
  hardhatClient: PublicClient,
  forkUrl: string
) {
  const forkClient = createPublicClient({
    transport: http(forkUrl),
  })
  hardhatClient.getProof = async args => {
    const blockTag = args.blockTag || args.blockNumber
    let blockNumber =
      typeof blockTag === 'bigint'
        ? blockTag
        : (await hardhatClient.getBlock({ blockTag })).number
    if (blockNumber === null) {
      throw new Error(`Block number ${blockTag} not found`)
    }

    return forkClient.getProof({
      ...args,
      blockTag: undefined,
    })
  }
}

function getEnv(key: string) {
  const value = process.env[key]
  if (value === undefined) {
    throw new Error(`Environment variable ${key} is not set`)
  }
  return value
}


async function main() {

  let homeClient: PublicClient
  let targetClient: PublicClient

  const clients = await initialSetup(
    getEnv('ARBITRUM_RPC_URL'),
    getEnv('ETHEREUM_RPC_URL')
  )

  homeClient = clients.homeClient
  targetClient = clients.targetClient

  const broadcasterProverHelper = new BroadcasterProverHelper(
    homeClient,
    targetClient
  )

  const { input, targetBlockHash } =
    await broadcasterProverHelper.buildInputForGetTargetBlockHash()

    console.log("input", input)
    console.log("targetBlockHash", targetBlockHash)

    // targetBlockHash is a bytes32 hash (0x...)  and input is a bytes (0x...), I want to get them together in a single file, where the first 32 bytes are the targetBlockHash and the rest are the input

    const payloadGetTargetBlockHash = encodePacked([{ type: 'bytes32' }, { type: 'bytes' }], [targetBlockHash, input])

    

    console.log("payloadGetTargetBlockHash", payloadGetTargetBlockHash.toString())





  

}

main()
