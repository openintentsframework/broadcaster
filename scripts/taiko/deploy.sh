#!/usr/bin/env bash
set -e

source .env
source scripts/taiko/config.sh

if [ -f scripts/taiko/addresses.sh ]; then
    source scripts/taiko/addresses.sh
fi

check_deployed() {
    local address=$1
    local rpc=$2
    if [ -z "$address" ] || [ "$address" = "0x0000000000000000000000000000000000000000" ]; then
        return 1
    fi
    local code=$(cast code "$address" --rpc-url "$rpc" 2>/dev/null || echo "0x")
    if [ "$code" = "0x" ]; then
        return 1
    fi
    return 0
}

FORCE_DEPLOY=${1:-false}

if [ "$FORCE_DEPLOY" = "--force" ]; then
    echo "Force deployment mode enabled"
    SKIP_L1=false
    SKIP_L2=false
    SKIP_L1_PROVER=false
    SKIP_L2_PROVER=false
else
    SKIP_L1=false
    SKIP_L2=false
    SKIP_L1_PROVER=false
    SKIP_L2_PROVER=false

    if check_deployed "$L1_BROADCASTER" "$L1_RPC"; then
        echo "L1 contracts already deployed at $L1_BROADCASTER"
        SKIP_L1=true
    fi

    if check_deployed "$L2_BROADCASTER" "$L2_RPC"; then
        echo "L2 contracts already deployed at $L2_BROADCASTER"
        SKIP_L2=true
    fi

    if check_deployed "$L1_PARENT_TO_CHILD_PROVER" "$L1_RPC"; then
        echo "L1 prover already deployed at $L1_PARENT_TO_CHILD_PROVER"
        SKIP_L1_PROVER=true
    fi

    if check_deployed "$L2_CHILD_TO_PARENT_PROVER" "$L2_RPC"; then
        echo "L2 prover already deployed at $L2_CHILD_TO_PARENT_PROVER"
        SKIP_L2_PROVER=true
    fi
fi

if [ "$SKIP_L1" = false ]; then
    echo "Deploying Broadcaster/Receiver on L1..."
    L1_OUTPUT=$(forge script scripts/taiko/deploy-all.s.sol:DeployAll \
        --rpc-url "$L1_RPC" \
        --private-key "$TAIKO_DEPLOYER_PK" \
        --broadcast --json)
else
    echo "Skipping L1 deployment (already deployed)"
fi

