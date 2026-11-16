// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Mocks.sol";

// BullAgreements (0xef9cEeB6594504ADe1ec903A7A29a2BFe38EFC8B, Robinhood Chain 4663).
// The contract is UNVERIFIED; this harness etches the REAL mainnet runtime
// bytecode with ONLY the feeSigner constant zeroed (both occurrences) so a
// junk 65-byte signature recovers address(0) == feeSigner and passes the
// quote check. All other bytes are bit-identical to mainnet. Payer is
// always msg.sender (enforced by the contract); Params has NO payer field.
//
// Structs reconstructed from the solc-generated ABI decoders in the
// deployed bytecode (Params decoder 0x3477, Condition decoder 0x3333,
// Quote decoder 0x3534) and confirmed by the storage layout in create().
interface IBullAgreements {
    struct Condition { uint8 kind; address target; bytes data; uint256 value; }
    struct Params { address payee; address asset; uint256 amount; uint64 expiry; bytes32 termsHash; Condition[] conditions; }
    struct Quote { uint256 fee; uint64 expiry; bytes sig; }
    function createAgreement(Params calldata p, Quote calldata q) external payable returns (uint256);
    function release(uint256 id) external;
    function refund(uint256 id) external;
    function attest(uint256 id, uint256 idx) external;
    function vote(uint256 id, uint256 idx) external;
    function object(uint256 id, uint256 idx) external;
    function agreement(uint256 id) external view returns (address payer, address payee, address asset, uint256 amount, uint64 expiry, uint8 status, bytes32 termsHash);
    function nextId() external view returns (uint256);
    function attested(uint256 id, uint256 idx) external view returns (bool);
    function votes(uint256 id, uint256 idx) external view returns (uint256);
    function voted(uint256 id, uint256 idx, address voter) external view returns (bool);
}

