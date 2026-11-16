// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "./Agreements.t.sol";

// Try several quote-hash constructions against the feeSigner=vm.addr(1)
// patched bytecode; log which one (if any) creates successfully.
contract QuoteHashVariants is Test {
    IBullAgreements constant AGR = IBullAgreements(0xef9cEeB6594504ADe1ec903A7A29a2BFe38EFC8B);
    address payer = address(0x1111);
    address payee = address(0x2222);

    function setUp() public {
        string memory hexstr = vm.readFile("test-data/agreements_patched.hex");
        bytes memory code = vm.parseBytes(hexstr);
        vm.etch(address(AGR), code);
        vm.store(address(AGR), bytes32(uint256(6)), bytes32(uint256(1)));
        vm.deal(payer, 100 ether);
    }

    function _params() internal view returns (IBullAgreements.Params memory p) {
        IBullAgreements.Condition[] memory c = new IBullAgreements.Condition[](1);
        c[0] = IBullAgreements.Condition({kind: 0, target: address(0), data: "", value: block.timestamp + 3600});
        p = IBullAgreements.Params({
            payee: payee, asset: address(0), amount: 0.01 ether, expiry: uint64(block.timestamp + 72*3600),
            termsHash: bytes32(uint256(1)), conditions: c
        });
    }

    function _try(bytes32 digest, uint64 qExp) internal returns (bool ok) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        IBullAgreements.Quote memory q = IBullAgreements.Quote({fee: 0, expiry: qExp, sig: abi.encodePacked(r, s, v)});
        bytes memory data = abi.encodeWithSelector(IBullAgreements.createAgreement.selector, _params(), q);
        vm.prank(payer);
        (ok,) = address(AGR).call{value: 0.01 ether}(data);
    }

    function test_variants() public {
        IBullAgreements.Params memory p = _params();
        uint64 qExp = uint64(block.timestamp + 3600);
        bytes32 ph = keccak256(abi.encode(p));
        bytes32 h1 = keccak256(abi.encode(block.chainid, address(AGR), payer, ph, uint256(0), qExp));
        emit log_named_string("V1 eth-prefixed", _try(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h1)), qExp) ? "OK" : "FAIL");
        emit log_named_string("V1 raw", _try(h1, qExp) ? "OK" : "FAIL");
        bytes32 h2 = keccak256(abi.encodePacked(block.chainid, address(AGR), payer, ph, uint256(0), qExp));
        emit log_named_string("V2 packed eth-prefixed", _try(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h2)), qExp) ? "OK" : "FAIL");
        emit log_named_string("V2 packed raw", _try(h2, qExp) ? "OK" : "FAIL");
        // fee/expiry order swapped in the outer hash
        bytes32 h3 = keccak256(abi.encode(block.chainid, address(AGR), payer, ph, qExp, uint256(0)));
        emit log_named_string("V3 swapped eth-prefixed", _try(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h3)), qExp) ? "OK" : "FAIL");
        emit log_named_string("V3 swapped raw", _try(h3, qExp) ? "OK" : "FAIL");
    }
}
