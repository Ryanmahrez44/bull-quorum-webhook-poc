// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// Layout matrix for BullAgreements.createAgreement.
// Correct layout => validation passes => BadQuote 0xf3fb463d (junk sig).
contract LayoutMatrix is Test {
    address constant AGR = 0xef9cEeB6594504ADe1ec903A7A29a2BFe38EFC8B;
    address payer = address(0x1111);
    address payee = address(0x2222);

    // D: (kind, target, voters, value, data)
    struct CondD { uint8 kind; address target; address[] voters; uint256 value; bytes data; }
    struct ParamsD1 { address payer; address payee; address asset; uint256 amount; uint64 expiry; CondD[] conditions; bytes32 termsHash; }
    struct ParamsD2 { address payer; address payee; address asset; uint64 expiry; uint256 amount; CondD[] conditions; bytes32 termsHash; }
    // B: (kind, target, data, value, voters)
    struct CondB { uint8 kind; address target; bytes data; uint256 value; address[] voters; }
    struct ParamsB1 { address payer; address payee; address asset; uint256 amount; uint64 expiry; CondB[] conditions; bytes32 termsHash; }
    struct ParamsB2 { address payer; address payee; address asset; uint64 expiry; uint256 amount; CondB[] conditions; bytes32 termsHash; }
    struct Quote { uint256 fee; uint64 expiry; bytes sig; }

    function setUp() public {
        string memory hexstr = vm.readFile("test-data/agreements_patched.hex");
        bytes memory code = vm.parseBytes(hexstr);
        vm.etch(AGR, code);
        vm.store(AGR, bytes32(uint256(6)), bytes32(uint256(1)));
        vm.deal(payer, 100 ether);
    }

    function _call(bytes memory data, address from, uint256 value) internal returns (bool, bytes memory) {
        vm.prank(from);
        return AGR.call{value: value}(data);
    }

    function _report(string memory name, bool ok, bytes memory ret) internal {
        emit log_named_string(name, ok ? "OK" : "REVERT");
        emit log_named_bytes(string.concat(name, " ret"), ret);
    }

    function _voters() internal pure returns (address[] memory v) {
        v = new address[](2);
        v[0] = address(0xAAAA); v[1] = address(0xBBBB);
    }

    function _q() internal view returns (Quote memory) {
        return Quote({fee: 0, expiry: uint64(block.timestamp + 3600), sig: new bytes(65)});
    }

    // --- quorum with CondD ---
    function test_D1_quorum() public {
        CondD[] memory c = new CondD[](1);
        c[0] = CondD({kind: 6, target: address(0), voters: _voters(), value: 2, data: ""});
        ParamsD1 memory p = ParamsD1({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("D1 quorum", ok, ret);
    }

    function test_D2_quorum() public {
        CondD[] memory c = new CondD[](1);
        c[0] = CondD({kind: 6, target: address(0), voters: _voters(), value: 2, data: ""});
        ParamsD2 memory p = ParamsD2({payer: payer, payee: payee, asset: address(0), expiry: uint64(block.timestamp + 72*3600), amount: 0.01 ether, conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("D2 quorum", ok, ret);
    }

    // --- quorum with CondB, voters abi-encoded into data ---
    function test_B1_quorum_dataVoters() public {
        CondB[] memory c = new CondB[](1);
        c[0] = CondB({kind: 6, target: address(0), data: abi.encode(_voters()), value: 2, voters: new address[](0)});
        ParamsB1 memory p = ParamsB1({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("B1 quorum dataVoters", ok, ret);
    }

    function test_B2_quorum_dataVoters() public {
        CondB[] memory c = new CondB[](1);
        c[0] = CondB({kind: 6, target: address(0), data: abi.encode(_voters()), value: 2, voters: new address[](0)});
        ParamsB2 memory p = ParamsB2({payer: payer, payee: payee, asset: address(0), expiry: uint64(block.timestamp + 72*3600), amount: 0.01 ether, conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("B2 quorum dataVoters", ok, ret);
    }

    // --- time_after with CondD ---
    function test_D1_timeAfter() public {
        CondD[] memory c = new CondD[](1);
        c[0] = CondD({kind: 0, target: address(0), voters: new address[](0), value: block.timestamp + 3600, data: ""});
        ParamsD1 memory p = ParamsD1({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("D1 timeAfter", ok, ret);
    }

    function test_D2_timeAfter() public {
        CondD[] memory c = new CondD[](1);
        c[0] = CondD({kind: 0, target: address(0), voters: new address[](0), value: block.timestamp + 3600, data: ""});
        ParamsD2 memory p = ParamsD2({payer: payer, payee: payee, asset: address(0), expiry: uint64(block.timestamp + 72*3600), amount: 0.01 ether, conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("D2 timeAfter", ok, ret);
    }

    // --- time_after with CondB, nonzero dummy target ---
    function test_B1_timeAfter_target() public {
        CondB[] memory c = new CondB[](1);
        c[0] = CondB({kind: 0, target: address(0x1234), data: "", value: block.timestamp + 3600, voters: new address[](0)});
        ParamsB1 memory p = ParamsB1({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("B1 timeAfter target", ok, ret);
    }

    function test_B2_timeAfter_target() public {
        CondB[] memory c = new CondB[](1);
        c[0] = CondB({kind: 0, target: address(0x1234), data: "", value: block.timestamp + 3600, voters: new address[](0)});
        ParamsB2 memory p = ParamsB2({payer: payer, payee: payee, asset: address(0), expiry: uint64(block.timestamp + 72*3600), amount: 0.01 ether, conditions: c, termsHash: bytes32(uint256(1))});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, _q()), payer, 0.01 ether);
        _report("B2 timeAfter target", ok, ret);
    }
}
