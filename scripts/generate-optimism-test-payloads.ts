/**
 * Generate test payloads for Optimism ChildToParentProver
 * 
 * This script generates .hex files that can be used in Solidity tests.
 * Run with: npx hardhat run scripts/generate-optimism-test-payloads.ts
 * 
 * Generates:
 * - calldata_get.hex: For getTargetStateCommitment() test
 * - calldata_verify_target.hex: For verifyTargetBlockHash() test
 * - calldata_verify_slot.hex: For verifyStorageSlot() test
 */

import { createPublicClient, http, Address, Hash, Hex, encodeAbiParameters } from 'viem'
import { optimismSepolia, sepolia } from 'viem/chains'
import { OptimismChildToParentProverHelper } from '../src/ts/optimism/ChildToParentProverHelper'
import fs from 'fs'
import path from 'path'

const OPTIMISM_SEPOLIA_RPC = process.env.OPTIMISM_SEPOLIA_RPC_URL || 'https://sepolia.optimism.io'
const SEPOLIA_RPC = process.env.ETHEREUM_RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com'

async function main() {
  console.log('🔄 Generating Optimism ChildToParentProver test payloads...\n')

  // Create clients
  const optimismClient = createPublicClient({
    chain: optimismSepolia,
    transport: http(OPTIMISM_SEPOLIA_RPC),
  })

  const sepoliaClient = createPublicClient({
    chain: sepolia,
    transport: http(SEPOLIA_RPC),
  })

  // Create helper
  const helper = new OptimismChildToParentProverHelper(optimismClient, sepoliaClient)

  // Get current block numbers
  const optimismBlockNumber = await optimismClient.getBlockNumber()
  const optimismBlock = await optimismClient.getBlock({ blockNumber: optimismBlockNumber })
  const optimismBlockHash = optimismBlock.hash

  console.log(`📍 Current Optimism Sepolia block: ${optimismBlockNumber}`)
  console.log(`📍 Optimism block hash: ${optimismBlockHash}\n`)

  const outputDir = path.join(__dirname, '../test/payloads/optimism')
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true })
  }

  // 1. Generate calldata_get.hex
  console.log('1️⃣  Generating calldata_get.hex...')
  try {
    const { input, targetBlockHash } = await helper.buildInputForGetTargetBlockHash()
    
    // Format: [input (32 bytes), targetBlockHash (32 bytes)]
    const payload = encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }],
      [input.padEnd(66, '0') as Hash, targetBlockHash]
    )
    
    fs.writeFileSync(path.join(outputDir, 'calldata_get.hex'), payload)
    console.log(`   ✅ Input: ${input}`)
    console.log(`   ✅ Target block hash: ${targetBlockHash}\n`)
  } catch (error) {
    console.error(`   ❌ Error: ${error}\n`)
  }

  // 2. Generate calldata_verify_target.hex
  console.log('2️⃣  Generating calldata_verify_target.hex...')
  try {
    const { input, targetBlockHash } = await helper.buildInputForVerifyTargetBlockHash(optimismBlockHash)
    
    // Format: [homeBlockHash (32 bytes), targetBlockHash (32 bytes), input (variable)]
    const payload = encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }, { type: 'bytes' }],
      [optimismBlockHash, targetBlockHash, input]
    )
    
    fs.writeFileSync(path.join(outputDir, 'calldata_verify_target.hex'), payload)
    console.log(`   ✅ Home block hash: ${optimismBlockHash}`)
    console.log(`   ✅ Target block hash: ${targetBlockHash}`)
    console.log(`   ✅ Input length: ${input.length / 2 - 1} bytes\n`)
  } catch (error) {
    console.error(`   ❌ Error: ${error}\n`)
  }

  // 3. Generate calldata_verify_slot.hex
  console.log('3️⃣  Generating calldata_verify_slot.hex...')
  try {
    // Use a known contract on Sepolia (WETH or similar)
    const knownAccount: Address = '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14' // WETH on Sepolia
    const knownSlot = 0n // Usually slot 0 for name or owner

    // Use a RECENT L1 block instead of the one from L1Block (which might be too old for Infura)
    const recentL1Block = await sepoliaClient.getBlock({ blockTag: 'latest' })
    const targetBlockHash = recentL1Block.hash

    const { input, slotValue } = await helper.buildInputForVerifyStorageSlot(
      targetBlockHash,
      knownAccount,
      knownSlot
    )
    
    // Format: [targetBlockHash (32 bytes), slotValue (32 bytes), input (variable)]
    const payload = encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }, { type: 'bytes' }],
      [targetBlockHash, slotValue, input]
    )
    
    fs.writeFileSync(path.join(outputDir, 'calldata_verify_slot.hex'), payload)
    console.log(`   ✅ Target block hash: ${targetBlockHash}`)
    console.log(`   ✅ Account: ${knownAccount}`)
    console.log(`   ✅ Slot: ${knownSlot}`)
    console.log(`   ✅ Slot value: ${slotValue}`)
    console.log(`   ✅ Input length: ${input.length / 2 - 1} bytes\n`)
  } catch (error) {
    console.error(`   ❌ Error: ${error}\n`)
  }

  console.log('✨ Done! Payload files generated in test/payloads/optimism/\n')
  console.log('📝 You can now use these in your Solidity tests like:')
  console.log('   bytes memory payload = _loadPayload("test/payloads/optimism/calldata_get.hex");')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

