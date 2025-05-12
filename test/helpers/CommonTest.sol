// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    IMoolah,
    Id,
    MarketParams,
    Authorization as MoolahAuthorization,
    Signature as MoolahSignature
} from "../../lib/moolah/src/moolah/interfaces/IMoolah.sol";

import {SigUtils} from "./SigUtils.sol";
import {MarketParamsLib} from "../../lib/moolah/src/moolah/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/moolah/src/moolah/libraries/SharesMathLib.sol";
import {MathLib, WAD} from "../../lib/moolah/src/moolah/libraries/MathLib.sol";
import {UtilsLib as MoolahUtilsLib} from "../../lib/moolah/src/moolah/libraries/UtilsLib.sol";
import {MoolahBalancesLib} from "../../lib/moolah/src/moolah/libraries/periphery/MoolahBalancesLib.sol";
import {
    LIQUIDATION_CURSOR,
    MAX_LIQUIDATION_INCENTIVE_FACTOR,
    ORACLE_PRICE_SCALE
} from "../../lib/moolah/src/moolah/libraries/ConstantsLib.sol";

import {IrmMock} from "../../lib/moolah/src/moolah/mocks/IrmMock.sol";
import {OracleMock} from "../../lib/moolah/src/moolah/mocks/OracleMock.sol";
import {ERC1967Proxy} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Permit} from "../helpers/SigUtils.sol";

import {CoreAdapter, IERC20, SafeERC20, UtilsLib} from "../../src/adapters/CoreAdapter.sol";
import {FunctionMocker} from "./FunctionMocker.sol";
import {GeneralAdapter1} from "../../src/adapters/GeneralAdapter1.sol";
import {Bundler3, Call} from "../../src/Bundler3.sol";

import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/console.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.
uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

