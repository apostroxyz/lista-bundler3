// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SigUtils} from "./helpers/SigUtils.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {ErrorsLib as MoolahErrorsLib} from "../lib/moolah/src/moolah/libraries/ErrorsLib.sol";
import {MarketParamsLib} from "../lib/moolah/src/moolah/libraries/MarketParamsLib.sol";
import {MathRayLib} from "../src/libraries/MathRayLib.sol";

import "./helpers/LocalTest.sol";

contract MoolahAdapterLocalTest is LocalTest {
    using MathLib for uint256;
    using MoolahBalancesLib for IMoolah;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;
    using MathRayLib for uint256;

    function setUp() public override {
        super.setUp();

        vm.startPrank(USER);
        loanToken.approve(address(moolah), type(uint256).max);
        collateralToken.approve(address(moolah), type(uint256).max);
        loanToken.approve(address(generalAdapter1), type(uint256).max);
        collateralToken.approve(address(generalAdapter1), type(uint256).max);
        vm.stopPrank();

        vm.prank(LIQUIDATOR);
        loanToken.approve(address(generalAdapter1), type(uint256).max);
    }

    function approveERC20ToMoolahAndAdapter(address user) internal {
        vm.startPrank(user);
        loanToken.approve(address(moolah), type(uint256).max);
        collateralToken.approve(address(moolah), type(uint256).max);
        loanToken.approve(address(generalAdapter1), type(uint256).max);
        collateralToken.approve(address(generalAdapter1), type(uint256).max);
        vm.stopPrank();
    }

    function assumeOnBehalf(address onBehalf) internal view {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(moolah));
        vm.assume(onBehalf != address(generalAdapter1));
    }

    function testSetAuthorizationWithSig(uint256 privateKey, uint32 deadline) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, true));

        bundler3.multicall(bundle);

        assertTrue(moolah.isAuthorized(user, address(generalAdapter1)), "isAuthorized(user, generalAdapter1)");
    }

    function testSetAuthorizationWithSigRevert(uint256 privateKey, uint32 deadline) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));

        vm.expectRevert(bytes(MoolahErrorsLib.INVALID_NONCE));
        bundler3.multicall(bundle);
    }

    function testSupplyOnBehalfAdapterAddress(uint256 assets) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_moolahSupply(marketParams, assets, 0, type(uint256).max, address(generalAdapter1), hex""));

        vm.expectRevert(ErrorsLib.AdapterAddress.selector);
        bundler3.multicall(bundle);
    }

    function testSupplyCollateralOnBehalfAdapterAddress(uint256 assets) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_moolahSupplyCollateral(marketParams, assets, address(generalAdapter1), hex""));

        vm.expectRevert(ErrorsLib.AdapterAddress.selector);
        bundler3.multicall(bundle);
    }

    function testRepayOnBehalfAdapterAddress(uint256 assets) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_moolahRepay(marketParams, assets, 0, type(uint256).max, address(generalAdapter1), hex""));

        vm.expectRevert(ErrorsLib.AdapterAddress.selector);
        bundler3.multicall(bundle);
    }

    function _testSupply(uint256 amount, address onBehalf) internal view {
        assertEq(collateralToken.balanceOf(USER), 0, "collateral.balanceOf(USER)");
        assertEq(loanToken.balanceOf(USER), 0, "loan.balanceOf(USER)");

        assertEq(collateralToken.balanceOf(onBehalf), 0, "collateral.balanceOf(onBehalf)");
        assertEq(loanToken.balanceOf(onBehalf), 0, "loan.balanceOf(onBehalf)");

        assertEq(moolah.position(id, onBehalf).collateral, 0, "collateral(onBehalf)");
        assertEq(
            moolah.position(id, onBehalf).supplyShares, amount * SharesMathLib.VIRTUAL_SHARES, "supplyShares(onBehalf)"
        );
        assertEq(moolah.position(id, onBehalf).borrowShares, 0, "borrowShares(onBehalf)");

        if (onBehalf != USER) {
            assertEq(moolah.position(id, USER).collateral, 0, "collateral(USER)");
            assertEq(moolah.position(id, USER).supplyShares, 0, "supplyShares(USER)");
            assertEq(moolah.position(id, USER).borrowShares, 0, "borrowShares(USER)");
        }

        assertEq(
            loanToken.allowance(address(generalAdapter1), address(moolah)),
            type(uint256).max,
            "loanToken.allowance(generalAdapter1, moolah)"
        );
    }

    function testSupply(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(loanToken), amount));
        bundle.push(_moolahSupply(marketParams, amount, 0, type(uint256).max, onBehalf, hex""));

        deal(address(loanToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupply(amount, onBehalf);
    }

    function testSupplyShares(uint256 shares, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        shares = bound(shares, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(loanToken), type(uint128).max));
        bundle.push(_moolahSupply(marketParams, 0, shares, type(uint256).max, onBehalf, hex""));

        deal(address(loanToken), USER, type(uint128).max);

        vm.prank(USER);
        bundler3.multicall(bundle);

        assertEq(moolah.position(id, onBehalf).supplyShares, shares);
    }

    function testSupplyMax(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(loanToken), amount));
        bundle.push(_moolahSupply(marketParams, type(uint256).max, 0, type(uint256).max, onBehalf, hex""));

        deal(address(loanToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupply(amount, onBehalf);
    }

    function testSupplyCallback(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        callbackBundle.push(_erc20TransferFrom(address(loanToken), amount));

        bundle.push(_moolahSupply(marketParams, amount, 0, type(uint256).max, onBehalf, abi.encode(callbackBundle)));

        deal(address(loanToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupply(amount, onBehalf);
    }

    function _testSupplyCollateral(uint256 amount, address onBehalf) internal view {
        assertEq(collateralToken.balanceOf(USER), 0, "collateral.balanceOf(USER)");
        assertEq(loanToken.balanceOf(USER), 0, "loan.balanceOf(USER)");

        assertEq(collateralToken.balanceOf(onBehalf), 0, "collateral.balanceOf(onBehalf)");
        assertEq(loanToken.balanceOf(onBehalf), 0, "loan.balanceOf(onBehalf)");

        assertEq(moolah.position(id, onBehalf).collateral, amount, "collateral(onBehalf)");
        assertEq(moolah.position(id, onBehalf).supplyShares, 0, "supplyShares(onBehalf)");
        assertEq(moolah.position(id, onBehalf).borrowShares, 0, "borrowShares(onBehalf)");

        if (onBehalf != USER) {
            assertEq(moolah.position(id, USER).collateral, 0, "collateral(USER)");
            assertEq(moolah.position(id, USER).supplyShares, 0, "supplyShares(USER)");
            assertEq(moolah.position(id, USER).borrowShares, 0, "borrowShares(USER)");
        }
    }

    function testSupplyCollateral(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(collateralToken), amount));
        bundle.push(_moolahSupplyCollateral(marketParams, amount, onBehalf, hex""));

        deal(address(collateralToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupplyCollateral(amount, onBehalf);
    }

    function testSupplyCollateralMax(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(collateralToken), amount));
        bundle.push(_moolahSupplyCollateral(marketParams, type(uint256).max, onBehalf, hex""));

        deal(address(collateralToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupplyCollateral(amount, onBehalf);
    }

    function testWithdrawUnauthorized(uint256 withdrawnShares) public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        generalAdapter1.moolahWithdraw(marketParams, 0, withdrawnShares, 0, RECEIVER);
    }

    function testWithdraw(uint256 privateKey, uint256 amount, uint256 withdrawnShares) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        uint256 expectedSupplyShares = amount.toSharesDown(0, 0);
        withdrawnShares = bound(withdrawnShares, 1, expectedSupplyShares);
        uint256 expectedWithdrawnAmount = withdrawnShares.toAssetsDown(amount, expectedSupplyShares);

        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahWithdraw(marketParams, 0, withdrawnShares, 0, user));

        deal(address(loanToken), user, amount);

        vm.startPrank(user);
        moolah.supply(marketParams, amount, 0, user, hex"");

        bundler3.multicall(bundle);
        vm.stopPrank();

        assertEq(loanToken.balanceOf(user), expectedWithdrawnAmount, "loan.balanceOf(user)");
        assertEq(loanToken.balanceOf(address(generalAdapter1)), 0, "loan.balanceOf(address(generalAdapter1)");
        assertEq(
            loanToken.balanceOf(address(moolah)), amount - expectedWithdrawnAmount, "loan.balanceOf(address(moolah))"
        );

        assertEq(moolah.position(id, user).collateral, 0, "collateral(user)");
        assertEq(moolah.position(id, user).supplyShares, expectedSupplyShares - withdrawnShares, "supplyShares(user)");
        assertEq(moolah.position(id, user).borrowShares, 0, "borrowShares(user)");
    }

    function testMoolahSupplyMaxAssetsZero() public {
        bundle.push(_moolahSupply(marketParams, type(uint256).max, 0, type(uint256).max, address(this), hex""));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMoolahSupplyCollateralMaxZero() public {
        bundle.push(_moolahSupplyCollateral(marketParams, type(uint256).max, address(this), hex""));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMoolahSupplyCollateralZero(uint256 amount) public {
        deal(address(collateralToken), address(generalAdapter1), amount);
        bundle.push(_moolahSupplyCollateral(marketParams, 0, address(this), hex""));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMoolahRepayMaxAssetsZero() public {
        bundle.push(_moolahRepay(marketParams, type(uint256).max, 0, type(uint256).max, address(this), hex""));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMoolahRepayMaxSharesZero() public {
        bundle.push(_moolahRepay(marketParams, 0, type(uint256).max, type(uint256).max, address(this), hex""));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testWithdrawZeroMaxSupply() public {
        bundle.push(_moolahWithdraw(marketParams, 0, type(uint256).max, 0, RECEIVER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testWithdrawCollateralZero() public {
        bundle.push(_moolahWithdrawCollateral(marketParams, 0, RECEIVER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testWithdrawMaxSupply(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahWithdraw(marketParams, 0, type(uint256).max, 0, user));

        deal(address(loanToken), user, amount);

        vm.startPrank(user);
        moolah.supply(marketParams, amount, 0, user, hex"");

        bundler3.multicall(bundle);
        vm.stopPrank();

        assertEq(loanToken.balanceOf(user), amount, "loan.balanceOf(user)");
        assertEq(loanToken.balanceOf(address(generalAdapter1)), 0, "loan.balanceOf(address(generalAdapter1)");
        assertEq(loanToken.balanceOf(address(moolah)), 0, "loan.balanceOf(address(moolah))");

        assertEq(moolah.position(id, user).collateral, 0, "collateral(user)");
        assertEq(moolah.position(id, user).supplyShares, 0, "supplyShares(user)");
        assertEq(moolah.position(id, user).borrowShares, 0, "borrowShares(user)");
    }

    function testBorrowUnauthorized(uint256 borrowedAssets) public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        generalAdapter1.moolahBorrow(marketParams, borrowedAssets, 0, 0, RECEIVER);
    }

    function _testSupplyCollateralBorrow(address user, uint256 amount, uint256 collateralAmount) internal view {
        assertEq(collateralToken.balanceOf(RECEIVER), 0, "collateral.balanceOf(RECEIVER)");
        assertEq(loanToken.balanceOf(RECEIVER), amount, "loan.balanceOf(RECEIVER)");

        assertEq(moolah.position(id, user).collateral, collateralAmount, "collateral(user)");
        assertEq(moolah.position(id, user).supplyShares, 0, "supplyShares(user)");
        assertEq(moolah.position(id, user).borrowShares, amount * SharesMathLib.VIRTUAL_SHARES, "borrowShares(user)");

        if (RECEIVER != user) {
            assertEq(moolah.position(id, RECEIVER).collateral, 0, "collateral(RECEIVER)");
            assertEq(moolah.position(id, RECEIVER).supplyShares, 0, "supplyShares(RECEIVER)");
            assertEq(moolah.position(id, RECEIVER).borrowShares, 0, "borrowShares(RECEIVER)");

            assertEq(collateralToken.balanceOf(user), 0, "collateral.balanceOf(user)");
            assertEq(loanToken.balanceOf(user), 0, "loan.balanceOf(user)");
        }
    }

    function testSupplyCollateralBorrow(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(loanToken), address(this), amount);
        moolah.supply(marketParams, amount, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);

        bundle.push(_erc20TransferFrom(address(collateralToken), collateralAmount));
        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahSupplyCollateral(marketParams, collateralAmount, user, hex""));
        bundle.push(_moolahBorrow(marketParams, amount, 0, 0, RECEIVER));

        deal(address(collateralToken), user, collateralAmount);

        vm.prank(user);
        bundler3.multicall(bundle);

        _testSupplyCollateralBorrow(user, amount, collateralAmount);
    }

    function testSupplyCollateralBorrowViaCallback(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(loanToken), address(this), amount);
        moolah.supply(marketParams, amount, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);

        callbackBundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        callbackBundle.push(_moolahBorrow(marketParams, amount, 0, 0, RECEIVER));
        callbackBundle.push(_erc20TransferFrom(address(collateralToken), collateralAmount));

        bundle.push(_moolahSupplyCollateral(marketParams, collateralAmount, user, abi.encode(callbackBundle)));

        deal(address(collateralToken), user, collateralAmount);

        vm.prank(user);
        bundler3.multicall(bundle);

        _testSupplyCollateralBorrow(user, amount, collateralAmount);
    }

    function testWithdrawCollateralUnauthorized(uint256 collateralAmount) public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        generalAdapter1.moolahWithdrawCollateral(marketParams, collateralAmount, RECEIVER);
    }

    function _testRepayWithdrawCollateral(address user, uint256 collateralAmount) internal view {
        assertEq(collateralToken.balanceOf(RECEIVER), collateralAmount, "collateral.balanceOf(RECEIVER)");
        assertEq(loanToken.balanceOf(RECEIVER), 0, "loan.balanceOf(RECEIVER)");

        assertEq(moolah.position(id, user).collateral, 0, "collateral(user)");
        assertEq(moolah.position(id, user).supplyShares, 0, "supplyShares(user)");
        assertEq(moolah.position(id, user).borrowShares, 0, "borrowShares(user)");

        if (RECEIVER != user) {
            assertEq(moolah.position(id, RECEIVER).collateral, 0, "collateral(RECEIVER)");
            assertEq(moolah.position(id, RECEIVER).supplyShares, 0, "supplyShares(RECEIVER)");
            assertEq(moolah.position(id, RECEIVER).borrowShares, 0, "borrowShares(RECEIVER)");

            assertEq(collateralToken.balanceOf(user), 0, "collateral.balanceOf(user)");
            assertEq(loanToken.balanceOf(user), 0, "loan.balanceOf(user)");
        }
    }

    function testRepayWithdrawCollateral(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(loanToken), address(this), amount);
        moolah.supply(marketParams, amount, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        moolah.supplyCollateral(marketParams, collateralAmount, user, hex"");
        moolah.borrow(marketParams, amount, 0, user, user);
        vm.stopPrank();

        bundle.push(_erc20TransferFrom(address(loanToken), amount));
        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahRepay(marketParams, amount, 0, type(uint256).max, user, hex""));
        bundle.push(_moolahWithdrawCollateral(marketParams, collateralAmount, RECEIVER));

        vm.prank(user);
        bundler3.multicall(bundle);

        _testRepayWithdrawCollateral(user, collateralAmount);
    }

    function testRepayMaxAndWithdrawCollateral(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(loanToken), address(this), amount);
        moolah.supply(marketParams, amount, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        moolah.supplyCollateral(marketParams, collateralAmount, user, hex"");
        moolah.borrow(marketParams, amount, 0, user, user);
        vm.stopPrank();

        bundle.push(_erc20TransferFrom(address(loanToken), amount));
        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahRepay(marketParams, type(uint256).max, 0, type(uint256).max, user, hex""));
        bundle.push(_moolahWithdrawCollateral(marketParams, collateralAmount, RECEIVER));

        vm.prank(user);
        bundler3.multicall(bundle);

        _testRepayWithdrawCollateral(user, collateralAmount);
    }

    function testWithdrawMaxCollateral(uint256 privateKey, uint256 collateralAmount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        collateralAmount = bound(collateralAmount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(collateralToken), user, collateralAmount);
        vm.prank(user);
        moolah.supplyCollateral(marketParams, collateralAmount, user, hex"");

        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        bundle.push(_moolahWithdrawCollateral(marketParams, type(uint256).max, RECEIVER));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(collateralToken.balanceOf(RECEIVER), collateralAmount, "collateral.balanceOf(RECEIVER)");
    }

    function testRepayWithdrawCollateralViaCallback(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(loanToken), address(this), amount);
        moolah.supply(marketParams, amount, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        moolah.supplyCollateral(marketParams, collateralAmount, user, hex"");
        moolah.borrow(marketParams, amount, 0, user, user);
        vm.stopPrank();

        callbackBundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));
        callbackBundle.push(_moolahWithdrawCollateral(marketParams, collateralAmount, RECEIVER));
        callbackBundle.push(_erc20TransferFrom(address(loanToken), amount));

        bundle.push(_moolahRepay(marketParams, amount, 0, type(uint256).max, user, abi.encode(callbackBundle)));

        vm.prank(user);
        bundler3.multicall(bundle);

        _testRepayWithdrawCollateral(user, collateralAmount);
    }

    function testRepayMaxShares(uint256 privateKey, uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(generalAdapter1));
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);
        approveERC20ToMoolahAndAdapter(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(loanToken), address(this), amount);
        moolah.supply(marketParams, amount, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amount.wDivUp(LLTV);

        deal(address(collateralToken), onBehalf, collateralAmount);
        vm.startPrank(onBehalf);
        moolah.supplyCollateral(marketParams, collateralAmount, onBehalf, hex"");
        moolah.borrow(marketParams, amount, 0, onBehalf, address(generalAdapter1));
        vm.stopPrank();

        bundle.push(_moolahRepay(marketParams, 0, type(uint256).max, type(uint256).max, onBehalf, hex""));

        assertGt(moolah.position(marketParams.id(), onBehalf).borrowShares, 0, "before: borrowShares(onBehalf)");

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(loanToken.balanceOf(user), 0, "after: loan.balanceOf(user)");
        assertEq(moolah.position(marketParams.id(), onBehalf).borrowShares, 0, "after: borrowShares(onBehalf)");
        assertEq(loanToken.balanceOf(address(generalAdapter1)), 0, "loan.balanceOf(address(generalAdapter1)");
        assertEq(loanToken.balanceOf(address(moolah)), amount, "loan.balanceOf(address(moolah))");
    }

    struct BundleTransactionsVars {
        uint256 expectedSupplyShares;
        uint256 expectedBorrowShares;
        uint256 expectedTotalSupply;
        uint256 expectedTotalBorrow;
        uint256 expectedCollateral;
        uint256 expectedAdapterLoanBalance;
        uint256 expectedAdapterCollateralBalance;
        uint256 initialUserLoanBalance;
        uint256 initialUserCollateralBalance;
    }

    function testBundleTransactions(uint256 privateKey, uint256 size, uint256 seedAction, uint256 seedAmount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMoolahAndAdapter(user);

        bundle.push(_moolahSetAuthorizationWithSig(privateKey, true, 0, false));

        seedAction = bound(seedAction, 0, type(uint256).max - 30);
        seedAmount = bound(seedAmount, 0, type(uint256).max - 30);

        BundleTransactionsVars memory vars;

        for (uint256 i; i < size % 30; ++i) {
            uint256 actionId = uint256(keccak256(abi.encode(seedAmount + i))) % 11;
            uint256 amount = uint256(keccak256(abi.encode(seedAction + i)));
            if (actionId < 3) _addSupplyData(vars, amount, user);
            else if (actionId < 6) _addSupplyCollateralData(vars, amount, user);
            else if (actionId < 8) _addBorrowData(vars, amount);
            else if (actionId < 9) _addRepayData(vars, amount, user);
            else if (actionId < 10) _addWithdrawData(vars, amount);
            else if (actionId == 10) _addWithdrawCollateralData(vars, amount);
        }

        deal(address(loanToken), user, vars.initialUserLoanBalance);
        deal(address(collateralToken), user, vars.initialUserCollateralBalance);

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(moolah.position(id, user).supplyShares, vars.expectedSupplyShares, "User's supply shares");
        assertEq(moolah.position(id, user).borrowShares, vars.expectedBorrowShares, "User's borrow shares");
        assertEq(moolah.market(id).totalSupplyShares, vars.expectedSupplyShares, "Total supply shares");
        assertEq(moolah.market(id).totalBorrowShares, vars.expectedBorrowShares, "Total borrow shares");
        assertEq(moolah.market(id).totalSupplyAssets, vars.expectedTotalSupply, "Total supply");
        assertEq(moolah.market(id).totalBorrowAssets, vars.expectedTotalBorrow, "Total borrow");
        assertEq(moolah.position(id, user).collateral, vars.expectedCollateral, "User's collateral");

        assertEq(loanToken.balanceOf(user), 0, "User's loan balance");
        assertEq(collateralToken.balanceOf(user), 0, "User's collateral balance");
        assertEq(
            loanToken.balanceOf(address(moolah)),
            vars.expectedTotalSupply - vars.expectedTotalBorrow,
            "User's loan balance"
        );
        assertEq(collateralToken.balanceOf(address(moolah)), vars.expectedCollateral, "Moolah's collateral balance");
        assertEq(
            loanToken.balanceOf(address(generalAdapter1)),
            vars.expectedAdapterLoanBalance,
            unicode"Adapter's loan balance"
        );
        assertEq(
            collateralToken.balanceOf(address(generalAdapter1)),
            vars.expectedAdapterCollateralBalance,
            "Adapter's collateral balance"
        );
    }

    function _addSupplyData(BundleTransactionsVars memory vars, uint256 amount, address user) internal {
        amount = bound(amount % MAX_AMOUNT, MIN_AMOUNT, MAX_AMOUNT);

        _transferMissingLoan(vars, amount);

        bundle.push(_moolahSupply(marketParams, amount, 0, type(uint256).max, user, hex""));
        vars.expectedAdapterLoanBalance -= amount;

        uint256 expectedAddedSupplyShares = amount.toSharesDown(vars.expectedTotalSupply, vars.expectedSupplyShares);
        vars.expectedTotalSupply += amount;
        vars.expectedSupplyShares += expectedAddedSupplyShares;
    }

    function _addSupplyCollateralData(BundleTransactionsVars memory vars, uint256 amount, address user) internal {
        amount = bound(amount % MAX_AMOUNT, MIN_AMOUNT, MAX_AMOUNT);

        _transferMissingCollateral(vars, amount);

        bundle.push(_moolahSupplyCollateral(marketParams, amount, user, hex""));
        vars.expectedAdapterCollateralBalance -= amount;

        vars.expectedCollateral += amount;
    }

    function _addWithdrawData(BundleTransactionsVars memory vars, uint256 amount) internal {
        uint256 availableLiquidity = vars.expectedTotalSupply - vars.expectedTotalBorrow;
        if (availableLiquidity == 0 || vars.expectedSupplyShares == 0) return;

        uint256 supplyBalance =
            vars.expectedSupplyShares.toAssetsDown(vars.expectedTotalSupply, vars.expectedSupplyShares);

        uint256 maxAmount = MoolahUtilsLib.min(supplyBalance, availableLiquidity);
        amount = bound(amount % maxAmount, 1, maxAmount);

        bundle.push(_moolahWithdraw(marketParams, amount, 0, 0, address(generalAdapter1)));
        vars.expectedAdapterLoanBalance += amount;

        uint256 expectedDecreasedSupplyShares = amount.toSharesUp(vars.expectedTotalSupply, vars.expectedSupplyShares);
        vars.expectedTotalSupply -= amount;
        vars.expectedSupplyShares -= expectedDecreasedSupplyShares;
    }

    function _addBorrowData(BundleTransactionsVars memory vars, uint256 shares) internal {
        uint256 availableLiquidity = vars.expectedTotalSupply - vars.expectedTotalBorrow;
        if (availableLiquidity == 0 || vars.expectedCollateral == 0) return;

        uint256 totalBorrowPower = vars.expectedCollateral.wMulDown(marketParams.lltv);

        uint256 borrowed = vars.expectedBorrowShares.toAssetsUp(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        uint256 currentBorrowPower = totalBorrowPower - borrowed;
        if (currentBorrowPower == 0) return;

        uint256 maxShares = MoolahUtilsLib.min(currentBorrowPower, availableLiquidity).toSharesDown(
            vars.expectedTotalBorrow, vars.expectedBorrowShares
        );
        if (maxShares < MIN_AMOUNT) return;
        shares = bound(shares % maxShares, MIN_AMOUNT, maxShares);

        bundle.push(_moolahBorrow(marketParams, 0, shares, 0, address(generalAdapter1)));
        uint256 expectedBorrowedAmount = shares.toAssetsDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);
        vars.expectedAdapterLoanBalance += expectedBorrowedAmount;

        vars.expectedTotalBorrow += expectedBorrowedAmount;
        vars.expectedBorrowShares += shares;
    }

    function _addRepayData(BundleTransactionsVars memory vars, uint256 amount, address user) internal {
        if (vars.expectedBorrowShares == 0) return;

        uint256 borrowBalance =
            vars.expectedBorrowShares.toAssetsDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        amount = bound(amount % borrowBalance, 1, borrowBalance);

        _transferMissingLoan(vars, amount);

        bundle.push(_moolahRepay(marketParams, amount, 0, type(uint256).max, user, hex""));
        vars.expectedAdapterLoanBalance -= amount;

        uint256 expectedDecreasedBorrowShares = amount.toSharesDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);
        vars.expectedTotalBorrow -= amount;
        vars.expectedBorrowShares -= expectedDecreasedBorrowShares;
    }

    function _addWithdrawCollateralData(BundleTransactionsVars memory vars, uint256 amount) internal {
        if (vars.expectedCollateral == 0) return;

        uint256 borrowPower = vars.expectedCollateral.wMulDown(marketParams.lltv);
        uint256 borrowed = vars.expectedBorrowShares.toAssetsUp(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        uint256 withdrawableCollateral = (borrowPower - borrowed).wDivDown(marketParams.lltv);
        if (withdrawableCollateral == 0) return;

        amount = bound(amount % withdrawableCollateral, 1, withdrawableCollateral);

        bundle.push(_moolahWithdrawCollateral(marketParams, amount, address(generalAdapter1)));
        vars.expectedAdapterCollateralBalance += amount;

        vars.expectedCollateral -= amount;
    }

    function _transferMissingLoan(BundleTransactionsVars memory vars, uint256 amount) internal {
        if (amount > vars.expectedAdapterLoanBalance) {
            uint256 missingAmount = amount - vars.expectedAdapterLoanBalance;
            bundle.push(_erc20TransferFrom(address(loanToken), missingAmount));
            vars.initialUserLoanBalance += missingAmount;
            vars.expectedAdapterLoanBalance += missingAmount;
        }
    }

    function _transferMissingCollateral(BundleTransactionsVars memory vars, uint256 amount) internal {
        if (amount > vars.expectedAdapterCollateralBalance) {
            uint256 missingAmount = amount - vars.expectedAdapterCollateralBalance;
            bundle.push(_erc20TransferFrom(address(collateralToken), missingAmount));
            vars.initialUserCollateralBalance += missingAmount;
            vars.expectedAdapterCollateralBalance += missingAmount;
        }
    }

    function testSlippageSupplyOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivUp(shares), type(uint256).max);

        deal(marketParams.loanToken, address(generalAdapter1), assets);

        bundle.push(_moolahSupply(marketParams, assets, 0, sharePriceE27, address(this), hex""));
        bundler3.multicall(bundle);
    }

    function testSlippageSupplyKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares) - 1);

        deal(marketParams.loanToken, address(generalAdapter1), assets);

        bundle.push(_moolahSupply(marketParams, assets, 0, sharePriceE27, address(this), hex""));
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);
    }

    function testSlippageWithdrawOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares));

        deal(marketParams.loanToken, address(this), assets);
        moolah.supply(marketParams, assets, 0, address(this), hex"");
        moolah.setAuthorization(address(generalAdapter1), true);

        bundle.push(_moolahWithdraw(marketParams, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageWithdrawKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivDown(shares) + 1, type(uint256).max);

        deal(marketParams.loanToken, address(this), assets);
        moolah.supply(marketParams, assets, 0, address(this), hex"");
        moolah.setAuthorization(address(generalAdapter1), true);

        bundle.push(_moolahWithdraw(marketParams, assets, 0, sharePriceE27, address(this)));
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);
    }

    function testSlippageBorrowOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivDown(shares));
        uint256 collateral = assets.wDivUp(LLTV);

        deal(marketParams.loanToken, address(this), assets);
        deal(marketParams.collateralToken, address(this), collateral);
        moolah.supply(marketParams, assets, 0, address(this), hex"");
        moolah.supplyCollateral(marketParams, collateral, address(this), hex"");
        moolah.setAuthorization(address(generalAdapter1), true);

        bundle.push(_moolahBorrow(marketParams, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageBorrowKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivDown(shares) + 1, type(uint256).max);
        uint256 collateral = assets.wDivUp(LLTV);

        deal(marketParams.loanToken, address(this), assets);
        deal(marketParams.collateralToken, address(this), collateral);
        moolah.supply(marketParams, assets, 0, address(this), hex"");
        moolah.supplyCollateral(marketParams, collateral, address(this), hex"");
        moolah.setAuthorization(address(generalAdapter1), true);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundle.push(_moolahBorrow(marketParams, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageRepayOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivUp(shares), type(uint256).max);
        uint256 collateral = assets.wDivUp(LLTV);

        deal(marketParams.loanToken, address(this), assets);
        deal(marketParams.collateralToken, address(this), collateral);
        moolah.supply(marketParams, assets, 0, address(this), hex"");
        moolah.supplyCollateral(marketParams, collateral, address(this), hex"");
        moolah.borrow(marketParams, assets, 0, address(this), address(generalAdapter1));

        bundle.push(_moolahRepay(marketParams, assets, 0, sharePriceE27, address(this), hex""));
        bundler3.multicall(bundle);
    }

    function testSlippageRepayKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares) - 1);
        uint256 collateral = assets.wDivUp(LLTV);

        deal(marketParams.loanToken, address(this), assets);
        deal(marketParams.collateralToken, address(this), collateral);
        moolah.supply(marketParams, assets, 0, address(this), hex"");
        moolah.supplyCollateral(marketParams, collateral, address(this), hex"");
        moolah.borrow(marketParams, assets, 0, address(this), address(generalAdapter1));

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundle.push(_moolahRepay(marketParams, assets, 0, sharePriceE27, address(this), hex""));
        bundler3.multicall(bundle);
    }

    function testFlashLoanZero() public {
        bundle.push(_moolahFlashLoan(address(0), 0, hex""));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testFlashLoan(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(loanToken), address(this), amount);

        moolah.supply(marketParams, amount, 0, SUPPLIER, hex"");

        callbackBundle.push(_erc20Transfer(address(loanToken), USER, amount, generalAdapter1));
        callbackBundle.push(_erc20TransferFrom(address(loanToken), amount));

        bundle.push(_moolahFlashLoan(address(loanToken), amount, abi.encode(callbackBundle)));

        vm.prank(USER);
        bundler3.multicall(bundle);

        assertEq(loanToken.balanceOf(USER), 0, "User's loan token balance");
        assertEq(loanToken.balanceOf(address(generalAdapter1)), 0, "Adapter's loan token balance");
        assertEq(loanToken.balanceOf(address(moolah)), amount, "Moolah's loan token balance");
    }
}
