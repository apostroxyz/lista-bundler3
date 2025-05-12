// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {CommonBase} from "../../../lib/forge-std/src/Base.sol";

// Holds fork-specific configuration data

struct ConfigMarket {
    string collateralToken;
    string loanToken;
    uint256 lltv;
}

// NetworkConfig loads config data at construction time.
// This makes config data available to inheriting test contracts when they are constructed.
// But `block.chainid` is not preserved between the constructor and the call to `setUp`. So we store the planned chainid
// in the config to have it available.
struct Config {
    string network;
    uint256 chainid;
    uint256 blockNumber;
    mapping(string => address) addresses;
    ConfigMarket[] markets;
}

abstract contract NetworkConfig is CommonBase {
    function initializeConfigData() private {
        /* BSC NETWORK */

        if (config.chainid == 56) {
            config.network = "bsc";
            config.blockNumber = 49533000;
            config.markets.push(ConfigMarket({collateralToken: "WETH", loanToken: "WETH", lltv: 800000000000000000}));

            setAddress("DAI", 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3);
            setAddress("WETH", 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB
        }
    }

    address public constant UNINITIALIZED_ADDRESS = address(bytes20(bytes32("UNINITIALIZED ADDRESS")));

    Config internal config;

    // Load known addresses before tests try to use them when initializing their state variables.
    bool private initialized = initializeConfig();

    function initializeConfig() internal virtual returns (bool) {
        require(!initialized, "Configured: already initialized");

        vm.label(UNINITIALIZED_ADDRESS, "UNINITIALIZED_ADDRESS");

        // Run tests on Ethereum by default
        if (block.chainid == 31337) {
            config.chainid = 56;
        } else {
            config.chainid = block.chainid;
        }

        initializeConfigData();

        require(
            bytes(config.network).length > 0,
            string.concat("Configured: unknown chain id ", vm.toString(config.chainid))
        );
        return true;
    }

    function getAddress(string memory name) internal view returns (address addr) {
        addr = config.addresses[name];
        return addr == address(0) ? UNINITIALIZED_ADDRESS : addr;
    }

    function hasAddress(string memory name) internal view returns (bool) {
        return config.addresses[name] != address(0);
    }

    function setAddress(string memory name, address addr) internal {
        require(addr != address(0), "NetworkConfig: cannot set address 0");
        config.addresses[name] = addr;
        vm.label(addr, name);
    }
}