contract AgreementsTest is Test {
    IBullAgreements constant AGR = IBullAgreements(0xef9cEeB6594504ADe1ec903A7A29a2BFe38EFC8B);
    address payer = address(0x1111);
    address payee = address(0x2222);
    address attester = address(0x3333);
    MockERC20 usdg;

    function setUp() public {
        string memory hexstr = vm.readFile("test-data/agreements_zero_signer.hex");
        bytes memory code = vm.parseBytes(hexstr);
        vm.etch(address(AGR), code);
        // simulate constructor: reentrancy lock slot 6 = 1 (NOT_ENTERED)
        vm.store(address(AGR), bytes32(uint256(6)), bytes32(uint256(1)));
        usdg = new MockERC20();
        vm.deal(payer, 100 ether);
        vm.deal(payee, 100 ether);
        vm.deal(attester, 100 ether);
    }

    function _quote() internal view returns (IBullAgreements.Quote memory) {
        return IBullAgreements.Quote({fee: 0, expiry: uint64(block.timestamp + 3600), sig: new bytes(65)});
    }

    function _create(address _payee, address _asset, uint256 _amount, uint64 _expiry, IBullAgreements.Condition[] memory _conds, address _from, uint256 _value) internal returns (uint256 id) {
        IBullAgreements.Params memory p = IBullAgreements.Params({
            payee: _payee, asset: _asset, amount: _amount, expiry: _expiry,
            termsHash: bytes32(uint256(1)), conditions: _conds
        });
        vm.prank(_from);
        id = AGR.createAgreement{value: _value}(p, _quote());
    }

    function _timeAfter(uint256 at) internal pure returns (IBullAgreements.Condition[] memory c) {
        c = new IBullAgreements.Condition[](1);
        c[0] = IBullAgreements.Condition({kind: 0, target: address(0), data: "", value: at});
    }

    // Sanity: create a time_after ETH agreement and read it back.
    function test_create_timeAfter_works() public {
        uint256 id = _create(payee, address(0), 0.01 ether, uint64(block.timestamp + 72*3600), _timeAfter(block.timestamp + 3600), payer, 0.01 ether);
        (address p, address pe, address a, uint256 amt, uint64 exp, uint8 st, bytes32 th) = AGR.agreement(id);
        assertEq(p, payer, "payer must be msg.sender");
        assertEq(pe, payee);
        assertEq(a, address(0));
        assertEq(amt, 0.01 ether);
        assertEq(exp, uint64(block.timestamp + 72*3600));
        assertEq(st, 1, "status Open");
        assertEq(th, bytes32(uint256(1)));
        assertEq(address(AGR).balance, 0.01 ether);
    }

    // F-01 candidate: quorum with DUPLICATE voters can never complete.
    function test_quorum_duplicate_voters_lock() public {
        address[] memory voters = new address[](2);
        voters[0] = payer; voters[1] = payer; // duplicate!
        IBullAgreements.Condition[] memory c = new IBullAgreements.Condition[](1);
        c[0] = IBullAgreements.Condition({kind: 6, target: address(0), data: abi.encode(voters), value: 2});
        uint256 id = _create(payee, address(0), 0.01 ether, uint64(block.timestamp + 72*3600), c, payer, 0.01 ether);

        // payer votes once (counts 1/2)
        vm.prank(payer);
        AGR.vote(id, 0);
        assertEq(AGR.votes(id, 0), 1);
        assertTrue(AGR.voted(id, 0, payer));

        // second vote by the same address reverts (double-vote blocked)
        vm.prank(payer);
        vm.expectRevert(bytes4(0x8523b62a)); // BadState
        AGR.vote(id, 0);

        // release reverts: quorum not met (1 < 2)
        vm.expectRevert(bytes4(0xd5ae2fa4)); // conditions-not-met
        AGR.release(id);

        // funds are NOT stolen: after expiry the payer can refund in full
        vm.warp(block.timestamp + 73*3600);
        uint256 balBefore = payer.balance;
        vm.prank(payer);
        AGR.refund(id);
        assertEq(payer.balance - balBefore, 0.01 ether);
        (,,,,, uint8 st,) = AGR.agreement(id);
        assertEq(st, 3, "status Refunded");
    }

    // F-02 candidate: late objection defeats the "unless" window.
    function test_late_objection_blocks_release() public {
        IBullAgreements.Condition[] memory c = new IBullAgreements.Condition[](1);
        // unless: payee paid after 1h unless payer objects first
        c[0] = IBullAgreements.Condition({kind: 5, target: payer, data: "", value: block.timestamp + 3600});
        uint256 id = _create(payee, address(0), 0.01 ether, uint64(block.timestamp + 72*3600), c, payer, 0.01 ether);

        // window passes (2h later); payee has earned the payment...
        vm.warp(block.timestamp + 2*3600);
        // ...but the payer can STILL object (object() has no now < value check)
        vm.prank(payer);
        AGR.object(id, 0);

        // release now reverts forever
        vm.expectRevert(bytes4(0xd5ae2fa4));
        AGR.release(id);
    }

    // Control: objection BEFORE the window also blocks release (expected behaviour).
    function test_early_objection_blocks_release() public {
        IBullAgreements.Condition[] memory c = new IBullAgreements.Condition[](1);
        c[0] = IBullAgreements.Condition({kind: 5, target: payer, data: "", value: block.timestamp + 3600});
        uint256 id = _create(payee, address(0), 0.01 ether, uint64(block.timestamp + 72*3600), c, payer, 0.01 ether);
        vm.prank(payer);
        AGR.object(id, 0);
        vm.warp(block.timestamp + 2*3600);
        vm.expectRevert(bytes4(0xd5ae2fa4));
        AGR.release(id);
    }

    // Control: unless with NO objection releases fine after the window.
    function test_unless_no_objection_releases() public {
        IBullAgreements.Condition[] memory c = new IBullAgreements.Condition[](1);
        c[0] = IBullAgreements.Condition({kind: 5, target: payer, data: "", value: block.timestamp + 3600});
        uint256 id = _create(payee, address(0), 0.01 ether, uint64(block.timestamp + 72*3600), c, payer, 0.01 ether);
        vm.warp(block.timestamp + 2*3600);
        uint256 balBefore = payee.balance;
        AGR.release(id);
        assertEq(payee.balance - balBefore, 0.01 ether);
        (,,,,, uint8 st,) = AGR.agreement(id);
        assertEq(st, 2, "status Released");
    }

    // F-03 check: _pull has the exact balance-delta check, so a fee-on-transfer
    // token is REJECTED at creation (no underfunded agreement can be created).
    function test_pull_fot_rejected() public {
        MockFoT fot = new MockFoT();
        fot.mint(payer, 100 ether);
        vm.prank(payer);
        fot.approve(address(AGR), 100 ether);
        IBullAgreements.Params memory p = IBullAgreements.Params({
            payee: payee, asset: address(fot), amount: 1 ether, expiry: uint64(block.timestamp + 72*3600),
            termsHash: bytes32(uint256(1)), conditions: _timeAfter(block.timestamp + 3600)
        });
        vm.startPrank(payer);
        vm.expectRevert(bytes4(0x49986e73)); // WrongAmount from _pull
        AGR.createAgreement(p, _quote());
        vm.stopPrank();
    }

    // Control: a normal ERC20 agreement funds, releases, and pays the payee.
    function test_erc20_release() public {
        usdg.mint(payer, 100_000_000); // 100 USDG (6dp)
        vm.prank(payer);
        usdg.approve(address(AGR), 100_000_000);
        uint256 id = _create(payee, address(usdg), 10_000_000, uint64(block.timestamp + 72*3600), _timeAfter(block.timestamp + 3600), payer, 0);
        vm.warp(block.timestamp + 2*3600);
        AGR.release(id);
        assertEq(usdg.balanceOf(payee), 10_000_000);
    }
}

