// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IIrm} from "../../../lib/moolah/src/moolah/interfaces/IIrm.sol";
import {MarketParams, Market} from "../../../lib/moolah/src/moolah/interfaces/IMoolah.sol";

import {MathLib} from "../../../lib/moolah/src/moolah/libraries/MathLib.sol";

contract IrmMock is IIrm {
    using MathLib for uint128;

    function borrowRateView(MarketParams memory, Market memory market) public pure returns (uint256) {
        uint256 utilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);

        // Divide by the number of seconds in a year.
        // This is a very simple model where x% utilization corresponds to x% APR.
        return utilization / 365 days;
    }

    function borrowRate(MarketParams memory marketParams, Market memory market) external pure returns (uint256) {
        return borrowRateView(marketParams, market);
    }
}
