import { Address, Hash, Hex } from 'viem'

/**
 * IProverHelper defines the interface that IStateProver helper classes must implement.
 *
 * Implementations should avoid relying on specialized RPC capabilities such as large log queries.
 */
export interface IProverHelper {
  /**
   * Builds the bytes input argument for the IStateProver::getTargetStateCommitment function.
   * Finds the newest block hash that can be returned by getTargetStateCommitment on the prover.
   * @returns The input bytes and the resulting target block hash.
   */
  buildInputForGetTargetBlockHash(): Promise<{
    input: Hex
    targetStateCommitment: Hash
  }>

  /**
   * Build the bytes input argument for the IStateProver::verifyTargetStateCommitment function.
   * Finds the newest block hash that can be returned by verifyTargetStateCommitment on the prover given the home block hash.
   * @param homeBlockHash Home chain block hash that will be passed to the prover and proven against
   */
  buildInputForVerifyTargetBlockHash(
    homeBlockHash: Hash
  ): Promise<{ input: Hex; targetStateCommitment: Hash }>

  /**
   * Build the bytes input argument for the IStateProver::verifyStorageSlot function.
   * @param targetStateCommitment Target chain block hash that will be passed to the prover and proven against
   * @param account The account to prove the storage slot for
   * @param slot The storage slot to prove
   * @returns The input bytes and the slot value
   */
  buildInputForVerifyStorageSlot(
    targetStateCommitment: Hash,
    account: Address,
    slot: bigint
  ): Promise<{ input: Hex; slotValue: Hash }>

  buildInputForGetTargetBlockHashByBlockNumber(blockNumber: bigint): Promise<{
    input: Hex
    targetStateCommitment: Hash
  }>
}
