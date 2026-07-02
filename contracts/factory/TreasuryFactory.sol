// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryCore} from "../treasury/TreasuryCore.sol";
import {StreamingManager} from "../streaming/StreamingManager.sol";
import {YieldManager} from "../yield/YieldManager.sol";
import {
    DEFAULT_ADMIN_ROLE,
    MODULE_YIELD,
    MODULE_STREAMING
} from "../libraries/TreasuryConstants.sol";

struct TreasuryDeployment {
    TreasuryCore treasuryCore;
    StreamingManager streamingManager;
    YieldManager yieldManager;
    ERC1967Proxy treasuryCoreProxy;
    ERC1967Proxy streamingProxy;
    ERC1967Proxy yieldProxy;
}

contract TreasuryFactory {
    event TreasuryDeployed(
        address indexed treasuryCore,
        address indexed streamingManager,
        address indexed yieldManager
    );

    function deploy(
        address admin,
        address[] calldata initialSigners,
        uint256 globalThreshold,
        uint256 defaultMinDelay
    ) external returns (TreasuryDeployment memory deployment) {
        // Step 1: Deploy TreasuryCore implementation
        TreasuryCore treasuryImpl = new TreasuryCore();

        // Step 2: Deploy TreasuryCore proxy
        bytes memory initData = abi.encodeCall(
            TreasuryCore.initialize,
            (admin, initialSigners, globalThreshold, defaultMinDelay)
        );
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(address(treasuryImpl), initData);
        TreasuryCore treasury = TreasuryCore(payable(address(treasuryProxy)));

        // Step 3: Deploy StreamingManager implementation
        StreamingManager streamingImpl = new StreamingManager();

        // Step 4: Deploy StreamingManager proxy
        bytes memory streamingInitData =
            abi.encodeCall(StreamingManager.initialize, (admin, address(treasury)));
        ERC1967Proxy streamingProxy = new ERC1967Proxy(address(streamingImpl), streamingInitData);
        StreamingManager streaming = StreamingManager(address(streamingProxy));

        // Step 5: Deploy YieldManager implementation
        YieldManager yieldImpl = new YieldManager();

        // Step 6: Deploy YieldManager proxy
        bytes memory yieldInitData =
            abi.encodeCall(YieldManager.initialize, (admin, address(treasury)));
        ERC1967Proxy yieldProxy = new ERC1967Proxy(address(yieldImpl), yieldInitData);
        YieldManager yield = YieldManager(address(yieldProxy));

        emit TreasuryDeployed(address(treasury), address(streaming), address(yield));

        return TreasuryDeployment({
            treasuryCore: treasury,
            streamingManager: streaming,
            yieldManager: yield,
            treasuryCoreProxy: treasuryProxy,
            streamingProxy: streamingProxy,
            yieldProxy: yieldProxy
        });
    }
}
