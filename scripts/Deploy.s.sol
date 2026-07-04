// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

// Minimal interfaces to avoid pulling in full contract bytecode
interface IModuleRegistry {
    function registerModule(bytes32 moduleName, address moduleAddress) external;
}

contract DeployScript is Script {
    bytes32 constant MODULE_YIELD = keccak256("MODULE_YIELD");
    bytes32 constant MODULE_STREAMING = keccak256("MODULE_STREAMING");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("TREASURY_ADMIN");
        uint256 threshold = vm.envUint("SIGNER_THRESHOLD");
        uint256 minDelay = vm.envUint("MIN_DELAY");

        string memory signersStr = vm.envString("SIGNERS");
        address[] memory signers = _parseSigners(signersStr);

        console.log("=== Company Treasury Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Admin:", admin);
        console.log("Threshold: %d/%d", threshold, signers.length);
        for (uint256 i = 0; i < signers.length; i++) {
            console.log("  Signer[%d]: %s", i, signers[i]);
        }

        // Read bytecode from compiled artifacts
        string memory treasuryCoreInitCode = _readBytecode("TreasuryCore");
        string memory streamingManagerInitCode = _readBytecode("StreamingManager");
        string memory yieldManagerInitCode = _readBytecode("YieldManager");
        string memory erc1967ProxyCode = _readBytecode("ERC1967Proxy");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy TreasuryCore implementation
        address treasuryImpl = _deployCode(treasuryCoreInitCode);

        // Step 2: Deploy TreasuryCore proxy with initializer
        bytes memory treasuryInitData = abi.encodeWithSignature(
            "initialize(address,address[],uint256,uint256)", admin, signers, threshold, minDelay
        );
        address treasuryProxy = _deployProxy(erc1967ProxyCode, treasuryImpl, treasuryInitData);

        // Step 3: Deploy StreamingManager implementation
        address streamingImpl = _deployCode(streamingManagerInitCode);

        // Step 4: Deploy StreamingManager proxy
        bytes memory streamingInitData = abi.encodeWithSignature(
            "initialize(address,address)", admin, treasuryProxy
        );
        address streamingProxy = _deployProxy(erc1967ProxyCode, streamingImpl, streamingInitData);

        // Step 5: Deploy YieldManager implementation
        address yieldImpl = _deployCode(yieldManagerInitCode);

        // Step 6: Deploy YieldManager proxy
        bytes memory yieldInitData = abi.encodeWithSignature(
            "initialize(address,address)", admin, treasuryProxy
        );
        address yieldProxy = _deployProxy(erc1967ProxyCode, yieldImpl, yieldInitData);

        // Step 7: Register modules
        IModuleRegistry(treasuryProxy).registerModule(MODULE_YIELD, yieldProxy);
        IModuleRegistry(treasuryProxy).registerModule(MODULE_STREAMING, streamingProxy);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("TreasuryCore Impl:  %s", treasuryImpl);
        console.log("TreasuryCore Proxy: %s", treasuryProxy);
        console.log("Streaming Impl:     %s", streamingImpl);
        console.log("Streaming Proxy:    %s", streamingProxy);
        console.log("Yield Impl:         %s", yieldImpl);
        console.log("Yield Proxy:        %s", yieldProxy);
    }

    function _deployCode(string memory code) internal returns (address) {
        bytes memory bytecode = vm.getCode(code);
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "deploy failed");
        return deployed;
    }

    function _deployProxy(string memory proxyCode, address impl, bytes memory initData)
        internal returns (address proxy)
    {
        bytes memory bytecode = vm.getCode(proxyCode);
        bytes memory fullCode = abi.encodePacked(bytecode, abi.encode(impl, initData));
        assembly {
            proxy := create(0, add(fullCode, 0x20), mload(fullCode))
        }
        require(proxy != address(0), "proxy deploy failed");
    }

    function _readBytecode(string memory name) internal view returns (string memory) {
        return string(abi.encodePacked("out/", name, ".sol/", name, ".json"));
    }

    function _parseSigners(string memory str) internal pure returns (address[] memory) {
        bytes memory s = bytes(str);
        if (s.length == 0) return new address[](0);
        uint256 count = 1;
        for (uint256 i = 0; i < s.length; i++) if (s[i] == ",") count++;
        address[] memory r = new address[](count);
        uint256 idx; uint256 ci; bytes memory c = new bytes(42);
        for (uint256 i = 0; i < s.length; i++) {
            if (s[i] == ",") {
                bytes memory a = new bytes(ci);
                for (uint256 j = 0; j < ci; j++) a[j] = c[j];
                r[idx++] = _a(string(a)); ci = 0;
            } else { c[ci++] = s[i]; }
        }
        if (ci > 0) { bytes memory a = new bytes(ci); for (uint256 j = 0; j < ci; j++) a[j] = c[j]; r[idx] = _a(string(a)); }
        return r;
    }

    function _a(string memory str) internal pure returns (address) {
        bytes memory b = bytes(str);
        uint160 r;
        for (uint256 i = 2; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            r = r * 16 + (c >= 48 && c <= 57 ? uint160(c - 48) : c >= 97 && c <= 102 ? uint160(c - 87) : c >= 65 && c <= 70 ? uint160(c - 55) : 0);
        }
        return address(r);
    }
}
