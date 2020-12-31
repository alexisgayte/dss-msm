pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "./DssMsm.sol";
import "../lib/dss/lib/ds-token/src/token.sol";
import {Dai}              from  "../lib/dss/src/dai.sol";

contract MkrAuthority {
    address public root;
    modifier sudo { require(msg.sender == root); _; }
    event LogSetRoot(address indexed newRoot);
    function setRoot(address usr) public sudo {
        root = usr;
        emit LogSetRoot(usr);
    }

    mapping (address => uint) public wards;
    event LogRely(address indexed usr);
    function rely(address usr) public sudo { wards[usr] = 1; emit LogRely(usr); }
    event LogDeny(address indexed usr);
    function deny(address usr) public sudo { wards[usr] = 0; emit LogDeny(usr); }

    constructor() public {
        root = msg.sender;
    }

    // bytes4(keccak256(abi.encodePacked('burn(uint256)')))
    bytes4 constant burn = bytes4(0x42966c68);
    // bytes4(keccak256(abi.encodePacked('burn(address,uint256)')))
    bytes4 constant burnFrom = bytes4(0x9dc29fac);
    // bytes4(keccak256(abi.encodePacked('mint(address,uint256)')))
    bytes4 constant mint = bytes4(0x40c10f19);

    function canCall(address src, address, bytes4 sig)
    public view returns (bool)
    {
        if (sig == burn || sig == burnFrom || src == root) {
            return true;
        } else if (sig == mint) {
            return (wards[src] == 1);
        } else {
            return false;
        }
    }
}

contract TestToken is DSToken {

    constructor(bytes32 symbol_, uint256 decimals_) public DSToken(symbol_) {
        decimals = decimals_;
    }

}

contract User {

    Dai public dai;
    DssMsm public msm;

    constructor(Dai dai_, DssMsm msm_) public {
        dai = dai_;
        msm = msm_;
    }

    function sellGem(uint256 wad) public {
        DSToken(address(msm.gem())).approve(address(msm));
        msm.sellGem(address(this), wad);
    }

    function buyGem(uint256 wad) public {
        dai.approve(address(msm), uint256(-1));
        msm.buyGem(address(this), wad);
    }

}

contract DssMsmTest is DSTest {

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

    function test_sellGem() public {
        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);

        mkr.approve(address(msm));
        msm.sellGem(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 200 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 900000 * WAD);
    }

    function test_sellGem_fee() public {
        msm.file("tin", 10 * WAD / 100);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        mkr.approve(address(msm));
        msm.sellGem(me, 200 * MKR_DEC);

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
        msm.sellGem(me, 100 * MKR_DEC);
        dai.approve(address(msm), 500000 *WAD);
        msm.buyGem(me, 100 * MKR_DEC);

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
        msm.sellGem(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        dai.approve(address(msm), 100000 * WAD);
        msm.buyGem(me, 100 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 900 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 100 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);
    }


    function test_swap_both_other() public {

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        mkr.approve(address(msm));
        msm.sellGem(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        User someUser = new User(dai, msm);
        dai.mint(address(someUser), 100000 * WAD);
        someUser.buyGem(100 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(mkr.balanceOf(address(someUser)), 100 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);
        assertEq(dai.balanceOf(address(someUser)), 0 * WAD);

    }

    function test_buyGem_burn_reserve() public {
        msm.file("reserve", 50 * WAD);
        msm.file("burn", true);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);

        mkr.approve(address(msm));
        msm.sellGem(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 45 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 900000 * WAD);

        assertEq(mkr.totalSupply(), 845 * MKR_DEC);
    }

    function test_buyGem_reserve_reach_with_burn_disable() public {
        msm.file("reserve", 50 * WAD);
        msm.file("burn", false);

        assertEq(mkr.balanceOf(me), 1000 * MKR_DEC);
        assertEq(dai.balanceOf(me), 0);

        assertEq(mkr.balanceOf(address(msm)), 0 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 1000000 * WAD);

        mkr.approve(address(msm));
        msm.sellGem(me, 200 * MKR_DEC);

        assertEq(mkr.balanceOf(me), 800 * MKR_DEC);
        assertEq(dai.balanceOf(me), 100000 * WAD);

        assertEq(mkr.balanceOf(address(msm)), 200 * MKR_DEC);
        assertEq(dai.balanceOf(address(msm)), 900000 * WAD);
    }

    function testFail_sellGem_insufficient_gem() public {
        User user1 = new User(dai, msm);
        user1.sellGem(40 * MKR_DEC);
    }

    function testFail_swap_both_small_fee_insufficient_dai() public {
        msm.file("tin", 0 * WAD);
        msm.file("tout", 1 * WAD);

        User user1 = new User(dai, msm);
        mkr.transfer(address(user1), 40 * MKR_DEC);
        user1.sellGem(40 * MKR_DEC);
        user1.buyGem(40 * MKR_DEC);
    }

    function testFail_sellGem_over_line() public {
        mkr.mint(1000 * MKR_DEC);
        mkr.approve(address(mkr));
        msm.buyGem(me, 2000 * MKR_DEC);
    }

    function testFail_two_users_insufficient_dai() public {
        User user1 = new User(dai, msm);
        mkr.transfer(address(user1), 40 * MKR_DEC);
        user1.sellGem(40 * MKR_DEC);

        User user2 = new User(dai, msm);
        dai.mint(address(user2), 39 ether);
        user2.buyGem(40 * MKR_DEC);
    }

    function test_swap_both_zero() public {
        mkr.approve(address(mkr), uint(-1));
        msm.sellGem(me, 0);
        dai.approve(address(msm), uint(-1));
        msm.buyGem(me, 0);
    }


}
