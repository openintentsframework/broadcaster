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
  IProverHelper,
  ParentToChildProverHelper,
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
  targetBlockNumber: bigint
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
}



let homeClient: PublicClient
let targetClient: PublicClient
describe('Basic Prover Tests', () => {
    async function getTestContext(proverContructorParams: Array<any>, forkBlockNumber: bigint): Promise<TestContext> {

        const OFFSET_CHILD_BLOCKS = 100000n;

        // get current block on the child chain
        const currentChildBlock = await targetClient.getBlock({
            includeTransactions: false,
        });

        const childBlockNumber = currentChildBlock.number;

        const childBlock = await targetClient.getBlock({
            blockNumber: childBlockNumber,
        });

        const knownStorageSlotValue = await targetClient.getStorageAt({
            address: '0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071',
            slot: toHex(50),
        })

        const proverContract = (await hre.viem.deployContract(
            'ParentToChildProver',
            proverContructorParams as Array<any>
          ));
    
          const proverHelper = new ParentToChildProverHelper(
            proverContract.address,
            homeClient,
            targetClient
          )


        return {
            proverType: 'ParentToChildProver',
            forkBlockNumber: forkBlockNumber,
            targetBlockNumber: childBlockNumber,
            expectedTargetBlockHash: childBlock.hash,
            knownStorageSlotAccount: '0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071',
            knownStorageSlot: 50n,
            knownStorageSlotValue: knownStorageSlotValue as `0x${string}`,
            proverContract: proverContract as any,
            proverHelper: proverHelper as any,
        }
    }

  describe('ParentToChildProver', () => {
    // constructor arguments for the Arbitrum Sepolia prover
    const OUTBOX = '0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F'
    const ROOTS_SLOT = 3n

    let ctx!: TestContext;

    before(async () => {
      const clients = await initialSetup(
        getEnv('ETHEREUM_RPC_URL'),
        getEnv('ARBITRUM_RPC_URL')
      )

      homeClient = clients.homeClient
      targetClient = clients.targetClient

      const parentBlockNumber: bigint = await homeClient.getBlockNumber();

      ctx = await getTestContext([OUTBOX, ROOTS_SLOT], parentBlockNumber);
    })


    it('getTargetBlockHash should return the correct block hash', async () => {
        const { input, targetBlockHash } =
          await ctx.proverHelper.buildInputForGetTargetBlockHash()
        const targetBlockHashFromContract = await ctx.proverContract.read.getTargetBlockHash([input])
        expect(targetBlockHashFromContract).to.equal(
          targetBlockHash
        )
    
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
        await homeClient.getBlock({ blockNumber: ctx.forkBlockNumber})
      ).hash

      const { input, targetBlockHash } =
        await ctx.proverHelper.buildInputForVerifyTargetBlockHash(homeBlockHash)
      //expect(targetBlockHash).to.equal(ctx.expectedTargetBlockHash)

      // Deploy prover contract on target chain
      await reset(getEnv('ARBITRUM_RPC_URL'))

      const proverContractCopy = await hre.viem.deployContract(
        'ParentToChildProver',
        [OUTBOX, ROOTS_SLOT]
      )



      expect(
        await proverContractCopy.read.verifyTargetBlockHash([
          homeBlockHash,
          input,
        ])
      ).to.equal(targetBlockHash)
    
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
