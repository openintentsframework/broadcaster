DEPLOY:
./scripts/taiko/deploy.sh

BROADCAST:
./scripts/taiko/broadcast.sh [l1|l2|both]

GENERATE PROOF FROM L2:
1. Broadcast: ./scripts/taiko/broadcast.sh l2
2. Get tx hash and run: ./scripts/taiko/get-slot.sh <tx_hash> l2
3. Run the node command output to generate test/payloads/taiko/taikoProofL2.json

GENERATE PROOF FROM L1:
1. Broadcast: ./scripts/taiko/broadcast.sh l1
2. Run: ./scripts/taiko/generate-proof-l1.sh
3. Enter the L1 tx hash when prompted

TESTING:
forge test --mt test_verifyBroadcastMessage_from_TaikoL2
forge test --mt test_verifyBroadcastMessage_from_Ethereum

VERIFY REAL MESSAGE:
./scripts/taiko/verify-message.sh

DEPLOYED CONTRACTS:
- Broadcaster (L1 & L2)
- Receiver (L1 & L2)
- BlockHashProverPointer (L1 & L2)
- ParentToChildProver (L1)
- ChildToParentProver (L2)
- Prover Pointers (L1 & L2)

