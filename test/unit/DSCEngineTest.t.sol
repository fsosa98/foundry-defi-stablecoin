// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 public deployerKey;

    address public constant USER = address(1);
    address public constant LIQUIDATOR = address(2);
    uint256 public constant STARTING_BALANCE = 20 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_BALANCE);
    }

    // Constructor Tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // Price Tests
    function testGetUsdValue() public view {
        uint256 wethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, wethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 1000 ether;
        uint256 expectedWeth = 0.5 ether;
        assertEq(expectedWeth, dscEngine.getTokenAmountFromUsd(weth, usdAmount));
    }

    // Deposit Collateral Tests
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(randomToken)));
        dscEngine.depositCollateral(address(randomToken), 10);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        assertEq(0, totalDscMinted);
        assertEq(dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL), collateralValueInUsd);
    }

    // Mint DSC Tests
    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dscEngine.mintDsc(AMOUNT_TO_MINT);

        assertEq(dsc.balanceOf(USER), AMOUNT_TO_MINT);
    }

    function getCollateralValueInUsdAndMaxDscToMint() private view returns (uint256, uint256) {
        uint256 collateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 collateralAdjustedForThreshold =
            collateralValueInUsd * dscEngine.getLiquidationThreshold() / dscEngine.getLiquidationPrecision();
        uint256 maxDscToMint =
            collateralAdjustedForThreshold * dscEngine.getPrecision() / dscEngine.getMinHealthFactor();
        return (collateralValueInUsd, maxDscToMint);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (uint256 collateralValueInUsd, uint256 maxDscToMint) = getCollateralValueInUsdAndMaxDscToMint();
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(maxDscToMint + 1, collateralValueInUsd);

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDsc(maxDscToMint + 1);
        vm.stopPrank();
    }

    // Deposit Collateral and Mint DSC Tests
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndMintDsc() public depositedCollateralAndMintedDsc {
        uint256 collateral_amount = dscEngine.getCollateralBalanceOfUser(USER, weth);
        uint256 dsc_amount = dsc.balanceOf(USER);

        assertEq(collateral_amount, AMOUNT_COLLATERAL);
        assertEq(dsc_amount, AMOUNT_TO_MINT);
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (uint256 collateralValueInUsd, uint256 maxDscToMint) = getCollateralValueInUsdAndMaxDscToMint();
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(maxDscToMint + 1, collateralValueInUsd);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, maxDscToMint + 1);
        vm.stopPrank();
    }

    // Redeem Collateral Tests
    function testCanRedeemCollateral() public depositedCollateral {
        uint256 balanceBefore = ERC20Mock(weth).balanceOf(USER);
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        assertEq(ERC20Mock(weth).balanceOf(USER), balanceBefore + AMOUNT_COLLATERAL);
    }

    function testRevertsIfBreaksHealthFactor() public depositedCollateral {
        (uint256 collateralValueInUsd, uint256 maxDscToMint) = getCollateralValueInUsdAndMaxDscToMint();
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(maxDscToMint + 1, collateralValueInUsd);

        vm.startPrank(USER);
        dscEngine.mintDsc(maxDscToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.redeemCollateral(weth, 1);
        vm.stopPrank();
    }

    // Burn DSC Tests
    function testCanBurnMintedDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 0);
    }

    function testRevertsIfBurnAmountGreaterThanMintedAmount() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT + 1);
        vm.expectRevert();
        dscEngine.burnDsc(AMOUNT_TO_MINT + 1);
        vm.stopPrank();
    }

    // Redeem Collateral for DSC Test
    function testCanRedeemDepositedCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 0);
    }

    // Liquidation Tests
    function testCantLiquidateOkHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_BALANCE);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_BALANCE);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, LIQUIDATOR, AMOUNT_TO_MINT);
        vm.stopPrank();
    }
}
