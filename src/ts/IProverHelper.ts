import { Address, Hash, Hex } from 'viem'

/**
 * IProverHelper defines the interface that IBlockHashProver helper classes must implement.
 *
 * Implementations should avoid relying on specialized RPC capabilities such as large log queries.
 */
export interface IProverHelper {
  /**
   * Builds the bytes input argument for the IBlockHashProver::getTargetBlockHash function.
   * Finds the newest block hash that can be returned by getTargetBlockHash on the prover.
   * @returns The input bytes and the resulting target block hash.
   */
  buildInputForGetTargetBlockHash(): Promise<{
    input: Hex
    targetBlockHash: Hash
  }>

  /**
   * Build the bytes input argument for the IBlockHashProver::verifyTargetBlockHash function.
   * Finds the newest block hash that can be returned by verifyTargetBlockHash on the prover given the home block hash.
   * @param homeBlockHash Home chain block hash that will be passed to the prover and proven against
   */
  buildInputForVerifyTargetBlockHash(
    homeBlockHash: Hash
  ): Promise<{ input: Hex; targetBlockHash: Hash }>

  /**
   * Build the bytes input argument for the IBlockHashProver::verifyStorageSlot function.
   * @param targetBlockHash Target chain block hash that will be passed to the prover and proven against
   * @param account The account to prove the storage slot for
   * @param slot The storage slot to prove
   * @returns The input bytes and the slot value
   */
  buildInputForVerifyStorageSlot(
    targetBlockHash: Hash,
    account: Address,
    slot: bigint
  ): Promise<{ input: Hex; slotValue: Hash }>

  buildInputForGetTargetBlockHashByBlockNumber(blockNumber: bigint): Promise<{
    input: Hex
    targetBlockHash: Hash
  }>
}
