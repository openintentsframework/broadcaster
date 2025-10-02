import hre from 'hardhat'
import {
  getAddress,
  GetContractReturnType,
  keccak256,
  numberToHex,
  PublicClient,
  toHex,
  WalletClient,
} from 'viem'
import { BlockHashProverPointer$Type } from '../artifacts/src/contracts/BlockHashProverPointer.sol/BlockHashProverPointer'
import { expect } from 'chai'

const BLOCK_HASH_PROVER_POINTER_SLOT = numberToHex(
  BigInt(keccak256(toHex('eip7888.pointer.slot'))) - 1n
)

describe('BlockHashProverPointer', () => {
  let publicClient: PublicClient
  let owner: WalletClient
  let user: WalletClient

  let pointerContract: GetContractReturnType<
    BlockHashProverPointer$Type['abi'],
    PublicClient
  >

  beforeEach(async () => {
    publicClient = await hre.viem.getPublicClient()
    ;[, owner, user] = await hre.viem.getWalletClients()
    pointerContract = (await hre.viem.deployContract(
      'src/contracts/BlockHashProverPointer.sol:BlockHashProverPointer',
      [owner.account!.address]
    )) as any
  })

  it('should properly set the initial owner', async () => {
    expect(await pointerContract.read.owner()).to.eq(
      getAddress(owner.account!.address),
      'owner not set'
    )
  })

  it('should allow ownership transfer', async () => {
    await expect(
      pointerContract.write.transferOwnership([user.account!.address], {
        account: user.account!,
        chain: null,
      })
    ).to.be.rejectedWith(
      `OwnableUnauthorizedAccount("${getAddress(user.account!.address)}")`
    )

    await pointerContract.write.transferOwnership([user.account!.address], {
      account: owner.account!,
      chain: null,
    })
    expect(await pointerContract.read.owner()).to.eq(
      getAddress(user.account!.address),
      'owner not set'
    )
  })

  it('owner should be able to update prover', async () => {
    await expect(
      pointerContract.write.setBHP([user.account!.address], {
        account: user.account!,
        chain: null,
      })
    ).to.be.rejectedWith(
      `OwnableUnauthorizedAccount("${getAddress(user.account!.address)}")`
    )

    const mockProver = await hre.viem.deployContract('MockProver', [1])

    await pointerContract.write.setBHP([mockProver.address], {
      account: owner.account!,
      chain: null,
    })

    const expectedCodeHash = keccak256(
      (await publicClient.getCode({
        address: mockProver.address,
      }))!
    )

    expect(await pointerContract.read.implementationAddress()).to.eq(
      getAddress(mockProver.address),
      'prover not set'
    )
    expect(await pointerContract.read.implementationCodeHash()).to.eq(
      expectedCodeHash,
      'prover code hash not set'
    )

    expect(
      await publicClient.getStorageAt({
        address: pointerContract.address,
        slot: BLOCK_HASH_PROVER_POINTER_SLOT,
      })
    ).to.eq(expectedCodeHash, 'prover not set in storage')
  })

  it('should not allow decreasing prover versions', async () => {
    const mockProver1 = await hre.viem.deployContract('MockProver', [1])
    const mockProver2 = await hre.viem.deployContract('MockProver', [2])
    const mockProver3 = await hre.viem.deployContract('MockProver', [3])

    await pointerContract.write.setBHP([mockProver2.address], {
      account: owner.account!,
      chain: null,
    })

    await expect(
      pointerContract.write.setBHP([mockProver1.address], {
        account: owner.account!,
        chain: null,
      })
    ).to.be.rejectedWith('NonIncreasingVersion(2, 1)')

    await expect(
      pointerContract.write.setBHP([mockProver2.address], {
        account: owner.account!,
        chain: null,
      })
    ).to.be.rejectedWith('NonIncreasingVersion(2, 2)')

    await pointerContract.write.setBHP([mockProver3.address], {
      account: owner.account!,
      chain: null,
    })

    expect(await pointerContract.read.implementationAddress()).to.eq(
      getAddress(mockProver3.address),
      'prover not set'
    )
  })
})
