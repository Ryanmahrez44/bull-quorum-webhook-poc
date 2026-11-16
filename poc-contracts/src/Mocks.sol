// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockERC20 {
    string public name = "Mock USDG";
    string public symbol = "MUSDG";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; totalSupply += amount; }
    function approve(address spender, uint256 amount) external returns (bool) { allowance[msg.sender][spender] = amount; return true; }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external {}
}

// Fee-on-transfer token: takes 10% on transferFrom/transfer.
contract MockFoT {
    string public name = "FoT";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) { allowance[msg.sender][spender] = amount; return true; }
    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 net = amount * 90 / 100;
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount; balanceOf[to] += net; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 net = amount * 90 / 100;
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += net; return true;
    }
}

// Oracle mock for call_gte/call_lte: returns a settable uint256.
contract MockOracle {
    uint256 public value;
    function set(uint256 v) external { value = v; }
    function read() external view returns (uint256) { return value; }
}

// Fake escrow: deals(id).status controllable (2 = Settled).
contract FakeEscrow {
    uint8 public status = 2;
    function setStatus(uint8 s) external { status = s; }
    function deals(uint256) external view returns (
        address buyer, address seller, address sellToken, uint256 sellAmount,
        address payToken, uint256 payAmount, uint64 deadline, bool buyerFunded,
        bool sellerFunded, uint8 st, address sellerPayout, address buyerReceive, uint16 feeBps
    ) {
        return (address(0), address(0), address(0), 0, address(0), 0, 0, false, false, status, address(0), address(0), 0);
    }
}
