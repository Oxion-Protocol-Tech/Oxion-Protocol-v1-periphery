// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Multicall} from "../../src/base/Multicall.sol";

contract MockMulticall is Multicall {
    constructor() {}

    function functionThatRevertsWithError(string memory error) external pure {
        revert(error);
    }

    error CustomError(string);

    function functionThatRevertsWithCustomError(string memory param) external pure {
        revert CustomError(param);
    }

    struct Tuple {
        uint256 a;
        uint256 b;
    }

    function functionThatReturnsTuple(uint256 a, uint256 b) external pure returns (Tuple memory tuple) {
        tuple = Tuple({b: a, a: b});
    }

    uint256 public paid;

    function pays() external payable {
        paid += msg.value;
    }

    function returnSender() external view returns (address) {
        return msg.sender;
    }
}
