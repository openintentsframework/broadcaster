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
import dotenv from 'dotenv'
import fs from 'fs'
dotenv.config()

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
        broadcasterAddress: Address,
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

        console.log("slot", slot);
    
        const rlpBlockHeader = await this._getRlpBlockHeader('home', homeBlockHash)
        const { rlpAccountProof, rlpStorageProof } =
          await this._getRlpStorageAndAccountProof(
            'home',
            homeBlockHash,
            broadcasterAddress,
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
  //await reset(homeUrl)
  const homeClient = createPublicClient({
    transport: http(homeUrl),
  })
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

  const { input: input1, targetBlockHash } =
    await broadcasterProverHelper.buildInputForGetTargetBlockHash()

    console.log("input1", input1);
    console.log("targetBlockHash", targetBlockHash);

    console.log("------------------------------------------------------------");

    // the payload is basically the first string concatenated with the second string, but removing the 0x prefix from the second string
    const payloadGetTargetBlockHash = input1 + targetBlockHash.slice(2);

    // write the payload to a file
    fs.writeFileSync('test/payloads/arbitrum/broadcaster_get.hex', payloadGetTargetBlockHash)

    const {input: input2, slotValue} = await broadcasterProverHelper.buildInputForVerifyStorageSlot(
      targetBlockHash,
      '0x40f58bd4616a6e76021f1481154db829953bf01b',
      34911475602450811603768521319529596250529393651395612722173680283820326314854n
    )

    
    console.log("targetBlockHash", targetBlockHash);
    console.log("input2", input2);

    console.log("------------------------------------------------------------");


    const payloadVerifyStorageSlot = targetBlockHash + input2.slice(2)

    // write the payload to a file
    fs.writeFileSync('test/payloads/arbitrum/broadcaster_verify_slot.hex', payloadVerifyStorageSlot)

    const homeBlockHash = (
      await homeClient.getBlock()
    ).hash

    const {input: input3, targetBlockHash: targetBlockHash2} = await broadcasterProverHelper.buildInputForVerifyTargetBlockHash(homeBlockHash, 
                    "0x0000000000000000000000000000000000000000000000000000000074657374", "0x9a56ffd72f4b526c523c733f1f74197a51c495e1", "0x40f58bd4616a6e76021f1481154db829953bf01b")

    const payloadVerifyTargetBlockHash = homeBlockHash + targetBlockHash2.slice(2) + input3.slice(2);

    // write the payload to a file
    fs.writeFileSync('test/payloads/arbitrum/broadcaster_verify_target.hex', payloadVerifyTargetBlockHash)

    console.log("homeBlockHash", homeBlockHash);
    console.log("targetBlockHash2", targetBlockHash2);
    console.log("input3", input3);

    console.log("------------------------------------------------------------");






  

}

main()
