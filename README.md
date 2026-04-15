# Crosschain Broadcaster (ERC-7888)

Ethereum reference implementation for [ERC-7888: Crosschain Broadcaster](https://eips.ethereum.org/EIPS/eip-7888). The standard defines a storage-proof based way to publish 32-byte messages on one chain and verify their existence on any other chain that shares a common ancestor.

- **Broadcast**: `Broadcaster` stores `block.timestamp` in slot `keccak(message, publisher)`, emits `MessageBroadcast`, and prevents duplicates per publisher.
- **Prove**: `Receiver` walks a user-specified route of `StateProver` contracts to recover a finalized target block hash, proves a storage slot on a remote `Broadcaster`, checks the slot is non-zero and matches the expected `(message, publisher)` slot, then returns the timestamp.
- **Upgrade safely**: `StateProverPointer` holds the latest prover implementation address and code hash in a fixed slot (`STATE_PROVER_POINTER_SLOT`), enforcing monotonic `version()` upgrades so routes stay stable while provers evolve.
- **Reusable proving code**: `StateProver` copies can be deployed on any chain; the pointer-stored code hash guarantees the copy matches the canonical implementation.

## Contracts
- `src/contracts/Broadcaster.sol`: Minimal broadcaster with deduplication and timestamp storage.
- `src/contracts/Receiver.sol`: Verifies broadcast messages from remote chains using a route of block-hash provers and a final storage proof; can cache prover copies.
- `src/contracts/StateProverPointer.sol`: Ownable pointer storing the current prover implementation address and code hash with version monotonicity checks.
- `src/contracts/libraries/ProverUtils.sol`: Shared helpers for verifying block headers and MPT proofs (state root, account data, storage slot).
- Interfaces: `IBroadcaster`, `IReceiver`, `IStateProver`, `IStateProverPointer`.

## Key concepts
- **Broadcaster**: Singleton per chain that timestamps 32-byte messages in deterministic slots and emits `MessageBroadcast`.
- **Receiver**: Trustlessly reads a remote `Broadcaster` slot by following a prover route, checking slot correctness, and returning `(broadcasterId, timestamp)`.
- **StateProver**: Chain-specific verifier that proves a target block hash from a home chain state root and verifies arbitrary storage for that block.
- **StateProverPointer**: Stable address that stores the prover implementation address and code hash in `STATE_PROVER_POINTER_SLOT`, enforcing increasing `version()`.
- **StateProverCopy**: Locally deployed prover contract whose `codehash` matches the pointer; used by `Receiver` when proving multi-hop routes.
- **Route**: Ordered addresses of prover pointers from the destination back to the origin chain; hashed cumulatively in `Receiver` to produce unique IDs.

## Two-hop proof flow (L2 → L1 → L2)
1) Publisher broadcasts on L2-A → `Broadcaster` stores timestamp at `keccak(message, publisher)`.
2) On L2-B, caller gives `Receiver.verifyBroadcastMessage`:
   - Route: `[L2-A→L1 pointer, L1→L2-B pointer]`
   - `scpInputs[0]`: proof for L2-A block hash committed to L1
   - `scpInputs[1]`: proof for that L1 block hash committed to L2-B
   - `storageProof`: proof for the `(message, publisher)` slot on L2-A at the proven block hash
3) `Receiver` uses a local `StateProverCopy` for hop 2 (code hash must match pointer), verifies each hop, checks the slot matches `keccak(message, publisher)`, and returns `(broadcasterId, timestamp)`.
4) Subscriber contracts compare `broadcasterId` against their allowlist and mark messages as consumed.

## How the protocol fits together
1) A publisher calls `Broadcaster.broadcastMessage(message)` on Chain A. The `(message, publisher)` slot now holds the timestamp.
2) To trustlessly read that message on Chain C, a caller provides `Receiver.verifyBroadcastMessage` with:
   - `route`: addresses of the `StateProverPointer` hop-by-hop path (e.g., child→L1 pointer, L1→dest pointer).
   - `scpInputs`: prover-specific inputs for each hop (built off-chain with the TS helpers).
   - `storageProof`: a storage proof for the `Broadcaster` slot on the source chain at the proven block hash.
3) `Receiver` accumulates the route to derive unique IDs, ensures the proven slot matches `keccak(message, publisher)`, and returns `(broadcasterId, timestamp)`.
4) Before verifying, callers can seed `Receiver.updateStateProverCopy` with a local prover copy whose code hash matches the pointer slot and whose `version()` increases.

## Repository layout
- `src/contracts/` – Solidity contracts and interfaces.
- `src/ts/` – Proof input builders used by the forthcoming SDK.
- `docs/` – Design notes, specs, and chain-specific proving guides.
- `scripts/`, `broadcast/`, `artifacts/` – Deployment/testing assets (Hardhat, Foundry).
- `wagmi/` – Generated ABIs for TS helpers.

## Developing
- Install deps: `yarn install` (or `npm install`)
- Build contracts, ABIs, TS: `yarn build`
- Tests: `yarn test`
- Clean: `yarn clean`

## Using the contracts (high level)
- Deploy a `Broadcaster` on each chain where messages originate.
- Deploy a `StateProverPointer` per chain pair direction; point it to the canonical `StateProver` implementation (must expose `version()` and stable code hash).
- On destination chains, deploy `Receiver` and register local prover copies via `updateStateProverCopy` once the pointer’s code hash is provably available.
- Off-chain, use the TS helpers (or your own tooling) to:
  1) Find a route (e.g., L2→L1→L2),
  2) Build `scpInputs` per hop plus the final `storageProof`,
  3) Call `Receiver.verifyBroadcastMessage` with `(message, publisher)`; use the returned `broadcasterId` to authorize the source broadcaster.

## Links
- ERC text: [eip-7888](https://eips.ethereum.org/EIPS/eip-7888)
- Discussion: https://ethereum-magicians.org/t/new-erc-cross-chain-broadcaster/22927
