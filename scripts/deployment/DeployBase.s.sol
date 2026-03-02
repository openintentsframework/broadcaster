// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LowLevelCall} from "@openzeppelin/contracts/utils/LowLevelCall.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract DeployBase is Script {
    error InvalidChainId(uint256 chainId);
    error DeploymentFailed();
    error InvalidPusherAddress();
    error InvalidBufferAddress();

    // See https://github.com/Arachnid/deterministic-deployment-proxy
    // According to this research: https://ethereum-magicians.org/t/eip-7997-deterministic-factory-predeploy/24998/15
    // the Arachnid deployment proxy is the widest proxy available and its adoption suggests that a
    // more effect approach to support deterministic addresses is to enshrine it as a predeployed contract
    // through proposals like [RIP-7740](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7740.md).
    address public constant DEPLOYMENT_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function _chainName(uint256 chainId) internal view returns (string memory) {
        if (chainId == 11155111) return "ethereum-sepolia";
        if (chainId == 421614) return "arbitrum-sepolia";
        if (chainId == 59141) return "linea-sepolia";
        if (chainId == 534351) return "scroll-sepolia";
        if (chainId == 11155420) return "optimism-sepolia";
        if (chainId == 300) return "zksync-sepolia";
        revert InvalidChainId(chainId);
    }

    function _deploymentsDir() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments");
    }

    function _path() internal view returns (string memory) {
        return string.concat(_deploymentsDir(), "/", _chainName(block.chainid), ".json");
    }

    function _jsonString(string memory s) internal pure returns (string memory) {
        return string.concat('"', s, '"');
    }

    function _ensureDeploymentsDir() internal {
        vm.createDir(_deploymentsDir(), true);
    }

    function _ensureFile(string memory path) internal {
        _ensureDeploymentsDir();
        if (!vm.exists(path)) {
            // start as an empty object; we’ll add objects below
            vm.writeFile(path, "{}");
        } else {
            string memory content = vm.readFile(path);
            if (bytes(content).length == 0) vm.writeFile(path, "{}");
        }
    }

    /// Ensures that `jsonPath` exists and is an object. If missing, creates `{}` there.
    function _ensureObjectAt(string memory path, string memory jsonPath) internal {
        string memory content = vm.readFile(path);
        try vm.parseJson(content, jsonPath) returns (
            bytes memory
        ) {
        // exists (and is parseable), do nothing
        }
        catch {
            vm.writeJson("{}", path, jsonPath);
        }
    }

    function _ensureObjectAtPtr(string memory path, string memory ptr) internal {
        // Ensure an object exists at JSON Pointer `ptr` (e.g. "/provers/arbitrum-sepolia")
        string memory content = vm.readFile(path);
        try vm.parseJson(content, ptr) returns (
            bytes memory
        ) {
        // exists
        }
        catch {
            vm.writeJson("{}", path, ptr);
        }
    }

    function _ensureRootScaffold(string memory path) internal {
        _ensureFile(path);
        _ensureObjectAt(path, ".contracts");
        _ensureObjectAt(path, ".provers");
        _ensureObjectAt(path, ".copies");
    }

    function _getPusherAddress(string memory parentChain, string memory childChain) internal returns (address) {
        string memory path = string.concat(_deploymentsDir(), "/", parentChain, ".json");
        string memory json = vm.readFile(path);
        if (!vm.keyExistsJson(json, string.concat(".pushers.", childChain))) {
            revert InvalidPusherAddress();
        }
        return vm.parseJsonAddress(json, string.concat(".pushers.", childChain));
    }

    function _getBufferAddress(string memory childChain) internal returns (address) {
        string memory path = string.concat(_deploymentsDir(), "/", childChain, ".json");
        string memory json = vm.readFile(path);
        if (!vm.keyExistsJson(json, string.concat(".contracts.", "buffer"))) {
            revert InvalidBufferAddress();
        }
        return vm.parseJsonAddress(json, string.concat(".contracts.", "buffer"));
    }

    // -------------------------
    // Writes
    // -------------------------

    function _isContractDeployed(string memory name) internal returns (bool) {
        string memory path = _path();
        _ensureRootScaffold(path);
        string memory json = vm.readFile(path);
        return vm.keyExistsJson(json, string.concat(".contracts.", name));
    }

    function _isProverDeployed(string memory chainKey) internal returns (bool) {
        string memory path = _path();
        _ensureRootScaffold(path);
        string memory json = vm.readFile(path);
        return vm.keyExistsJson(json, string.concat(".provers.", chainKey));
    }

    function _isCopyDeployed(string memory homeChain, string memory targetChain) internal returns (bool) {
        string memory path = _path();
        _ensureRootScaffold(path);
        string memory json = vm.readFile(path);
        return vm.keyExistsJson(json, string.concat(".copies.", homeChain, ".", targetChain));
    }

    function _isPusherDeployed(string memory chainKey) internal returns (bool) {
        string memory path = _path();
        _ensureRootScaffold(path);
        string memory json = vm.readFile(path);
        return vm.keyExistsJson(json, string.concat(".pushers.", chainKey));
    }

    function _isBufferDeployed(string memory chainKey) internal returns (bool) {
        string memory path = _path();
        _ensureRootScaffold(path);
        string memory json = vm.readFile(path);
        return vm.keyExistsJson(json, string.concat(".buffers.", chainKey));
    }

    function _writeContract(string memory name, address addr) internal {
        string memory path = _path();
        _ensureRootScaffold(path);

        vm.writeJson(_jsonString(vm.toString(addr)), path, string.concat(".contracts.", name));
    }

    /// Adds/updates `.provers["chainKey"].pointer` and `.provers["chainKey"].prover`
    function _writeProver(string memory chainKey, address pointer, address prover) internal {
        string memory path = _path();
        _ensureRootScaffold(path);

        // Ensure `.provers.<chainKey>` exists as an object
        string memory objPath = string.concat(".provers.", chainKey);
        _ensureObjectAt(path, objPath);

        // Write the pointer and prover addresses
        vm.writeJson(_jsonString(vm.toString(pointer)), path, string.concat(objPath, ".pointer"));
        vm.writeJson(_jsonString(vm.toString(prover)), path, string.concat(objPath, ".prover"));
    }

    /// Adds/updates `.pushers["chainKey"]`
    function _writePusher(string memory chainKey, address pusher) internal {
        string memory path = _path();
        _ensureRootScaffold(path);

        // Ensure `.pushers.<chainKey>` exists as an object
        string memory objPath = string.concat(".pushers.", chainKey);
        _ensureObjectAt(path, objPath);

        // Write the pusher address
        vm.writeJson(_jsonString(vm.toString(pusher)), path, objPath);
    }

    /// Adds/updates `.copies["src"]["dst"] = "0x..."`
    function _writeCopy(string memory homeChain, string memory targetChain, address copyAddr) internal {
        string memory path = _path();
        _ensureRootScaffold(path);

        // Ensure `.copies.<homeChain>` exists as an object
        string memory homeObjPath = string.concat(".copies.", homeChain);
        _ensureObjectAt(path, homeObjPath);

        // Set `.copies.<homeChain>.<targetChain> = "0x..."`
        string memory leafPath = string.concat(homeObjPath, ".", targetChain);
        vm.writeJson(_jsonString(vm.toString(copyAddr)), path, leafPath);
    }

    function _deploy(bytes memory creationCode, bytes32 salt) internal returns (address) {
        address predictedAddress = Create2.computeAddress(salt, keccak256(creationCode), DEPLOYMENT_PROXY);

        bool success = LowLevelCall.callNoReturn(DEPLOYMENT_PROXY, abi.encodePacked(salt, creationCode));

        return predictedAddress;
    }
}
