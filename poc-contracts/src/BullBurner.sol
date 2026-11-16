// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface IWETH {
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
}

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function WETH9() external view returns (address);
}

contract BullBurner {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint8 private constant V4_SWAP = 0x10;
    uint8 private constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 private constant SETTLE_ALL = 0x0c;
    uint8 private constant TAKE_ALL = 0x0f;

    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    IUniversalRouter public constant universalRouter = IUniversalRouter(0x8876789976dEcBfCbBbe364623C63652db8C0904);
    ISwapRouter02 public constant swapRouterV3 = ISwapRouter02(0xCaf681a66D020601342297493863E78C959E5cb2);

    address public immutable keeper;
    address public immutable bull;
    address public immutable usdg;
    address public immutable weth;
    uint24 public immutable v3Fee;
    uint24 public immutable v4Fee;
    int24 public immutable v4TickSpacing;
    address public immutable v4Hooks;

    uint256 public constant OPEN_AFTER = 1 days;

    uint256 public totalBurned;
    uint256 public totalEthSpent;
    uint256 public lastBurn;

    event Burned(uint256 usdgIn, uint256 ethSpent, uint256 bullBurned, address indexed by);

    error NotAllowed();
    error BadInput();
    error NothingToBurn();
    error SwapFailed();

    constructor(
        address _keeper,
        address _bull,
        address _usdg,
        uint24 _v4Fee,
        int24 _v4TickSpacing,
        address _v4Hooks,
        uint24 _v3Fee
    ) {
        if (
            _keeper == address(0) || _bull == address(0) || _usdg == address(0) || _bull == _usdg
        ) revert BadInput();
        address _weth = swapRouterV3.WETH9();
        keeper = _keeper;
        bull = _bull;
        usdg = _usdg;
        weth = _weth;
        v4Fee = _v4Fee;
        v4TickSpacing = _v4TickSpacing;
        v4Hooks = _v4Hooks;
        v3Fee = _v3Fee;
        lastBurn = block.timestamp;

        IERC20(_usdg).approve(address(swapRouterV3), type(uint256).max);
    }

    receive() external payable {}

    function burn(uint256 minEthFromUsdg, uint256 minBullOut) external {
        bool isKeeper = msg.sender == keeper;
        if (!isKeeper && block.timestamp < lastBurn + OPEN_AFTER) revert NotAllowed();
        if (!isKeeper) {
            if (minEthFromUsdg == 0) minEthFromUsdg = 1;
            if (minBullOut == 0) minBullOut = 1;
        }

        uint256 usdgIn = IERC20(usdg).balanceOf(address(this));
        if (usdgIn > 0) _usdgToEth(usdgIn, minEthFromUsdg);

        uint256 ethIn = address(this).balance;
        if (ethIn > 0) _ethToBull(ethIn, minBullOut);

        uint256 bal = IERC20(bull).balanceOf(address(this));
        if (bal == 0) revert NothingToBurn();
        if (!IERC20(bull).transfer(DEAD, bal)) revert SwapFailed();

        totalBurned += bal;
        totalEthSpent += ethIn;
        lastBurn = block.timestamp;
        emit Burned(usdgIn, ethIn, bal, msg.sender);
    }

    function _usdgToEth(uint256 usdgIn, uint256 minOut) private {
        swapRouterV3.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: usdg,
                tokenOut: weth,
                fee: v3Fee,
                recipient: address(this),
                amountIn: usdgIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );
        IWETH(weth).withdraw(IWETH(weth).balanceOf(address(this)));
    }

    function _ethToBull(uint256 amountIn, uint256 minOut) private {
        if (amountIn > type(uint128).max || minOut > type(uint128).max) revert BadInput();
        PoolKey memory key = PoolKey({currency0: address(0), currency1: bull, fee: v4Fee, tickSpacing: v4TickSpacing, hooks: v4Hooks});

        bytes memory actions = abi.encodePacked(SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL);
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: uint128(amountIn),
                amountOutMinimum: uint128(minOut),
                hookData: ""
            })
        );
        params[1] = abi.encode(address(0), amountIn);
        params[2] = abi.encode(bull, minOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        universalRouter.execute{value: amountIn}(abi.encodePacked(V4_SWAP), inputs, block.timestamp + 300);
    }
}