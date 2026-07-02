// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreasuryFactory, TreasuryDeployment} from "../contracts/factory/TreasuryFactory.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("TREASURY_ADMIN");
        uint256 threshold = vm.envUint("SIGNER_THRESHOLD");
        uint256 minDelay = vm.envUint("MIN_DELAY");

        // Parse signers from comma-separated env var
        string memory signersStr = vm.envString("SIGNERS");
        address[] memory signers = _parseSigners(signersStr);

        vm.startBroadcast(deployerPrivateKey);

        TreasuryFactory factory = new TreasuryFactory();
        TreasuryDeployment memory d = factory.deploy(admin, signers, threshold, minDelay);

        vm.stopBroadcast();

        console.log("=== Treasury Deployment ===");
        console.log("TreasuryCore:", address(d.treasuryCore));
        console.log("StreamingManager:", address(d.streamingManager));
        console.log("YieldManager:", address(d.yieldManager));
        console.log("TreasuryCore Implementation:", address(d.treasuryCoreProxy));
        console.log("StreamingManager Implementation:", address(d.streamingProxy));
        console.log("YieldManager Implementation:", address(d.yieldProxy));
        console.log("Admin:", admin);
        console.log("Threshold:", threshold);
        console.log("MinDelay:", minDelay);
    }

    function _parseSigners(string memory str) internal pure returns (address[] memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) {
            return new address[](0);
        }

        // Count commas
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
