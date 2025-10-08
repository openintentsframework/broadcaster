// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Lib_SecureMerkleTrie} from "@eth-optimism/contracts/libraries/trie/Lib_SecureMerkleTrie.sol";
import {Lib_RLPReader} from "@eth-optimism/contracts/libraries/rlp/Lib_RLPReader.sol";
import {ProverUtils} from "./ProverUtils.sol";
import {IBlockHashProver} from "broadcast-erc/contracts/standard/interfaces/IBlockHashProver.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";

interface IAnchorStateRegistry {
    function isGameClaimValid(address _game) external view returns (bool);
}

interface IFaultDisputeGame {
    function rootClaim() external view returns (bytes32);
}

/// @notice OP-stack implementation of a parent to child IBlockHashProver.
/// @dev    verifyTargetBlockHash and getTargetBlockHash get block hashes from a valid fault dispute game proxy contract.
///         verifyStorageSlot is implemented to work against any OP-stack child chain with a standard Ethereum block header and state trie.
contract ParentToChildProver is IBlockHashProver {
    using Lib_RLPReader for Lib_RLPReader.RLPItem;

    struct OutputRootProof {
        bytes32 version;
        bytes32 stateRoot;
        bytes32 messagePasserStorageRoot;
        bytes32 latestBlockhash;
    }

    /// @dev The storage slot in the AnchorStateRegistry where the anchor game address is stored.
    ///      https://github.com/ethereum-optimism/optimism/blob/ef7a933ca7f3d27ac40406f87fea25e0c3ba2016/packages/contracts-bedrock/src/dispute/AnchorStateRegistry.sol#L39
    uint256 public constant ANCHOR_GAME_SLOT = 3;

    /// @notice The target chain's AnchorStateRegistry address.
    address public immutable anchorStateRegistry;

    constructor(address _anchorStateRegistry) {
        anchorStateRegistry = _anchorStateRegistry;
    }

    /// @notice Verify the latest available target block hash given a home chain block hash, a storage proof of the AnchorStateRegistry, the anchor game proxy code and a root claim preimage.
    /// @dev    1. The anchor game address is extracted from the AnchorStateRegistry storage slot.
    ///         2. The game proxy code hash is verified against the block hash.
    ///         3. The game's root claim hash is extracted from the game proxy code.
    ///         4. The root claim preimage is verified against the root claim hash.
    ///         5. The target block hash is returned from the root claim preimage.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader,
    ///                            bytes asrAccountProof,
    ///                            bytes asrStorageProof,
    ///                            bytes gameProxyAccountProof,
    ///                            bytes gameProxyCode,
    ///                            bytes rootClaimPreimage)
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
        // decode the input
        (
            bytes memory rlpBlockHeader,
            bytes memory asrAccountProof,
            bytes memory asrStorageProof,
            bytes memory gameProxyAccountProof,
            bytes memory gameProxyCode,
            OutputRootProof memory rootClaimPreimage
        ) = abi.decode(input, (bytes, bytes, bytes, bytes, bytes, OutputRootProof));

        // check the block hash
        require(homeBlockHash == keccak256(rlpBlockHeader), "Invalid home block header");
        bytes32 stateRoot = ProverUtils.extractStateRootFromBlockHeader(rlpBlockHeader);

        // grab the anchor game address
        address anchorGame = address(
            uint160(
                uint256(
                    ProverUtils.getStorageSlotFromStateRoot(
                        stateRoot, asrAccountProof, asrStorageProof, anchorStateRegistry, ANCHOR_GAME_SLOT
                    )
                )
            )
        );

        // get the anchor game's code hash from the account proof
        (bool accountExists, bytes memory accountValue) =
            ProverUtils.getAccountDataFromStateRoot(stateRoot, gameProxyAccountProof, anchorGame);
        require(accountExists, "Anchor game account does not exist");
        bytes32 codeHash = ProverUtils.extractCodeHashFromAccountData(accountValue);

        // verify the game proxy code against the code hash
        require(keccak256(gameProxyCode) == codeHash, "Invalid game proxy code");

        // extract the root claim from the game proxy code
        bytes32 rootClaim = _getRootClaimFromGameProxyCode(gameProxyCode);

        // verify the root claim preimage
        require(rootClaim == keccak256(abi.encode(rootClaimPreimage)), "Invalid root claim preimage");

        // return the target block hash from the root claim preimage
        return rootClaimPreimage.latestBlockhash;
    }

    /// @notice Return the blockhash from a valid fault dispute game's root claim. The game's claim must be considered valid by the anchor state registry.
    /// @dev    1. Check the game proxy using IAnchorStateRegistry.isGameClaimValid
    ///         2. Verify the root claim preimage against the game's root claim.
    ///         3. Return the latest block hash from the root claim preimage.
    /// @param  input ABI encoded (address gameProxy, OutputRootProof rootClaimPreimage)
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {
        // decode the input
        (address gameProxy, OutputRootProof memory rootClaimPreimage) = abi.decode(input, (address, OutputRootProof));

        // check the game proxy address
        require(IAnchorStateRegistry(anchorStateRegistry).isGameClaimValid(gameProxy), "Invalid game proxy");

        bytes32 rootClaim = IFaultDisputeGame(gameProxy).rootClaim();
        require(rootClaim == keccak256(abi.encode(rootClaimPreimage)), "Invalid root claim preimage");

        return rootClaimPreimage.latestBlockhash;
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetBlockHash The block hash of the target chain.
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        // decode the input
        bytes memory rlpBlockHeader;
        bytes memory accountProof;
        bytes memory storageProof;
        (rlpBlockHeader, account, slot, accountProof, storageProof) =
            abi.decode(input, (bytes, address, uint256, bytes, bytes));

        // verify proofs and get the value
        value = ProverUtils.getSlotFromBlockHeader(
            targetBlockHash, rlpBlockHeader, account, slot, accountProof, storageProof
        );
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }

    /// @notice Extract the root claim from the game proxy code.
    /// @dev    The game proxy is a CWIA deployed here:
    ///         https://github.com/ethereum-optimism/optimism/blob/ef7a933ca7f3d27ac40406f87fea25e0c3ba2016/packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol#L164
    ///         https://github.com/Vectorized/solady/blob/502cc1ea718e6fa73b380635ee0868b0740595f0/src/utils/LibClone.sol#L329
    /// @param  bytecode The game proxy code.
    /// @return rootClaim The root claim extracted from the game proxy code.
    function _getRootClaimFromGameProxyCode(bytes memory bytecode) internal pure returns (bytes32 rootClaim) {
        // https://github.com/ethereum-optimism/optimism/blob/ef7a933ca7f3d27ac40406f87fea25e0c3ba2016/packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol#L155-L164
        // CWIA Calldata Layout:
        // ┌──────────────┬────────────────────────────────────┐
        // │    Bytes     │            Description             │
        // ├──────────────┼────────────────────────────────────┤
        // │ [0, 20)      │ Game creator address               │
        // │ [20, 52)     │ Root claim                         │
        // │ [52, 84)     │ Parent block hash at creation time │
        // │ [84, 84 + n) │ Extra data (opaque)                │
        // └──────────────┴────────────────────────────────────┘

        // grab the root claim from the CWIA data which starts at 0x62
        return abi.decode(Bytes.slice(bytecode, 0x62 + 20, 0x62 + 52), (bytes32));
    }
}
