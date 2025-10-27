import hre from 'hardhat'
import {
  Address,
  createPublicClient,
  GetContractReturnType,
  Hash,
  http,
  PublicClient,
  toHex,
} from 'viem'
import {
  ChildToParentProverHelper,
  IProverHelper,
} from '../../../src/ts/'
import { expect } from 'chai'
import { IBlockHashProver$Type } from '../../../artifacts/src/contracts/interfaces/IBlockHashProver.sol/IBlockHashProver'
import { reset } from '@nomicfoundation/hardhat-toolbox-viem/network-helpers'

type TestContext = {
  proverType: 'ChildToParentProver' | 'ParentToChildProver'
  proverContract: GetContractReturnType<
    IBlockHashProver$Type['abi'],
    PublicClient
  >
  forkBlockNumber: bigint
  proverHelper: IProverHelper
  expectedTargetBlockHash: Hash
  knownStorageSlotAccount: Address
  knownStorageSlot: bigint
  knownStorageSlotValue: Hash
}

const gasEstimates = {
  ParentToChildProver: {
    getTargetBlockHash: 0n,
    verifyTargetBlockHash: 0n,
    verifyStorageSlot: 0n,
  },
  ChildToParentProver: {
    getTargetBlockHash: 0n,
    verifyTargetBlockHash: 0n,
    verifyStorageSlot: 0n,
  },
}

let homeClient: PublicClient
let targetClient: PublicClient
describe('Basic Prover Tests', () => {

  async function getTestContext(proverContructorParams: Array<any>, forkBlockNumber: bigint): Promise<TestContext> {

    const knownStorageSlotAccount = '0x38f918D0E9F1b721EDaA41302E399fa1B79333a9'
    const knownStorageSlot = 10n

    const parentBlock = await targetClient.getBlock({
      
    });

    const knownStorageSlotValue = await targetClient.getStorageAt({
      address: knownStorageSlotAccount,
      slot: toHex(knownStorageSlot),
    })

    const proverContract = (await hre.viem.deployContract(
      'ChildToParentProver',
      proverContructorParams as Array<any>
    ));

    const proverHelper = new ChildToParentProverHelper(
      homeClient,
      targetClient
    );





    return {
      proverType: 'ChildToParentProver',
      forkBlockNumber: forkBlockNumber,
      targetBlockNumber: parentBlock.number,
      expectedTargetBlockHash: parentBlock.hash,
      knownStorageSlotAccount: '0x38f918D0E9F1b721EDaA41302E399fa1B79333a9',
      knownStorageSlot: 10n,
      knownStorageSlotValue: knownStorageSlotValue as `0x${string}`,
      proverContract: proverContract as any,
      proverHelper: proverHelper as any,
    } as unknown as TestContext
  }


  describe('ChildToParentProver', () => {

    let ctx!: TestContext;

    before(async () => {
      const clients = await initialSetup(
        getEnv('ARBITRUM_RPC_URL'),
        getEnv('ETHEREUM_RPC_URL')
      )
      homeClient = clients.homeClient
      targetClient = clients.targetClient

      const childBlockNumber: bigint = await homeClient.getBlockNumber();
      const childChainId = await homeClient.getChainId();

      ctx = await getTestContext([childChainId], childBlockNumber);
    })

    it('getTargetBlockHash should return the correct block hash', async () => {
      const { input, targetBlockHash } =
        await ctx.proverHelper.buildInputForGetTargetBlockHash()
      //expect(targetBlockHash).to.equal(ctx.expectedTargetBlockHash)
      expect(await ctx.proverContract.read.getTargetBlockHash([input])).to.equal(
        targetBlockHash
      )

      console.log("getTargetBlockHash", input, targetBlockHash)
  
      gasEstimates[ctx.proverType].getTargetBlockHash =
        await homeClient.estimateContractGas({
          address: ctx.proverContract.address,
          abi: ctx.proverContract.abi,
          functionName: 'getTargetBlockHash',
          args: [input],
        })
    })
  
    it('verifyStorageSlot should return the correct slot value', async () => {
      const { input, slotValue } =
        await ctx.proverHelper.buildInputForVerifyStorageSlot(
          ctx.expectedTargetBlockHash,
          ctx.knownStorageSlotAccount,
          ctx.knownStorageSlot
        )
      expect(slotValue).to.equal(
        ctx.knownStorageSlotValue,
        "buildInputForVerifyStorageSlot didn't return the expected slot value"
      )
      const [account, slot, value] =
        await ctx.proverContract.read.verifyStorageSlot([
          ctx.expectedTargetBlockHash,
          input,
        ])
      
      console.log("verifyStorageSlot",ctx.expectedTargetBlockHash, input, account, slot, value)

      expect(account).to.equal(
        ctx.knownStorageSlotAccount,
        "verifyStorageSlot didn't return the expected account"
      )
      expect(slot).to.equal(
        ctx.knownStorageSlot,
        "verifyStorageSlot didn't return the expected slot"
      )
      expect(value).to.equal(
        ctx.knownStorageSlotValue,
        "verifyStorageSlot didn't return the expected slot value"
      )
  
      gasEstimates[ctx.proverType].verifyStorageSlot =
        await homeClient.estimateContractGas({
          address: ctx.proverContract.address,
          abi: ctx.proverContract.abi,
          functionName: 'verifyStorageSlot',
          args: [ctx.expectedTargetBlockHash, input],
        })
    })

    it('verifyTargetBlockHash should return the correct block hash', async () => {
      const homeBlockHash = (
        await homeClient.getBlock({ blockNumber: ctx.forkBlockNumber })
      ).hash
      const { input, targetBlockHash } =
        await ctx.proverHelper.buildInputForVerifyTargetBlockHash(homeBlockHash)

      // Deploy prover contract on target chain
      await reset(getEnv('ETHEREUM_RPC_URL'))
      const targetChainId = await targetClient.getChainId();
      const proverContractCopy = await hre.viem.deployContract(
        'ChildToParentProver',
        [targetChainId]
      )
        expect(
        await proverContractCopy.read.verifyTargetBlockHash([
          homeBlockHash,
          input,
        ])
      ).to.equal(targetBlockHash)

      console.log("verifyTargetBlockHash", homeBlockHash, targetBlockHash, input)
  
      gasEstimates[ctx.proverType].verifyTargetBlockHash =
        await homeClient.estimateContractGas({
          address: ctx.proverContract.address,
          abi: ctx.proverContract.abi,
          functionName: 'verifyTargetBlockHash',
          args: [homeBlockHash, input],
        })
    })
  })

  after(() => {
    console.log('\nGas Estimates:', gasEstimates)
  })
})

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

function runBasicTests(ctx: TestContext) {
  
}

function getEnv(key: string) {
  const value = process.env[key]
  if (value === undefined) {
    throw new Error(`Environment variable ${key} is not set`)
  }
  return value
}

// since the hardhat network does not support the `eth_getProof` method,
// we need to patch the client bypass the hardhat network to query the forked RPC directly
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
      //blockNumber: blockNumber,
    })
  }
}