abstract contract CommonTest is Test {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;
    using stdJson for string;

    address internal immutable USER = makeAddr("User");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable RECEIVER = makeAddr("Receiver");
    address internal immutable LIQUIDATOR = makeAddr("Liquidator");

    IMoolah internal moolah;
    IrmMock internal irm;
    OracleMock internal oracle;

    Bundler3 internal bundler3;
    GeneralAdapter1 internal generalAdapter1;

    Call[] internal bundle;
    Call[] internal callbackBundle;

    FunctionMocker internal functionMocker;

    function setUp() public virtual {
        uint256 MIN_LOAN_VALUE = 15 * 1e8;

        // Deploy Moolah implementation
        address impl = deployCode("Moolah.sol");
        vm.label(impl, "Moolah Impl");

        // Deploy Moolah proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            impl,
            abi.encodeWithSelector(
                bytes4(keccak256("initialize(address,address,address,uint256)")), OWNER, OWNER, OWNER, MIN_LOAN_VALUE
            )
        );
        vm.label(address(proxy), "Moolah Proxy");

        moolah = IMoolah(address(proxy));

        functionMocker = new FunctionMocker();

        bundler3 = new Bundler3();
        generalAdapter1 = new GeneralAdapter1(address(bundler3), address(moolah), address(1));

        irm = new IrmMock();

        vm.startPrank(OWNER);
        moolah.enableIrm(address(irm));
        moolah.enableIrm(address(0));
        moolah.enableLltv(0);
        vm.stopPrank();

        oracle = new OracleMock();

        vm.prank(USER);
        // So tests can borrow/withdraw on behalf of USER without pranking it.
        moolah.setAuthorization(address(this), true);
    }

    function emptyMarketParams() internal pure returns (MarketParams memory _emptyMarketParams) {}

    function _boundPrivateKey(uint256 privateKey) internal returns (uint256) {
        privateKey = bound(privateKey, 1, type(uint160).max);

        address user = vm.addr(privateKey);
        vm.label(user, "address of generated private key");

        return privateKey;
    }

    function _supplyCollateral(MarketParams memory _marketParams, uint256 amount, address onBehalf) internal {
        deal(_marketParams.collateralToken, onBehalf, amount, true);
        vm.prank(onBehalf);
        moolah.supplyCollateral(_marketParams, amount, onBehalf, hex"");
    }

    function _supply(MarketParams memory _marketParams, uint256 amount, address onBehalf) internal {
        deal(_marketParams.loanToken, onBehalf, amount, true);
        vm.prank(onBehalf);
        moolah.supply(_marketParams, amount, 0, onBehalf, hex"");
    }

    function _borrow(MarketParams memory _marketParams, uint256 amount, address onBehalf) internal {
        vm.prank(onBehalf);
        moolah.borrow(_marketParams, amount, 0, onBehalf, onBehalf);
    }

    function _delegatePrank(address to, bytes memory callData) internal {
        vm.mockFunction(to, address(functionMocker), callData);
        (bool success,) = to.call(callData);
        require(success, "Function mocker call failed");
    }

    // Pick a uint stable by timestamp.
    /// The environment variable PICK_UINT can be used to force a specific uint.
    // Used to make fork tests faster.
    function pickUint() internal view returns (uint256) {
        bytes32 _hash = keccak256(bytes.concat("pickUint", bytes32(block.timestamp)));
        uint256 num = uint256(_hash);
        return vm.envOr("PICK_UINT", num);
    }

    /* GENERAL ADAPTER CALL */
    function _call(CoreAdapter to, bytes memory data) internal pure returns (Call memory) {
        return _call(address(to), data, 0, false, hex"");
    }

    function _call(address to, bytes memory data) internal pure returns (Call memory) {
        return _call(to, data, 0, false, hex"");
    }

    function _call(CoreAdapter to, bytes memory data, uint256 value) internal pure returns (Call memory) {
        return _call(address(to), data, value, false, hex"");
    }

    function _call(address to, bytes memory data, uint256 value) internal pure returns (Call memory) {
        return _call(to, data, value, false, hex"");
    }

    function _call(CoreAdapter to, bytes memory data, bool skipRevert) internal pure returns (Call memory) {
        return _call(address(to), data, 0, skipRevert, hex"");
    }

    function _call(address to, bytes memory data, bool skipRevert) internal pure returns (Call memory) {
        return _call(to, data, 0, skipRevert, hex"");
    }

    function _call(CoreAdapter to, bytes memory data, bytes32 callbackHash) internal pure returns (Call memory) {
        return _call(address(to), data, 0, false, callbackHash);
    }

    function _call(CoreAdapter to, bytes memory data, uint256 value, bool skipRevert, bytes32 callbackHash)
        internal
        pure
        returns (Call memory)
    {
        return _call(address(to), data, value, skipRevert, callbackHash);
    }

    function _call(CoreAdapter to, bytes memory data, uint256 value, bool skipRevert)
        internal
        pure
        returns (Call memory)
    {
        return _call(address(to), data, value, skipRevert, hex"");
    }

    function _call(address to, bytes memory data, uint256 value, bool skipRevert) internal pure returns (Call memory) {
        return _call(to, data, value, skipRevert, hex"");
    }

    function _call(address to, bytes memory data, uint256 value, bool skipRevert, bytes32 callbackHash)
        internal
        pure
        returns (Call memory)
    {
        require(to != address(0), "Adapter address is zero");
        return Call(to, data, value, skipRevert, callbackHash);
    }

    /* CALL WITH VALUE */

    function _transferNativeToAdapter(address adapter, uint256 amount) internal pure returns (Call memory) {
        return _call(adapter, hex"", amount);
    }

    /* TRANSFER */

    function _nativeTransfer(address recipient, uint256 amount, CoreAdapter adapter)
        internal
        pure
        returns (Call memory)
    {
        return _call(adapter, abi.encodeCall(adapter.nativeTransfer, (recipient, amount)));
    }

    function _nativeTransferNoFunding(address recipient, uint256 amount, CoreAdapter adapter)
        internal
        pure
        returns (Call memory)
    {
        return _call(adapter, abi.encodeCall(adapter.nativeTransfer, (recipient, amount)), uint256(0));
    }

    /* ERC20 ACTIONS */

    function _erc20Transfer(address token, address recipient, uint256 amount, CoreAdapter adapter)
        internal
        pure
        returns (Call memory)
    {
        return _call(adapter, abi.encodeCall(adapter.erc20Transfer, (token, recipient, amount)));
    }

    function _erc20TransferFrom(address token, address recipient, uint256 amount) internal view returns (Call memory) {
        return _call(generalAdapter1, abi.encodeCall(GeneralAdapter1.erc20TransferFrom, (token, recipient, amount)));
    }

    function _erc20TransferFrom(address token, uint256 amount) internal view returns (Call memory) {
        return _erc20TransferFrom(token, address(generalAdapter1), amount);
    }

    /* ERC4626 ACTIONS */

    function _erc4626Mint(address vault, uint256 shares, uint256 maxSharePriceE27, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            generalAdapter1, abi.encodeCall(GeneralAdapter1.erc4626Mint, (vault, shares, maxSharePriceE27, receiver))
        );
    }

    function _erc4626Deposit(address vault, uint256 assets, uint256 maxSharePriceE27, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            generalAdapter1, abi.encodeCall(GeneralAdapter1.erc4626Deposit, (vault, assets, maxSharePriceE27, receiver))
        );
    }

    function _erc4626Withdraw(address vault, uint256 assets, uint256 minSharePriceE27, address receiver, address owner)
        internal
        view
        returns (Call memory)
    {
        return _call(
            generalAdapter1,
            abi.encodeCall(GeneralAdapter1.erc4626Withdraw, (vault, assets, minSharePriceE27, receiver, owner))
        );
    }

    function _erc4626Redeem(address vault, uint256 shares, uint256 minSharePriceE27, address receiver, address owner)
        internal
        view
        returns (Call memory)
    {
        return _call(
            generalAdapter1,
            abi.encodeCall(GeneralAdapter1.erc4626Redeem, (vault, shares, minSharePriceE27, receiver, owner))
        );
    }

    /* MOOLAH ACTIONS */

    function _moolahSetAuthorizationWithSig(uint256 privateKey, bool isAuthorized, uint256 nonce, bool skipRevert)
        internal
        view
        returns (Call memory)
    {
        address user = vm.addr(privateKey);

        MoolahAuthorization memory authorization = MoolahAuthorization({
            authorizer: user,
            authorized: address(generalAdapter1),
            isAuthorized: isAuthorized,
            nonce: nonce,
            deadline: SIGNATURE_DEADLINE
        });

        bytes32 digest = SigUtils.toTypedDataHash(moolah.DOMAIN_SEPARATOR(), authorization);

        MoolahSignature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return _call(
            address(moolah), abi.encodeCall(moolah.setAuthorizationWithSig, (authorization, signature)), 0, skipRevert
        );
    }

    function _moolahSupply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 maxSharePriceE27,
        address onBehalf,
        bytes memory data
    ) internal view returns (Call memory) {
        return _call(
            generalAdapter1,
            abi.encodeCall(
                GeneralAdapter1.moolahSupply, (marketParams, assets, shares, maxSharePriceE27, onBehalf, data)
            ),
            data.length == 0 ? bytes32(0) : keccak256(data)
        );
    }

    function _moolahSupply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address onBehalf
    ) internal view returns (Call memory) {
        return _moolahSupply(marketParams, assets, shares, slippageAmount, onBehalf, abi.encode(callbackBundle));
    }

    function _moolahBorrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver
    ) internal view returns (Call memory) {
        return _call(
            generalAdapter1,
            abi.encodeCall(GeneralAdapter1.moolahBorrow, (marketParams, assets, shares, minSharePriceE27, receiver))
        );
    }

    function _moolahWithdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address receiver
    ) internal view returns (Call memory) {
        return _call(
            generalAdapter1,
            abi.encodeCall(GeneralAdapter1.moolahWithdraw, (marketParams, assets, shares, slippageAmount, receiver))
        );
    }

    function _moolahRepay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 maxSharePriceE27,
        address onBehalf,
        bytes memory data
    ) internal view returns (Call memory) {
        return _call(
            generalAdapter1,
            abi.encodeCall(
                GeneralAdapter1.moolahRepay, (marketParams, assets, shares, maxSharePriceE27, onBehalf, data)
            ),
            data.length == 0 ? bytes32(0) : keccak256(data)
        );
    }

    function _moolahSupplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) internal view returns (Call memory) {
        return _call(
            generalAdapter1,
            abi.encodeCall(GeneralAdapter1.moolahSupplyCollateral, (marketParams, assets, onBehalf, data)),
            data.length == 0 ? bytes32(0) : keccak256(data)
        );
    }

    function _moolahWithdrawCollateral(MarketParams memory marketParams, uint256 assets, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            generalAdapter1, abi.encodeCall(GeneralAdapter1.moolahWithdrawCollateral, (marketParams, assets, receiver))
        );
    }

    function _moolahFlashLoan(address token, uint256 amount, bytes memory data) internal view returns (Call memory) {
        return _call(
            generalAdapter1,
            abi.encodeCall(GeneralAdapter1.moolahFlashLoan, (token, amount, data)),
            data.length == 0 ? bytes32(0) : keccak256(data)
        );
    }

    /* PERMIT ACTIONS */

    function _permit(
        IERC20Permit token,
        uint256 privateKey,
        address spender,
        uint256 amount,
        uint256 deadline,
        bool skipRevert
    ) internal view returns (Call memory) {
        address user = vm.addr(privateKey);

        Permit memory permit = Permit(user, spender, amount, token.nonces(user), deadline);

        bytes32 digest = SigUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory callData = abi.encodeCall(IERC20Permit.permit, (user, spender, amount, deadline, v, r, s));
        return _call(address(token), callData, 0, skipRevert);
    }
}
