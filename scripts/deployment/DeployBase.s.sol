// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployBase is Script {
    error InvalidChainId(uint256 chainId);

    function _chainName(uint256 chainId) internal view returns (string memory) {
        if (chainId == 11155111) return "ethereum-sepolia";
        if (chainId == 421614) return "arbitrum-sepolia";
        if (chainId == 59141) return "linea-sepolia";
        if (chainId == 534351) return "scroll-sepolia";
        if (chainId == 11155420) return "optimism-sepolia";
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
        try vm.parseJson(content, jsonPath) returns (bytes memory) {
            // exists (and is parseable), do nothing
        } catch {
            vm.writeJson("{}", path, jsonPath);
        }
    }

    function _ensureObjectAtPtr(string memory path, string memory ptr) internal {
        // Ensure an object exists at JSON Pointer `ptr` (e.g. "/provers/arbitrum-sepolia")
        string memory content = vm.readFile(path);
        try vm.parseJson(content, ptr) returns (bytes memory) {
            // exists
        } catch {
            vm.writeJson("{}", path, ptr);
        }
    }

    function _ensureRootScaffold(string memory path) internal {
        _ensureFile(path);
        _ensureObjectAt(path, ".contracts");
        _ensureObjectAt(path, ".provers");
        _ensureObjectAt(path, ".copies");
    }

    // -------------------------
    // Writes
    // -------------------------

    function _writeContract(string memory name, address addr) internal {
        string memory path = _path();
        _ensureRootScaffold(path);

        vm.writeJson(
            _jsonString(vm.toString(addr)),
            path,
            string.concat(".contracts.", name)
        );
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
        vm.writeJson(_jsonString(vm.toString(prover)),  path, string.concat(objPath, ".prover"));
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


}
