# Block Hash Pusher

A system for pushing parent chain block hashes to child chains, enabling L2 contracts to access historical L1 block hashes for verification purposes.

## Architecture Overview

The block hash pusher system consists of two main components:

1. **Pusher**: Deployed on the parent chain (L1), retrieves recent block hashes and sends them to the child chain via chain-specific cross-chain messaging.
2. **Buffer**: Deployed on the child chain (L2), receives and stores block hashes in a sparse circular buffer for efficient lookup.

## Base Contracts

### BlockHashArrayBuilder

`BlockHashArrayBuilder` is an abstract contract that provides the core functionality for building arrays of recent block hashes. It leverages [EIP-2935](https://eips.ethereum.org/EIPS/eip-2935) to access historical block hashes beyond the standard 256-block limit.

**Key Features:**
- Retrieves block hashes using OpenZeppelin's `Blockhash` utility, which handles EIP-2935 history storage window limitations
- Supports batch sizes up to `MAX_BATCH_SIZE` (8,191 blocks), matching the EIP-2935 history storage window
- Builds arrays of block hashes starting from a specified `firstBlockNumber` for a given `batchSize`

**Important:** This contract assumes deployment on a chain that supports EIP-2935. For chains without EIP-2935 support, the batch size must be limited to 256 blocks.

**Core Function:**
- `_buildBlockHashArray(uint256 firstBlockNumber, uint256 batchSize)`: Internal function that retrieves and returns an array of block hashes starting from `firstBlockNumber` for `batchSize` consecutive blocks. The function validates that `firstBlockNumber + batchSize <= block.number`.

Concrete implementations must override `pushHashes` to implement chain-specific cross-chain messaging mechanisms.

### BaseBuffer

`BaseBuffer` implements a sparse circular buffer mechanism for storing parent chain block hashes efficiently.

**Buffer Design:**
- **Size**: 393,168 slots (48 × 8,191), providing approximately 54 days of history for Ethereum's 12-second block time
- **Storage**: Uses modulo-based indexing (`blockNumber % bufferSize`) to map block numbers to buffer positions
- **Sparse**: Block numbers don't need to be contiguous; the buffer stores only the hashes that are pushed
- **Eviction**: When a new block hash maps to the same buffer index as an existing one, the old hash is automatically evicted if the new block number is greater than the existing one

**Storage Mechanism:**
1. Block hashes are stored in a fixed-size array of structs (`BufferSlot[_BUFFER_SIZE]`), where each slot contains both a `blockNumber` and `blockHash`
2. When storing a hash at index `i`, the buffer checks if `blockNumber > bufferSlot[i].blockNumber`
3. If the condition is true, the slot is updated with the new block number and hash
4. If the condition is false (i.e., the new block number is less than or equal to the existing one), the operation is skipped (noop)
5. This ensures the buffer maintains a sliding window of the most recent block hashes and prevents overwriting newer blocks with older ones

**Core Functions:**
- `parentChainBlockHash(uint256 parentChainBlockNumber)`: Retrieves a stored block hash, reverting if not found
- `_receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes)`: Internal function that stores block hashes in the buffer
- `newestBlockNumber()`: Returns the highest block number that has been pushed

Concrete implementations must override `receiveHashes` to add chain-specific access control (e.g., verifying the sender is an authorized pusher contract).

## Chain Implementations

### ZkSync Era

**ZkSyncPusher** (`zksync/ZkSyncPusher.sol`):
- Deployed on Ethereum L1
- Uses ZkSync's Mailbox contract (`requestL2Transaction`) to send L1→L2 messages
- Requires L2 transaction parameters encoded as `L2Transaction` struct: gas limit, gas per pubdata byte limit, and refund recipient
- The `l2GasPerPubdataByteLimit` must match ZkSync's `REQUIRED_L2_GAS_PRICE_PER_PUBDATA` constant (currently 800)
- The `pushHashes` function signature is: `pushHashes(address buffer, uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)`

**ZkSyncBuffer** (`zksync/ZkSyncBuffer.sol`):
- Deployed on ZkSync Era L2
- Uses address aliasing for access control: only accepts messages from the aliased L1 pusher address
- The pusher address is set in the constructor during deployment
- Uses `AddressAliasHelper.applyL1ToL2Alias()` from Arbitrum's nitro-contracts to verify the sender matches the expected aliased pusher address (ZkSync uses the same address aliasing mechanism as Arbitrum)
- Provides `pusher()` to get the L1 pusher address and `aliasedPusher()` to get the aliased L2 address

### Scroll

**ScrollPusher** (`scroll/ScrollPusher.sol`):
- Deployed on Ethereum L1
- Uses Scroll's L1ScrollMessenger contract (`sendMessage`) to send L1→L2 messages
- Requires L2 transaction parameters: gas limit and refund address (optional, defaults to `msg.sender` if not provided)
- The pusher must be configured with the correct L1ScrollMessenger address
- The `pushHashes` function signature is: `pushHashes(address buffer, uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)`

**ScrollBuffer** (`scroll/ScrollBuffer.sol`):
- Deployed on Scroll L2
- Uses Scroll's cross-domain messaging for access control: only accepts messages relayed by the L2ScrollMessenger contract
- Verifies that `msg.sender` is the L2ScrollMessenger and that `xDomainMessageSender()` matches the pusher address
- The pusher address is set in the constructor during deployment
- Requires the L2ScrollMessenger address to be set during construction

### Linea

**LineaPusher** (`linea/LineaPusher.sol`):
- Deployed on Ethereum L1
- Uses Linea's Rollup contract (`sendMessage`) to send L1→L2 messages
- Requires L2 transaction parameters: fee (paid to the postman for claiming the message on L2)
- The pusher must be configured with the correct Linea Rollup address
- The `msg.value` sent must be at least equal to the fee specified in the transaction data
- The `pushHashes` function signature is: `pushHashes(address buffer, uint256 firstBlockNumber, uint256 batchSize, bytes calldata l2TransactionData)`

**LineaBuffer** (`linea/LineaBuffer.sol`):
- Deployed on Linea L2
- Uses Linea's cross-chain messaging for access control: only accepts messages relayed by the L2MessageService contract
- Verifies that `msg.sender` is the L2MessageService and that `sender()` matches the pusher address
- The pusher address is set in the constructor during deployment
- Requires the L2MessageService address to be set during construction
- Messages must be claimed on L2 by a postman (Linea runs a postman service) or by users for more expensive messages

## Usage Flow

1. **Initialization**: Deploy the buffer on L2, passing the pusher address as a constructor parameter
2. **Pushing Hashes**: Call `pushHashes` on the pusher contract with:
   - `buffer`: The address of the buffer contract on L2
   - `firstBlockNumber`: The block number of the first block hash to push
   - `batchSize`: Number of consecutive block hashes to push (1 to `MAX_BATCH_SIZE`)
   - `l2TransactionData`: Chain-specific transaction data encoded as bytes (e.g., ABI-encoded `L2Transaction` struct for ZkSync)
3. **Cross-Chain Message**: The pusher sends a cross-chain message containing the block hashes
4. **Storage**: The buffer receives the message, verifies access control, and stores the hashes
5. **Lookup**: Contracts on L2 can query `parentChainBlockHash(blockNumber)` to retrieve stored hashes