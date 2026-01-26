# ERC-7888 Tutorial: Cross-Chain Message Broadcasting

This tutorial walks through implementing cross-chain messaging using ERC-7888. We'll cover broadcasting messages, verifying them on remote chains, and building applications on top of the protocol.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Broadcasting Messages](#broadcasting-messages)
4. [Verifying Messages](#verifying-messages)
5. [Setting Up StateProverCopies](#setting-up-stateprovercopies)
6. [Building a Cross-Chain Application](#building-a-cross-chain-application)
7. [Generating Proofs with TypeScript](#generating-proofs-with-typescript)

---

## Prerequisites

**Required:**
- Node.js 18+
- Foundry toolkit (forge, cast)
- Access to RPC endpoints for source and destination chains

**Install dependencies:**
```bash
yarn install
forge install
```

**Environment setup:**
```bash
cp .env.example .env
# Configure RPC URLs for the chains you're working with
```

---

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        Source Chain (L2-A)                       │
│  ┌─────────────┐        ┌──────────────────────────┐            │
│  │  Publisher  │───────▶│      Broadcaster         │            │
│  └─────────────┘        │  stores: timestamp @ slot │            │
│                         └──────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                                    │
                            State Commitment
                              (block hash)
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Parent Chain (Ethereum)                      │
│           ┌──────────────────────────────────┐                  │
│           │  Rollup Contract                  │                  │
│           │  (stores L2 state commitments)    │                  │
│           └──────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
                                    │
                            State Commitment
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Destination Chain (L2-B)                    │
│  ┌──────────────────────────────┐      ┌─────────────┐          │
│  │         Receiver              │◀─────│  Subscriber │          │
│  │  - StateProverCopies         │      └─────────────┘          │
│  │  - verifyBroadcastMessage()  │                               │
│  └──────────────────────────────┘                               │
└─────────────────────────────────────────────────────────────────┘
```

### Message Flow

1. **Publisher** broadcasts a 32-byte message on Source Chain
2. **Broadcaster** stores `block.timestamp` at slot `keccak256(message, publisher)`
3. Source chain's state is committed to Parent Chain
4. **Subscriber** on Destination Chain calls **Receiver** with:
   - Route of StateProverPointers
   - Proofs for each hop
   - Storage proof for the message slot
5. **Receiver** verifies the proof chain and returns `(broadcasterId, timestamp)`

---

## Broadcasting Messages

### Step 1: Deploy or Locate the Broadcaster

The Broadcaster is a singleton per chain. If not deployed, deploy it:

```solidity
// Deploy.s.sol
import {Broadcaster} from "../src/contracts/Broadcaster.sol";

contract DeployBroadcaster is Script {
    function run() external {
        vm.startBroadcast();
        Broadcaster broadcaster = new Broadcaster();
        vm.stopBroadcast();
        
        console.log("Broadcaster deployed at:", address(broadcaster));
    }
}
```

```bash
forge script scripts/DeployBroadcaster.s.sol --rpc-url $SOURCE_RPC --broadcast
```

### Step 2: Broadcast a Message

```solidity
// Your publisher contract
import {IBroadcaster} from "src/contracts/interfaces/IBroadcaster.sol";

contract MyPublisher {
    IBroadcaster public broadcaster;
    uint256 public nonce;
    
    event MessagePublished(bytes32 indexed message, uint256 nonce);
    
    constructor(IBroadcaster _broadcaster) {
        broadcaster = _broadcaster;
    }
    
    function publish(bytes memory data) external {
        // Create unique message with nonce
        bytes32 message = keccak256(abi.encode(data, nonce++));
        
        // Broadcast
        broadcaster.broadcastMessage(message);
        
        emit MessagePublished(message, nonce - 1);
    }
}
```

**Direct broadcast via cast:**
```bash
# Encode a message (example: "hello world" padded to 32 bytes)
MESSAGE=$(cast keccak "hello world")

cast send $BROADCASTER_ADDRESS "broadcastMessage(bytes32)" $MESSAGE \
    --rpc-url $SOURCE_RPC \
    --private-key $PRIVATE_KEY
```

### Step 3: Calculate the Storage Slot

The message is stored at a deterministic slot:

```solidity
bytes32 slot = keccak256(abi.encode(message, publisher));
```

```bash
# Calculate slot off-chain
PUBLISHER="0xYourPublisherAddress"
cast keccak $(cast abi-encode "encode(bytes32,address)" $MESSAGE $PUBLISHER)
```

---

## Verifying Messages

### Step 1: Determine the Route

A route consists of StateProverPointer addresses from destination to source:

```
Destination Chain → Parent Chain → Source Chain
       route[0]         route[1]
```

**Example: Arbitrum → Ethereum → Optimism**
```solidity
address[] memory route = new address[](2);
route[0] = 0x...; // Arbitrum ChildToParent StateProverPointer (on Arbitrum)
route[1] = 0x...; // Ethereum ParentToChild StateProverPointer for Optimism (on Ethereum)
```

### Step 2: Build Proof Inputs

For each hop in the route, you need prover-specific inputs. Use the TypeScript helpers:

```typescript
import { 
  ChildToParentProverHelper,
  ParentToChildProverHelper 
} from './src/ts';
import { createPublicClient, http } from 'viem';
import { arbitrum, mainnet } from 'viem/chains';

// Setup clients
const arbitrumClient = createPublicClient({
  chain: arbitrum,
  transport: http(process.env.ARBITRUM_RPC_URL)
});

const mainnetClient = createPublicClient({
  chain: mainnet,
  transport: http(process.env.ETHEREUM_RPC_URL)
});

// Build proof for first hop (Arbitrum → Ethereum)
const arbHelper = new ChildToParentProverHelper(
  arbitrumClient,
  mainnetClient
);

const { input: scpInput0, targetBlockHash: ethBlockHash } = 
  await arbHelper.buildInputForGetTargetBlockHash();
```

### Step 3: Call verifyBroadcastMessage

```solidity
import {IReceiver} from "src/contracts/interfaces/IReceiver.sol";

contract MySubscriber {
    IReceiver public receiver;
    bytes32 public trustedBroadcasterId;
    
    mapping(bytes32 => bool) public processedMessages;
    
    constructor(IReceiver _receiver, bytes32 _trustedBroadcasterId) {
        receiver = _receiver;
        trustedBroadcasterId = _trustedBroadcasterId;
    }
    
    function processMessage(
        IReceiver.RemoteReadArgs calldata readArgs,
        bytes32 message,
        address publisher,
        bytes calldata applicationData
    ) external {
        // Verify the message was broadcast
        (bytes32 broadcasterId, uint256 timestamp) = 
            receiver.verifyBroadcastMessage(readArgs, message, publisher);
        
        // Verify it's from the trusted broadcaster
        require(broadcasterId == trustedBroadcasterId, "Untrusted broadcaster");
        
        // Prevent replay
        require(!processedMessages[message], "Already processed");
        processedMessages[message] = true;
        
        // Process the application data
        _handleMessage(message, timestamp, applicationData);
    }
    
    function _handleMessage(
        bytes32 message,
        uint256 timestamp,
        bytes calldata data
    ) internal {
        // Application-specific logic
    }
}
```

---

## Setting Up StateProverCopies

Before verifying messages through multi-hop routes, you must register StateProverCopies on the destination chain.

### Step 1: Deploy the StateProverCopy

Deploy an exact copy of the StateProver on the destination chain:

```bash
# Get the bytecode from the home chain
BYTECODE=$(cast code $STATE_PROVER_ADDRESS --rpc-url $HOME_CHAIN_RPC)

# Deploy on destination chain
cast send --create $BYTECODE \
    --rpc-url $DEST_CHAIN_RPC \
    --private-key $PRIVATE_KEY
```

### Step 2: Generate Pointer Proof

You need a proof that reads the StateProverPointer's code hash from `STATE_PROVER_POINTER_SLOT`:

```typescript
import { keccak256, encodeAbiParameters } from 'viem';

// STATE_PROVER_POINTER_SLOT
const SLOT = BigInt(keccak256(encodeAbiParameters(
  [{ type: 'string' }],
  ['eip7888.pointer.slot']
))) - 1n;

// Build proof for the pointer's storage
const { input: pointerProof } = await helper.buildInputForVerifyStorageSlot(
  blockHash,
  POINTER_ADDRESS,
  SLOT
);
```

### Step 3: Register the Copy

```solidity
// Route to the StateProverPointer's home chain
address[] memory route = new address[](1);
route[0] = localPointerAddress; // Pointer that can prove the remote chain

bytes[] memory scpInputs = new bytes[](1);
scpInputs[0] = /* proof input for the hop */;

bytes memory pointerStorageProof = /* storage proof for SLOT */;

IReceiver.RemoteReadArgs memory readArgs = IReceiver.RemoteReadArgs({
    route: route,
    scpInputs: scpInputs,
    proof: pointerStorageProof
});

receiver.updateStateProverCopy(readArgs, IStateProver(copyAddress));
```

---

## Building a Cross-Chain Application

### Example: One-Way Token Bridge

This example demonstrates a burn-and-mint token bridge using ERC-7888.

**Burn Side (Source Chain):**

```solidity
// Burner.sol
import {IBroadcaster} from "src/contracts/interfaces/IBroadcaster.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct BurnMessage {
    address recipient;
    uint256 amount;
    uint256 nonce;
}

contract Burner {
    IERC20 public token;
    IBroadcaster public broadcaster;
    uint256 public burnCount;
    
    event Burned(bytes32 indexed message, BurnMessage data);
    
    constructor(IERC20 _token, IBroadcaster _broadcaster) {
        token = _token;
        broadcaster = _broadcaster;
    }
    
    function burn(address recipient, uint256 amount) external {
        // Transfer and burn tokens
        token.transferFrom(msg.sender, address(this), amount);
        // Assume token has burn function, or send to dead address
        
        // Create unique message
        BurnMessage memory data = BurnMessage({
            recipient: recipient,
            amount: amount,
            nonce: burnCount++
        });
        bytes32 message = keccak256(abi.encode(data));
        
        // Broadcast
        broadcaster.broadcastMessage(message);
        
        emit Burned(message, data);
    }
}
```

**Mint Side (Destination Chain):**

```solidity
// Minter.sol
import {IReceiver} from "src/contracts/interfaces/IReceiver.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";

contract Minter {
    IReceiver public receiver;
    IERC20Mintable public token;
    address public trustedBurner;
    bytes32 public trustedBroadcasterId;
    
    mapping(bytes32 => bool) public claimed;
    
    constructor(
        IReceiver _receiver,
        IERC20Mintable _token,
        address _trustedBurner,
        bytes32 _trustedBroadcasterId
    ) {
        receiver = _receiver;
        token = _token;
        trustedBurner = _trustedBurner;
        trustedBroadcasterId = _trustedBroadcasterId;
    }
    
    function mint(
        IReceiver.RemoteReadArgs calldata readArgs,
        BurnMessage calldata burnData
    ) external {
        bytes32 message = keccak256(abi.encode(burnData));
        
        require(!claimed[message], "Already claimed");
        
        (bytes32 broadcasterId,) = receiver.verifyBroadcastMessage(
            readArgs,
            message,
            trustedBurner
        );
        
        require(broadcasterId == trustedBroadcasterId, "Wrong broadcaster");
        
        claimed[message] = true;
        
        token.mint(burnData.recipient, burnData.amount);
    }
}
```

---

## Generating Proofs with TypeScript

### Complete Proof Generation Example

```typescript
import {
  ChildToParentProverHelper,
  ParentToChildProverHelper,
} from './src/ts';
import { createPublicClient, http, keccak256, encodeAbiParameters } from 'viem';
import { arbitrum, mainnet, optimism } from 'viem/chains';

async function generateProofs(
  message: `0x${string}`,
  publisher: `0x${string}`,
  broadcasterAddress: `0x${string}`
) {
  // Setup clients
  const arbitrumClient = createPublicClient({
    chain: arbitrum,
    transport: http(process.env.ARBITRUM_RPC_URL)
  });
  
  const mainnetClient = createPublicClient({
    chain: mainnet,
    transport: http(process.env.ETHEREUM_RPC_URL)
  });
  
  const optimismClient = createPublicClient({
    chain: optimism,
    transport: http(process.env.OPTIMISM_RPC_URL)
  });

  // Route: Optimism → Ethereum → Arbitrum
  // Step 1: Get Ethereum block hash from Optimism
  const opToEthHelper = new ChildToParentProverHelper(
    optimismClient,  // home
    mainnetClient    // target
  );
  
  const { input: scpInput0, targetBlockHash: ethBlockHash } = 
    await opToEthHelper.buildInputForGetTargetBlockHash();

  // Step 2: Get Arbitrum block hash from Ethereum
  const ethToArbHelper = new ParentToChildProverHelper(
    PROVER_ADDRESS,
    mainnetClient,   // home
    arbitrumClient   // target
  );
  
  const { input: scpInput1, targetBlockHash: arbBlockHash } = 
    await ethToArbHelper.buildInputForVerifyTargetBlockHash(ethBlockHash);

  // Step 3: Generate storage proof for the broadcaster slot
  const messageSlot = BigInt(keccak256(encodeAbiParameters(
    [{ type: 'bytes32' }, { type: 'address' }],
    [message, publisher]
  )));
  
  const { input: storageProof, slotValue } = 
    await ethToArbHelper.buildInputForVerifyStorageSlot(
      arbBlockHash,
      broadcasterAddress,
      messageSlot
    );

  return {
    route: [OP_TO_ETH_POINTER, ETH_TO_ARB_POINTER],
    scpInputs: [scpInput0, scpInput1],
    proof: storageProof,
    timestamp: slotValue
  };
}
```

### Using the Generated Proof

```typescript
import { encodeFunctionData } from 'viem';
import { receiverAbi } from './wagmi/abi';

const { route, scpInputs, proof } = await generateProofs(message, publisher, broadcaster);

const calldata = encodeFunctionData({
  abi: receiverAbi,
  functionName: 'verifyBroadcastMessage',
  args: [
    { route, scpInputs, proof },
    message,
    publisher
  ]
});

// Send transaction or simulate
const result = await client.simulateContract({
  address: RECEIVER_ADDRESS,
  abi: receiverAbi,
  functionName: 'verifyBroadcastMessage',
  args: [{ route, scpInputs, proof }, message, publisher]
});

console.log('Broadcaster ID:', result.result[0]);
console.log('Timestamp:', result.result[1]);
```

---

## Best Practices

### 1. Message Design

- Include nonces for uniqueness
- Use structured data that can be reconstructed from events
- Keep messages to 32 bytes (hash larger payloads)

### 2. Replay Protection

- Always track processed messages in subscriber contracts
- Use the `(message, publisher)` pair as the unique key

### 3. Broadcaster ID Verification

- Store trusted `broadcasterId` values at deployment
- The `broadcasterId` is deterministic based on the route and broadcaster address

### 4. Proof Freshness

- Some chains (e.g., OP Stack) have short-lived state commitments
- Generate proofs just-in-time when possible
- Implement retry logic for stale proof failures

### 5. Gas Optimization

- Cache proof results when verifying multiple messages
- Use batch verification patterns for high-throughput applications

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `MessageNotFound` | Slot value is zero | Message not yet broadcast or wrong slot |
| `WrongMessageSlot` | Slot doesn't match expected | Check message/publisher encoding |
| `ProverCopyNotFound` | Missing StateProverCopy | Register copy via `updateStateProverCopy` |
| `DifferentCodeHash` | Copy bytecode mismatch | Deploy exact copy from home chain |
| `NewerProverVersion` | Trying to downgrade | Use a higher version prover |

---

## Links

- [ERC-7888 Specification](ERC7888.md)
- [StateProvers Reference](PROVERS.md)
- [EIP-7888 on ethereum.org](https://eips.ethereum.org/EIPS/eip-7888)