if [ "$SKIP_L1" = false ]; then
    L1_BROADCASTER=$(echo "$L1_OUTPUT" | grep -o "Broadcaster: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
    L1_RECEIVER=$(echo "$L1_OUTPUT" | grep -o "Receiver: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
    L1_POINTER=$(echo "$L1_OUTPUT" | grep -o "BlockHashProverPointer: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
fi

if [ "$SKIP_L2" = false ]; then
    echo "Deploying Broadcaster/Receiver on L2..."
    L2_OUTPUT=$(forge script scripts/taiko/deploy-all.s.sol:DeployAll \
        --rpc-url "$L2_RPC" \
        --private-key "$TAIKO_DEPLOYER_PK" \
        --broadcast --json)
    
    L2_BROADCASTER=$(echo "$L2_OUTPUT" | grep -o "Broadcaster: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
    L2_RECEIVER=$(echo "$L2_OUTPUT" | grep -o "Receiver: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
    L2_POINTER=$(echo "$L2_OUTPUT" | grep -o "BlockHashProverPointer: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
else
    echo "Skipping L2 deployment (already deployed)"
fi

if [ "$SKIP_L1_PROVER" = false ]; then
    echo "Deploying Provers on L1..."
    L1_PROVER_OUTPUT=$(forge script scripts/taiko/provers.s.sol:DeployL1Prover \
        --rpc-url "$L1_RPC" \
        --private-key "$TAIKO_DEPLOYER_PK" \
        --broadcast --json)
    
    L1_PARENT_TO_CHILD_PROVER=$(echo "$L1_PROVER_OUTPUT" | grep -o "ParentToChildProver: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
    L1_PROVER_POINTER=$(echo "$L1_PROVER_OUTPUT" | grep -o "L1ProverPointer: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
else
    echo "Skipping L1 prover deployment (already deployed)"
fi

if [ "$SKIP_L2_PROVER" = false ]; then
    echo "Deploying Provers on L2..."
    L2_PROVER_OUTPUT=$(forge script scripts/taiko/provers-l2.s.sol:DeployL2Prover \
        --rpc-url "$L2_RPC" \
        --private-key "$TAIKO_DEPLOYER_PK" \
        --broadcast --json)
    
    L2_CHILD_TO_PARENT_PROVER=$(echo "$L2_PROVER_OUTPUT" | grep -o "ChildToParentProver: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
    L2_PROVER_POINTER=$(echo "$L2_PROVER_OUTPUT" | grep -o "L2ProverPointer: 0x[a-fA-F0-9]*" | cut -d' ' -f2)
else
    echo "Skipping L2 prover deployment (already deployed)"
fi

if [ "$SKIP_L1" = true ] && [ "$SKIP_L2" = true ] && [ "$SKIP_L1_PROVER" = true ] && [ "$SKIP_L2_PROVER" = true ]; then
    echo ""
    echo "All contracts already deployed. Use --force to redeploy."
    echo ""
    cat scripts/taiko/addresses.sh
    exit 0
fi

sleep 5

if [ "$SKIP_L1" = false ] || [ "$SKIP_L1_PROVER" = false ]; then
    echo "Verifying L1 contracts..."
    
    if [ "$SKIP_L1" = false ]; then
        forge verify-contract --rpc-url "$L1_RPC" --verifier blockscout --verifier-url "$L1_VERIFIER_URL" \
            "$L1_BROADCASTER" src/contracts/Broadcaster.sol:Broadcaster || true

        forge verify-contract --rpc-url "$L1_RPC" --verifier blockscout --verifier-url "$L1_VERIFIER_URL" \
            "$L1_RECEIVER" src/contracts/Receiver.sol:Receiver || true

        forge verify-contract --rpc-url "$L1_RPC" --verifier blockscout --verifier-url "$L1_VERIFIER_URL" \
            --constructor-args $(cast abi-encode "constructor(address)" "$TAIKO_DEPLOYER_ADDRESS") \
            "$L1_POINTER" src/contracts/BlockHashProverPointer.sol:BlockHashProverPointer || true
    fi
    
    if [ "$SKIP_L1_PROVER" = false ]; then
        forge verify-contract --rpc-url "$L1_RPC" --verifier blockscout --verifier-url "$L1_VERIFIER_URL" \
            --constructor-args $(cast abi-encode "constructor(address,uint256,uint256)" "$L1_SIGNAL_SERVICE" "$CHECKPOINTS_SLOT" "$L1_CHAIN_ID") \
            "$L1_PARENT_TO_CHILD_PROVER" src/contracts/provers/taiko/ParentToChildProver.sol:ParentToChildProver || true

        forge verify-contract --rpc-url "$L1_RPC" --verifier blockscout --verifier-url "$L1_VERIFIER_URL" \
            --constructor-args $(cast abi-encode "constructor(address)" "$TAIKO_DEPLOYER_ADDRESS") \
            "$L1_PROVER_POINTER" src/contracts/BlockHashProverPointer.sol:BlockHashProverPointer || true
    fi
fi

if [ "$SKIP_L2" = false ] || [ "$SKIP_L2_PROVER" = false ]; then
    echo "Verifying L2 contracts..."

    if [ "$SKIP_L2" = false ]; then
        forge verify-contract --rpc-url "$L2_RPC" --verifier blockscout --verifier-url "$L2_VERIFIER_URL" \
            "$L2_BROADCASTER" src/contracts/Broadcaster.sol:Broadcaster || true

        forge verify-contract --rpc-url "$L2_RPC" --verifier blockscout --verifier-url "$L2_VERIFIER_URL" \
            "$L2_RECEIVER" src/contracts/Receiver.sol:Receiver || true

        forge verify-contract --rpc-url "$L2_RPC" --verifier blockscout --verifier-url "$L2_VERIFIER_URL" \
            --constructor-args $(cast abi-encode "constructor(address)" "$TAIKO_DEPLOYER_ADDRESS") \
            "$L2_POINTER" src/contracts/BlockHashProverPointer.sol:BlockHashProverPointer || true
    fi

    if [ "$SKIP_L2_PROVER" = false ]; then
        forge verify-contract --rpc-url "$L2_RPC" --verifier blockscout --verifier-url "$L2_VERIFIER_URL" \
            --constructor-args $(cast abi-encode "constructor(address,uint256,uint256)" "$L2_SIGNAL_SERVICE" "$CHECKPOINTS_SLOT" "$L2_CHAIN_ID") \
            "$L2_CHILD_TO_PARENT_PROVER" src/contracts/provers/taiko/ChildToParentProver.sol:ChildToParentProver || true

        forge verify-contract --rpc-url "$L2_RPC" --verifier blockscout --verifier-url "$L2_VERIFIER_URL" \
            --constructor-args $(cast abi-encode "constructor(address)" "$TAIKO_DEPLOYER_ADDRESS") \
            "$L2_PROVER_POINTER" src/contracts/BlockHashProverPointer.sol:BlockHashProverPointer || true
    fi
fi

cat > scripts/taiko/addresses.sh <<EOF
export L1_BROADCASTER=$L1_BROADCASTER
export L1_RECEIVER=$L1_RECEIVER
export L1_POINTER=$L1_POINTER
export L1_PARENT_TO_CHILD_PROVER=$L1_PARENT_TO_CHILD_PROVER
export L1_PROVER_POINTER=$L1_PROVER_POINTER
export L2_BROADCASTER=$L2_BROADCASTER
export L2_RECEIVER=$L2_RECEIVER
export L2_POINTER=$L2_POINTER
export L2_CHILD_TO_PARENT_PROVER=$L2_CHILD_TO_PARENT_PROVER
export L2_PROVER_POINTER=$L2_PROVER_POINTER
EOF

echo ""
echo "=========================================="
echo "DEPLOYMENT SUMMARY"
echo "=========================================="
echo ""
echo "L1 (Taiko Parent Chain - 32382):"
echo "  Broadcaster:           $L1_BROADCASTER"
echo "  Receiver:              $L1_RECEIVER"
echo "  BlockHashProverPointer: $L1_POINTER"
echo "  ParentToChildProver:   $L1_PARENT_TO_CHILD_PROVER"
echo "  ProverPointer:         $L1_PROVER_POINTER"
echo ""
echo "L2 (Taiko Child Chain - 167001):"
echo "  Broadcaster:           $L2_BROADCASTER"
echo "  Receiver:              $L2_RECEIVER"
echo "  BlockHashProverPointer: $L2_POINTER"
echo "  ChildToParentProver:   $L2_CHILD_TO_PARENT_PROVER"
echo "  ProverPointer:         $L2_PROVER_POINTER"
echo ""
echo "Addresses saved to scripts/taiko/addresses.sh"
echo "=========================================="

