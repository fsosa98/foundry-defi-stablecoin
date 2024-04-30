// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStablecoinTest is Test {
    DecentralizedStableCoin dsc;
    address public constant USER = address(1);

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testCantMintToZeroAddress() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 1 ether);
    }

    function testMintAmountMustBeMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(USER, 0);
    }

    function testBurnAmountMustBeMoreThanZero() public {
        vm.prank(dsc.owner());
        dsc.mint(dsc.owner(), 10 ether);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testCantBurnMoreThanYouHave() public {
        vm.prank(dsc.owner());
        dsc.mint(dsc.owner(), 1 ether);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(10 ether);
    }
}
