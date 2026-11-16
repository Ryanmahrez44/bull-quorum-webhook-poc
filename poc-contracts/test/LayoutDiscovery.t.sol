// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// Layout discovery for BullAgreements.createAgreement (selector 0x8952f925).
// We etch the REAL mainnet runtime bytecode with ONLY the feeSigner constant
// patched (0x5857... -> vm.addr(1)) so we can sign fee quotes locally.
contract LayoutDiscovery is Test {
    address constant AGR = 0xef9cEeB6594504ADe1ec903A7A29a2BFe38EFC8B;
    address payer = address(0x1111);
    address payee = address(0x2222);

    struct CondA { uint8 kind; address target; uint256 value; bytes data; address[] voters; }
    struct CondB { uint8 kind; address target; bytes data; uint256 value; address[] voters; }
    struct CondC { uint8 kind; address target; bytes data; address[] voters; uint256 value; }
    struct ParamsA { address payer; address payee; address asset; uint256 amount; uint64 expiry; CondA[] conditions; bytes32 termsHash; }
    struct ParamsB { address payer; address payee; address asset; uint256 amount; uint64 expiry; CondB[] conditions; bytes32 termsHash; }
    struct ParamsC { address payer; address payee; address asset; uint256 amount; uint64 expiry; CondC[] conditions; bytes32 termsHash; }
    struct Quote { uint256 fee; uint64 expiry; bytes sig; }

    function setUp() public {
        string memory hexstr = vm.readFile("test-data/agreements_patched.hex");
        bytes memory code = vm.parseBytes(hexstr);
        vm.etch(AGR, code);
        // simulate constructor: reentrancy lock slot 6 = 1 (NOT_ENTERED)
        vm.store(AGR, bytes32(uint256(6)), bytes32(uint256(1)));
        vm.deal(payer, 100 ether);
    }

    function _call(bytes memory data, address from, uint256 value) internal returns (bool ok, bytes memory ret) {
        vm.prank(from);
        (ok, ret) = AGR.call{value: value}(data);
    }

    function _report(string memory name, bool ok, bytes memory ret) internal {
        emit log_named_string(name, ok ? "OK" : "REVERT");
        emit log_named_bytes(string.concat(name, " ret"), ret);
    }

    // time_after condition, fee=0, junk sig: correct layout => BadQuote 0xf3fb463d
    function test_layoutA() public {
        CondA[] memory conds = new CondA[](1);
        conds[0] = CondA({kind: 0, target: address(0), value: block.timestamp + 3600, data: "", voters: new address[](0)});
        ParamsA memory p = ParamsA({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: conds, termsHash: bytes32(uint256(1))});
        Quote memory q = Quote({fee: 0, expiry: uint64(block.timestamp + 3600), sig: new bytes(65)});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, q), payer, 0.01 ether);
        _report("layoutA", ok, ret);
    }

    function test_layoutB() public {
        CondB[] memory conds = new CondB[](1);
        conds[0] = CondB({kind: 0, target: address(0), data: "", value: block.timestamp + 3600, voters: new address[](0)});
        ParamsB memory p = ParamsB({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: conds, termsHash: bytes32(uint256(1))});
        Quote memory q = Quote({fee: 0, expiry: uint64(block.timestamp + 3600), sig: new bytes(65)});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, q), payer, 0.01 ether);
        _report("layoutB", ok, ret);
    }

    function test_layoutC() public {
        CondC[] memory conds = new CondC[](1);
        conds[0] = CondC({kind: 0, target: address(0), data: "", voters: new address[](0), value: block.timestamp + 3600});
        ParamsC memory p = ParamsC({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: conds, termsHash: bytes32(uint256(1))});
        Quote memory q = Quote({fee: 0, expiry: uint64(block.timestamp + 3600), sig: new bytes(65)});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, q), payer, 0.01 ether);
        _report("layoutC", ok, ret);
    }

    // Quorum condition (kind=6) with voters [A,B], needed=2: distinguishes B vs C.
    function test_layoutB_quorum() public {
        address[] memory voters = new address[](2);
        voters[0] = address(0xAAAA); voters[1] = address(0xBBBB);
        CondB[] memory conds = new CondB[](1);
        conds[0] = CondB({kind: 6, target: address(0), data: "", value: 2, voters: voters});
        ParamsB memory p = ParamsB({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: conds, termsHash: bytes32(uint256(1))});
        Quote memory q = Quote({fee: 0, expiry: uint64(block.timestamp + 3600), sig: new bytes(65)});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, q), payer, 0.01 ether);
        _report("layoutB quorum", ok, ret);
    }

    function test_layoutC_quorum() public {
        address[] memory voters = new address[](2);
        voters[0] = address(0xAAAA); voters[1] = address(0xBBBB);
        CondC[] memory conds = new CondC[](1);
        conds[0] = CondC({kind: 6, target: address(0), data: "", voters: voters, value: 2});
        ParamsC memory p = ParamsC({payer: payer, payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600), conditions: conds, termsHash: bytes32(uint256(1))});
        Quote memory q = Quote({fee: 0, expiry: uint64(block.timestamp + 3600), sig: new bytes(65)});
        (bool ok, bytes memory ret) = _call(abi.encodeWithSelector(bytes4(0x8952f925), p, q), payer, 0.01 ether);
        _report("layoutC quorum", ok, ret);
    }
}
