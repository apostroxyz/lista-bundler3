// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "../../src/libraries/ErrorsLib.sol";

import {ERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20PermitMock} from "../helpers/mocks/ERC20PermitMock.sol";

import "./helpers/ForkTest.sol";

/// @dev The unique EIP-712 domain domain separator for the DAI token contract on Ethereum.
bytes32 constant DAI_DOMAIN_SEPARATOR = 0xdbb8cf42e1ecb028be3f3dbc922e1d878b963f411dc388ced501601c60f7c6f7;

contract PermitAdapterForkTest is ForkTest {
    ERC20PermitMock internal permitToken;

    function setUp() public override {
        super.setUp();

        permitToken = new ERC20PermitMock("Permit Token", "PT");
    }

    function testPermit(uint256 amount, address spender, uint256 deadline) public {
        uint256 privateKey = _boundPrivateKey(pickUint());
        address user = vm.addr(privateKey);
        vm.assume(spender != address(0));
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        bundle.push(_permit(permitToken, privateKey, spender, amount, deadline, false));
        bundle.push(_permit(permitToken, privateKey, spender, amount, deadline, true));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(permitToken.allowance(user, spender), amount, "allowance(user, spender)");
    }

    function testPermitRevert(uint256 amount, address spender, uint256 deadline) public {
        uint256 privateKey = _boundPrivateKey(pickUint());
        address user = vm.addr(privateKey);
        vm.assume(spender != address(0));
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        bundle.push(_permit(permitToken, privateKey, spender, amount, deadline, false));
        bundle.push(_permit(permitToken, privateKey, spender, amount, deadline, false));

        vm.prank(user);
        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        bundler3.multicall(bundle);
    }

    function testTransferFrom(uint256 amount, uint256 deadline) public {
        uint256 privateKey = _boundPrivateKey(pickUint());
        address user = vm.addr(privateKey);
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        deadline = bound(deadline, block.timestamp, type(uint48).max);

        bundle.push(_permit(permitToken, privateKey, address(generalAdapter1), amount, deadline, false));

        bundle.push(_erc20TransferFrom(address(permitToken), amount));

        deal(address(permitToken), user, amount);

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(permitToken.balanceOf(address(generalAdapter1)), amount, "balanceOf(generalAdapter1)");
        assertEq(permitToken.balanceOf(user), 0, "balanceOf(user)");
    }
}
