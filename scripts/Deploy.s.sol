// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreasuryFactory, TreasuryDeployment} from "../contracts/factory/TreasuryFactory.sol";
import {TreasuryCore} from "../contracts/treasury/TreasuryCore.sol";
import {StreamingManager} from "../contracts/streaming/StreamingManager.sol";
import {YieldManager} from "../contracts/yield/YieldManager.sol";
import {
    MODULE_YIELD,
    MODULE_STREAMING
} from "../contracts/libraries/TreasuryConstants.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("TREASURY_ADMIN");
        uint256 threshold = vm.envUint("SIGNER_THRESHOLD");
        uint256 minDelay = vm.envUint("MIN_DELAY");

        string memory signersStr = vm.envString("SIGNERS");
        address[] memory signers = _parseSigners(signersStr);

        console.log("=== Company Treasury Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Admin:", admin);
        console.log("Signers:");
        for (uint256 i = 0; i < signers.length; i++) {
            console.log("  [%d] %s", i, signers[i]);
        }
        console.log("Threshold: %d/%d", threshold, signers.length);
        console.log("Min Delay: %d seconds", minDelay);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy all contracts via factory
        TreasuryFactory factory = new TreasuryFactory();
        TreasuryDeployment memory d = factory.deploy(admin, signers, threshold, minDelay);

        // Auto-register external modules
        TreasuryCore(payable(address(d.treasuryCore))).registerModule(MODULE_YIELD, address(d.yieldManager));
        TreasuryCore(payable(address(d.treasuryCore))).registerModule(MODULE_STREAMING, address(d.streamingManager));

        vm.stopBroadcast();

        // Output deployment info
        console.log("=== Deployment Complete ===");
        console.log("TreasuryCore Proxy:       %s", address(d.treasuryCore));
        console.log("TreasuryCore Impl:        %s", address(d.treasuryCoreProxy));
        console.log("StreamingManager Proxy:   %s", address(d.streamingManager));
        console.log("StreamingManager Impl:    %s", address(d.streamingProxy));
        console.log("YieldManager Proxy:       %s", address(d.yieldManager));
        console.log("YieldManager Impl:        %s", address(d.yieldProxy));
        console.log("");

        // Write deployment artifact
        string memory json = _buildDeploymentJson(d, admin);
        vm.writeFile("./deployments/deployment.json", json);
        console.log("Deployment artifact written to deployments/deployment.json");
    }

    function _buildDeploymentJson(TreasuryDeployment memory d, address admin)
        internal
        pure
        returns (string memory)
    {
        string memory s = string(abi.encodePacked(
            '{"chainId":', vm.toString(block.chainid),
            ',"admin":"', vm.toString(admin),
            '","treasuryCore":"', vm.toString(address(d.treasuryCore)),
            '","treasuryCoreImpl":"', vm.toString(address(d.treasuryCoreProxy)),
            '","streamingManager":"', vm.toString(address(d.streamingManager)),
            '","streamingManagerImpl":"', vm.toString(address(d.streamingProxy)),
            '","yieldManager":"', vm.toString(address(d.yieldManager)),
            '","yieldManagerImpl":"', vm.toString(address(d.yieldProxy)),
            '"}'
        ));
        return s;
    }

    function _parseSigners(string memory str) internal pure returns (address[] memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) {
            return new address[](0);
        }

        uint256 count = 1;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == ",") count++;
        }

        address[] memory result = new address[](count);
        uint256 idx = 0;
        bytes memory current = new bytes(42);
        uint256 currentIdx = 0;

        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == ",") {
                bytes memory addrBytes = new bytes(currentIdx);
                for (uint256 j = 0; j < currentIdx; j++) {
                    addrBytes[j] = current[j];
                }
                result[idx] = _parseAddress(string(addrBytes));
                idx++;
                currentIdx = 0;
            } else {
                current[currentIdx] = strBytes[i];
                currentIdx++;
            }
        }

        if (currentIdx > 0) {
            bytes memory addrBytes = new bytes(currentIdx);
            for (uint256 j = 0; j < currentIdx; j++) {
                addrBytes[j] = current[j];
            }
            result[idx] = _parseAddress(string(addrBytes));
        }

        return result;
    }

    function _parseAddress(string memory str) internal pure returns (address) {
        bytes memory b = bytes(str);
        uint160 result = 0;
        for (uint256 i = 2; i < b.length; i++) {
            result = result * 16 + _hexToUint(uint8(b[i]));
        }
        return address(result);
    }

    function _hexToUint(uint8 c) internal pure returns (uint160) {
        if (c >= uint8(bytes1("0")) && c <= uint8(bytes1("9"))) {
            return uint160(c - uint8(bytes1("0")));
        } else if (c >= uint8(bytes1("a")) && c <= uint8(bytes1("f"))) {
            return uint160(c - uint8(bytes1("a")) + 10);
        } else if (c >= uint8(bytes1("A")) && c <= uint8(bytes1("F"))) {
            return uint160(c - uint8(bytes1("A")) + 10);
        }
        return 0;
    }
}
