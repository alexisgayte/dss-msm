pragma solidity ^0.6.7;

import "dss-interfaces/ERC/GemAbstract.sol";
import "dss-interfaces/dss/DaiAbstract.sol";

contract DssMsm {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth { require(wards[msg.sender] == 1); _; }

    // --- Variable ---
    DaiAbstract public dai;
    GemAbstract public token;
    uint256 public dec;

    uint256 internal to18ConversionFactor;

    uint256 public tin;         // toll in [wad]
    uint256 public tout;        // toll out [wad]
    uint256 public price;       // price [wad]
    uint256 public reserve;     // gem amount keep to buy [wad]
    bool    public burn;        // burn or not the assert
    uint256 public blockTimestampLast;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, bool data);
    event Sell(address indexed owner, uint256 value, uint256 fee);
    event Buy(address indexed owner, uint256 value, uint256 fee);

    // --- Init ---
    constructor(address gem_, address dai_) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        token = GemAbstract(gem_);
        dai = DaiAbstract(dai_);

        burn = false;
        reserve = 1000*WAD;
        price = 500*WAD;
        tin = 0;
        tout = 2*WAD;
        blockTimestampLast = block.timestamp;

        require(GemAbstract(gem_).decimals() <= 18, "DssMsm/decimals-18-or-higher");
        to18ConversionFactor = 10 ** (18 - uint(GemAbstract(gem_).decimals()));
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "tin") {
            require(data < WAD , "DssMsm/more-100-percent");
            tin = data;
        }
        else if (what == "tout") {
            require(data < 10*WAD , "DssMsm/more-1000-percent");
            tout = data;
        }
        else if (what == "price") {
            price = data;
            blockTimestampLast = block.timestamp;
        }
        else if (what == "reserve") reserve = data;
        else revert("DssMsm/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, bool data) external auth {
        if (what == "burn") burn = data;
        else revert("DssMsm/file-unrecognized-param");

        emit File(what, data);
    }

    // --- View ---
    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
        _reserve0 = dai.balanceOf(address(this));
        _reserve1 = token.balanceOf(address(this));
        _blockTimestampLast = blockTimestampLast;
    }


    // --- Primary Functions ---
    function sell(address usr, uint256 gemAmt) external {

        uint256 gemAmt18 = mul(gemAmt, to18ConversionFactor);
        uint256 gemAmtPrice = mul(gemAmt18, price) / WAD;
        uint256 daiAmt = mul(gemAmtPrice, sub(1 * WAD, tin)) / WAD;

        emit Sell(usr, gemAmt, daiAmt);

        require(token.transferFrom(msg.sender, address(this), gemAmt), "DssMsm/failed-sell-transfer-gem");
        require(dai.transfer(msg.sender, daiAmt), "DssMsm/failed-sell-transfer-dai");

        if(burn && reserve < mul(token.balanceOf(address(this)), to18ConversionFactor)) {
            uint _amountReserveLeft18 = mul(reserve, (90 * WAD)/100 ) / WAD; // 90% total reserve
            uint _amountGem18 = mul(token.balanceOf(address(this)), to18ConversionFactor);

            token.burn(sub(_amountGem18, _amountReserveLeft18) / to18ConversionFactor);
        }

    }

    function buy(address usr, uint256 gemAmt) external {

        uint256 gemAmt18 = mul(gemAmt, to18ConversionFactor);
        uint256 gemAmtPrice = mul(gemAmt18, price) / WAD;
        uint256 daiAmt = mul(gemAmtPrice, add(1 * WAD, tout)) / WAD;

        emit Buy(usr, gemAmt, daiAmt);

        require(dai.transferFrom(msg.sender, address(this), daiAmt), "DssMsm/failed-buy-transfer-dai");
        require(token.transfer(address(msg.sender), gemAmt), "DssMsm/failed-buy-transfer-gem");

    }

}