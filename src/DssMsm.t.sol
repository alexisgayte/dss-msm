pragma solidity ^0.6.7;

import "ds-test/test.sol";
import {Dai} from  "dss/dai.sol";

import "./testhelper/TestToken.sol";
import "./testhelper/MkrTokenAuthority.sol";

import "./DssMsm.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function roll(uint256) external;
}

contract User {

    Dai public dai;
    DssMsm public msm;

    constructor(Dai dai_, DssMsm msm_) public {
        dai = dai_;
        msm = msm_;
    }

    function sell(uint256 wad) public {
        DSToken(address(msm.token())).approve(address(msm));
        msm.sell(address(this), wad);
    }

    function buy(uint256 wad) public {
        dai.approve(address(msm), uint256(-1));
        msm.buy(address(this), wad);
    }

}

contract DssMsmTest is DSTest {
    Hevm hevm;
    address me;

    TestToken mkr;
    Dai dai;

    DssMsm msm;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
    bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    uint256 constant MKR_DEC = 10 ** 18;
    uint256 constant WAD = 10 ** 18;

    function setUp() public {
        me = address(this);
        hevm = Hevm(address(CHEAT_CODE));
        mkr = new TestToken("MKR", 18);
        MkrAuthority mkrAuthority = new MkrAuthority();
        mkr.setAuthority(DSAuthority(address(mkrAuthority)));
        mkr.mint(1000 * MKR_DEC);

        dai = new Dai(0);

        msm = new DssMsm(address(mkr), address(dai));
        dai.mint(address(msm), 1000000* WAD);

        msm.file("price", 500 * WAD);
        msm.file("reserve", 1000 * WAD);
        msm.file("tin", 0 * WAD);
        msm.file("tout", 1 * WAD);

    }

    function test_reserve() public {

        (uint256 daireserve, uint256 gemreserve, uint256 blockTimestampLast) = msm.getReserves();

        assertEq(daireserve, 1000000 ether);
        assertEq(gemreserve, 0);
        assertEq(blockTimestampLast, 0);

        mkr.approve(address(msm));
        msm.sell(me, 1 * MKR_DEC);
        hevm.warp(1 hours);

        (daireserve, gemreserve, blockTimestampLast) = msm.getReserves();
        assertEq(daireserve, 999500 ether);
        assertEq(gemreserve, 1 ether);
        assertEq(blockTimestampLast, 0);
    }

    function test_sell() public {
        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);

        mkr.approve(address(msm));
        msm.sell(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 200 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 900000 * WAD);
    }

    function test_sell_price_change() public {
        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);

        hevm.warp(1 hours);
        msm.file("price", 1000 * WAD);

        mkr.approve(address(msm));
        msm.sell(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 200000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 200 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 800000 * WAD);

        (uint256 daireserve, uint256 gemreserve, uint256 blockTimestampLast) = msm.getReserves();

        assertEq(daireserve, 800000 ether);
        assertEq(gemreserve, 200 ether);
        assertEq(blockTimestampLast, 3600);

    }

    function test_sell_fee() public {
        msm.file("tin", 10 * WAD / 100);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        mkr.approve(address(msm));
        msm.sell(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 90000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 200 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 910000 * WAD);
    }

    function test_swap_both_no_fee() public {
        msm.file("tin", 0 * WAD);
        msm.file("tout", 0 * WAD);
        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        mkr.approve(address(msm));
        msm.sell(me, 100 * MKR_DEC);
        dai.approve(address(msm), 500000 *WAD);
        msm.buy(me, 100 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);
    }

    function test_swap_both_fees_out() public {
        msm.file("tin", 0 * WAD);
        msm.file("tout", 1 * WAD);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        mkr.approve(address(msm));
        msm.sell(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        dai.approve(address(msm), 100000 * WAD);
        msm.buy(me, 100 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 900 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 100 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);
    }


    function test_swap_both_other() public {

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        mkr.approve(address(msm));
        msm.sell(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        User someUser = new User(dai, msm);
        dai.mint(address(someUser), 100000 * WAD);
        someUser.buy(100 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(mkr.balanceOf(address(someUser)), 100 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);
        assertEq(dai.balanceOf(address(someUser)), 0 * WAD);

    }

    function test_buy_burn_reserve() public {
        msm.file("reserve", 50 * WAD);
        msm.file("burn", true);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);

        mkr.approve(address(msm));
        msm.sell(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 45 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 900000 * WAD);

        assertEq(mkr.totalSupply(), 845 * MKR_DEC);
    }

    function test_buy_reserve_reach_with_burn_disable() public {
        msm.file("reserve", 50 * WAD);
        msm.file("burn", false);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);

        mkr.approve(address(msm));
        msm.sell(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 200 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 900000 * WAD);
    }

    function testFail_sell_insufficient_gem() public {
        User user1 = new User(dai, msm);
        user1.sell(40 * MKR_DEC);
    }

    function testFail_swap_both_small_fee_insufficient_dai() public {
        msm.file("tin", 0 * WAD);
        msm.file("tout", 1 * WAD);

        User user1 = new User(dai, msm);
        mkr.transfer(address(user1), 40 * MKR_DEC);
        user1.sell(40 * MKR_DEC);
        user1.buy(40 * MKR_DEC);
    }

    function testFail_sell_over_line() public {
        mkr.mint(1000 * MKR_DEC);
        mkr.approve(address(mkr));
        msm.buy(me, 2000 * MKR_DEC);
    }

    function testFail_two_users_insufficient_dai() public {
        User user1 = new User(dai, msm);
        mkr.transfer(address(user1), 40 * MKR_DEC);
        user1.sell(40 * MKR_DEC);

        User user2 = new User(dai, msm);
        dai.mint(address(user2), 39 ether);
        user2.buy(40 * MKR_DEC);
    }

    function test_swap_both_zero() public {
        mkr.approve(address(mkr), uint(-1));
        msm.sell(me, 0);
        dai.approve(address(msm), uint(-1));
        msm.buy(me, 0);
    }


}
