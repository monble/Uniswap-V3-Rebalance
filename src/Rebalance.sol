// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "src/additions/erc20.sol";
import "src/interfaces/IUniswapV3Pool.sol";
import "src/interfaces/ISwapRouter.sol";
import "src/interfaces/IUniswapCalculator.sol";
import "src/interfaces/IUniswapV3PositionsNFT.sol";

contract Rebalance {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;
  address owner;

  struct Proportion {
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0;
    uint256 amount1;
    uint128 liquidity;
  }

  IERC20 public token0;
  IERC20 public token1;
  uint256 public tokenId;
  uint256 private amtSpecified = 10000000000000000;

  address private vault;
  int24 private tick_lower;
  int24 private tick_upper;

  address public constant univ3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public constant oneinch = 0x1111111254EEB25477B68fb85Ed929f73A960582;
  IUniswapV3PositionsNFT public constant nftManager = IUniswapV3PositionsNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
  IUniswapV3Pool public pool = IUniswapV3Pool(0x1fb3cf6e48F1E7B10213E7b6d87D4c073C7Fdb7b);
  IUniswapCalculator public uniswapCalculator;

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }
  

  function initialize() public {
    require(owner == address(0));
    owner = msg.sender;
    vault = msg.sender;

    deployCalculator();

    token0 = IERC20(pool.token0());
    token1 = IERC20(pool.token1());
    uint256 amt = type(uint96).max;

    token0.approve(univ3Router, amt);
    token1.approve(univ3Router, amt);

    token0.approve(oneinch, amt);
    token1.approve(oneinch, amt);

    token0.approve(address(nftManager), amt);
    token1.approve(address(nftManager), amt);
    nftManager.setApprovalForAll(address(nftManager), true);

    token0.approve(vault, amt);
    token1.approve(vault, amt);
    nftManager.setApprovalForAll(vault, true);
  }


  function setPool(
    address _pool,
    uint256 _amtSpecified
  ) public onlyOwner() {   
    pool = IUniswapV3Pool(_pool);
    amtSpecified = _amtSpecified;

    token0 = IERC20(pool.token0());
    token1 = IERC20(pool.token1());

    token0.approve(oneinch, type(uint96).max);
    token1.approve(oneinch, type(uint96).max);

    token0.approve(univ3Router, type(uint96).max);
    token1.approve(univ3Router, type(uint96).max);

    token0.approve(address(nftManager), type(uint96).max);
    token1.approve(address(nftManager), type(uint96).max);
    nftManager.setApprovalForAll(address(nftManager), true);
    
    token0.approve(vault, type(uint96).max);
    token1.approve(vault, type(uint96).max);
    nftManager.setApprovalForAll(vault, true);
  }


  function withdraw(int24 tickLow, int24 tickUp) external onlyOwner() {
    if (tokenId != 0) {
    ( ,int24 tickNow, , , , , ) = pool.slot0();
    require(tickLow <= tickNow);
    require(tickUp >= tickNow);

      (, , , , , , , uint256 _liquidity, , , , ) = nftManager.positions(tokenId);
      nftManager.decreaseLiquidity(
        IUniswapV3PositionsNFT.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(_liquidity),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp
        })
      );

      nftManager.collect(
        IUniswapV3PositionsNFT.CollectParams({
          tokenId: tokenId,
          recipient: address(this),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );
      tokenId = 0; 
    }
      token0.transfer(vault, token0.balanceOf(address(this)));
      token1.transfer(vault, token1.balanceOf(address(this)));

  }


  function simulate (int24 _tickLower, int24 _tickUpper) external onlyOwner() returns (uint256, address, address, uint256) {
    if (tokenId != 0) {
      (, , , , , , , uint256 _liquidity, , , , ) = nftManager.positions(tokenId);

      nftManager.decreaseLiquidity(
        IUniswapV3PositionsNFT.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(_liquidity),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp
        })
      );    
      nftManager.collect(
        IUniswapV3PositionsNFT.CollectParams({
          tokenId: tokenId,
          recipient: address(this),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );
    }


    (uint256 _amountSpecified, address _inputToken, address _outputToken) = _readRebalanceProportion(_tickLower, _tickUpper);
    uint256 inRange = _balanceProportion(_tickLower,_tickUpper);
    return (_amountSpecified, _inputToken, _outputToken, inRange);
  }


  function rebalanceVia1inch (int24 _tickLower, int24 _tickUpper, bytes calldata _data, int24 tickLow, int24 tickUp, bool dontSwap) external onlyOwner() {
    if (tokenId != 0) {
      (, , , , , , , uint256 _liquidity, , , , ) = nftManager.positions(tokenId);

      nftManager.decreaseLiquidity(
        IUniswapV3PositionsNFT.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(_liquidity),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp
        })
      );    
      nftManager.collect(
        IUniswapV3PositionsNFT.CollectParams({
          tokenId: tokenId,
          recipient: address(this),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );

    }


    ( ,int24 tickNow, , , , , ) = pool.slot0();
    require(tickLow <= tickNow);
    require(tickUp >= tickNow);
    if (dontSwap == false) {
    (bool success, ) = oneinch.call(_data);
    require(success, "1inch swap unsucessful");
    }

    uint256 _amount0Desired = token0.balanceOf(address(this));
    uint256 _amount1Desired = token1.balanceOf(address(this));

    (tokenId, , , ) = nftManager.mint(
      IUniswapV3PositionsNFT.MintParams({
        token0: address(token0),
        token1: address(token1),
        fee: pool.fee(),
        tickLower: _tickLower,
        tickUpper: _tickUpper,
        amount0Desired: _amount0Desired,
        amount1Desired: _amount1Desired,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp
      })
    );

    tick_lower = _tickLower;
    tick_upper = _tickUpper;
  }

  function rebalance (int24 _tickLower, int24 _tickUpper) external onlyOwner() {
    if (tokenId != 0) {
      (, , , , , , , uint256 _liquidity, , , , ) = nftManager.positions(tokenId);

      nftManager.decreaseLiquidity(
        IUniswapV3PositionsNFT.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(_liquidity),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp
        })
      );    
      nftManager.collect(
        IUniswapV3PositionsNFT.CollectParams({
          tokenId: tokenId,
          recipient: address(this),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );

    }
    ( ,int24 tickNow, , , , , ) = pool.slot0();
    require(_tickLower <= tickNow);
    require(_tickUpper >= tickNow);

    _balanceProportion(_tickLower, _tickUpper);


    uint256 _amount0Desired = token0.balanceOf(address(this));
    uint256 _amount1Desired = token1.balanceOf(address(this));

    (tokenId, , , ) = nftManager.mint(
      IUniswapV3PositionsNFT.MintParams({
        token0: address(token0),
        token1: address(token1),
        fee: pool.fee(),
        tickLower: _tickLower,
        tickUpper: _tickUpper,
        amount0Desired: _amount0Desired,
        amount1Desired: _amount1Desired,
        amount0Min: 100,
        amount1Min: 100,
        recipient: address(this),
        deadline: block.timestamp
      })
    );


    tick_lower = _tickLower;
    tick_upper = _tickUpper;
  }



  function _amountsDirection(
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0,
    uint256 amount1
  ) internal pure returns (bool zeroGreaterOne) {
    zeroGreaterOne = (amount0Desired - amount0) * amount1Desired > (amount1Desired - amount1) * amount0Desired
      ? true
      : false;
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes memory
  ) public pure returns (bytes4) {
    return this.onERC721Received.selector;
  }
  
  function slot0() public view returns(
    int24 ticklower,
    int24 tickupper,
    uint256 tokenID,
    int24 tickNow,
    bool inRange
  ) {
    ticklower = tick_lower;
    tickupper = tick_upper;
    tokenID = tokenId;
    ( ,tickNow, , , , , ) = pool.slot0();
    inRange = inRangeCalc();
  }


  function inRangeCalc() public view returns (bool) {
    (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
    uint160 sqrtRatioAX96 = uniswapCalculator.getSqrtRatioAtTick(tick_lower);
    uint160 sqrtRatioBX96 = uniswapCalculator.getSqrtRatioAtTick(tick_upper);  
    return sqrtPriceX96 > sqrtRatioAX96 && sqrtPriceX96 < sqrtRatioBX96;
  }


  function _readRebalanceProportion(
    int24 _tickLower,
    int24 _tickUpper
  )
    internal
    view
    returns (
      uint256,
      address,
      address
    )
  {
    Proportion memory _cache;

    _cache.amount0Desired = token0.balanceOf(address(this));
    _cache.amount1Desired = token1.balanceOf(address(this));
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();


    _cache.liquidity = uniswapCalculator.liquidityForAmounts(
      sqrtRatioX96,
      _cache.amount0Desired,
      _cache.amount1Desired,
      _tickLower,
      _tickUpper
    );


    (_cache.amount0, _cache.amount1) = uniswapCalculator.amountsForLiquidity(
      sqrtRatioX96,
      _cache.liquidity,
      _tickLower,
      _tickUpper
    );


    bool _zeroForOne;
    if (_cache.amount1Desired == 0) {
      _zeroForOne = true;
    } else {
      _zeroForOne = _amountsDirection(_cache.amount0Desired, _cache.amount1Desired, _cache.amount0, _cache.amount1);
    }


    uint160 sqrtRatioAX96 = uniswapCalculator.getSqrtRatioAtTick(_tickLower);
    uint160 sqrtRatioBX96 = uniswapCalculator.getSqrtRatioAtTick(_tickUpper);    
    uint256 amt0;
    uint256 amt1;
    if (_zeroForOne == true) {
    amt0 = _cache.amount0Desired - _cache.amount0;
    _cache.liquidity = uniswapCalculator.getLiquidityForAmount0(
      sqrtRatioAX96,
      sqrtRatioBX96,
      amt0
    );
    } else {
    amt1 = _cache.amount1Desired - _cache.amount1;
    _cache.liquidity = uniswapCalculator.getLiquidityForAmount1(
      sqrtRatioAX96,
      sqrtRatioBX96,
      amt1
    );
    }

    (_cache.amount0, _cache.amount1) = uniswapCalculator.amountsForLiquidity(
      sqrtRatioX96,
      _cache.liquidity,
      _tickLower,
      _tickUpper
    );

    uint256 _amountSpecified = _zeroForOne
      ? (amt0 - _cache.amount0)
      : (amt1 - _cache.amount1);

    address _inputToken = _zeroForOne ? address(token0) : address(token1);
    address _outputToken = _zeroForOne ? address(token1) : address(token0);
    return (_amountSpecified, _inputToken, _outputToken);

  }

  function _balanceProportion(
    int24 _tickLower,
    int24 _tickUpper
  ) internal returns (uint256){
    (uint256 _amountSpecified, address _inputToken, address _outputToken) = _readRebalanceProportion(
      _tickLower,
      _tickUpper
    );

    if (_amountSpecified > amtSpecified) {
      ISwapRouter(univ3Router).exactInputSingle(
        ISwapRouter.ExactInputSingleParams({
          tokenIn: _inputToken,
          tokenOut: _outputToken,
          fee: pool.fee(),
          recipient: address(this),
          deadline: block.timestamp,
          amountIn: _amountSpecified,
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
        })
      );
    }
    if (token0.balanceOf(address(this)) >= amtSpecified && token1.balanceOf(address(this)) >= amtSpecified) {
      return 1;
    }
    else {
      return 0;
    }
  }
    function deployCalculator() private {
        bytes memory bytecode = abi.encodePacked(hex"608060405234801561001057600080fd5b50611c42806100206000396000f3fe608060405234801561001057600080fd5b50600436106100a95760003560e01c806387aa64f71161007157806387aa64f714610387578063986cfba3146103e2578063a747b93b1461043d578063c5f266301461049c578063c72e160b1461059e578063e963af7314610659576100a9565b8063058421ca146100ae57806308c0f795146101095780632064ab9e1461019d5780636098fd4a1461023557806367df6e89146102f3575b600080fd5b6100dd600480360360208110156100c457600080fd5b81019080803560020b90602001909291905050506106ee565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6101756004803603606081101561011f57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050610700565b60405180826fffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b61020d600480360360a08110156101b357600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019092919080359060200190929190803560020b9060200190929190803560020b9060200190929190505050610716565b60405180826fffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6102cb600480360360a081101561024b57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019092919080359060200190929190505050610740565b60405180826fffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b61035f6004803603606081101561030957600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019092919050505061075a565b60405180826fffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6103c96004803603602081101561039d57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610770565b604051808260020b815260200191505060405180910390f35b610411600480360360208110156103f857600080fd5b81019080803560020b9060200190929190505050610782565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b61047f6004803603602081101561045357600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610794565b604051808381526020018281526020019250505060405180910390f35b61057b600480360360808110156104b257600080fd5b81019080803590602001906401000000008111156104cf57600080fd5b8201836020820111156104e157600080fd5b8035906020019184602083028401116401000000008311171561050357600080fd5b919080806020026020016040519081016040528093929190818152602001838360200280828437600081840152601f19601f820116905080830192505050505050509192919290803560020b9060200190929190803560020b9060200190929190803562ffffff169060200190929190505050610c14565b604051808360020b81526020018260020b81526020019250505060405180910390f35b61063c600480360360808110156105b457600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080356fffffffffffffffffffffffffffffffff169060200190929190505050610c78565b604051808381526020018281526020019250505060405180910390f35b6106d16004803603608081101561066f57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080356fffffffffffffffffffffffffffffffff169060200190929190803560020b9060200190929190803560020b9060200190929190505050610c94565b604051808381526020018281526020019250505060405180910390f35b60006106f982610cc0565b9050919050565b600061070d8484846110fb565b90509392505050565b60006107358661072585610cc0565b61072e85610cc0565b888861117d565b905095945050505050565b600061074f868686868661117d565b905095945050505050565b60006107678484846112a9565b90509392505050565b600061077b82611367565b9050919050565b600061078d82610cc0565b9050919050565b60008060008373ffffffffffffffffffffffffffffffffffffffff166316f0115b6040518163ffffffff1660e01b815260040160206040518083038186803b1580156107df57600080fd5b505afa1580156107f3573d6000803e3d6000fd5b505050506040513d602081101561080957600080fd5b8101908080519060200190929190505050905060008473ffffffffffffffffffffffffffffffffffffffff1663ef27c8536040518163ffffffff1660e01b815260040160206040518083038186803b15801561086457600080fd5b505afa158015610878573d6000803e3d6000fd5b505050506040513d602081101561088e57600080fd5b8101908080519060200190929190505050905060008573ffffffffffffffffffffffffffffffffffffffff16631d7c56606040518163ffffffff1660e01b815260040160206040518083038186803b1580156108e957600080fd5b505afa1580156108fd573d6000803e3d6000fd5b505050506040513d602081101561091357600080fd5b8101908080519060200190929190505050905060008673ffffffffffffffffffffffffffffffffffffffff1663a9c472b26040518163ffffffff1660e01b815260040160206040518083038186803b15801561096e57600080fd5b505afa158015610982573d6000803e3d6000fd5b505050506040513d602081101561099857600080fd5b810190808051906020019092919050505090506109b784828585611763565b80965081975050508373ffffffffffffffffffffffffffffffffffffffff16630dfe16816040518163ffffffff1660e01b815260040160206040518083038186803b158015610a0557600080fd5b505afa158015610a19573d6000803e3d6000fd5b505050506040513d6020811015610a2f57600080fd5b810190808051906020019092919050505073ffffffffffffffffffffffffffffffffffffffff166370a08231886040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b158015610aa657600080fd5b505afa158015610aba573d6000803e3d6000fd5b505050506040513d6020811015610ad057600080fd5b8101908080519060200190929190505050860195508373ffffffffffffffffffffffffffffffffffffffff1663d21220a76040518163ffffffff1660e01b815260040160206040518083038186803b158015610b2b57600080fd5b505afa158015610b3f573d6000803e3d6000fd5b505050506040513d6020811015610b5557600080fd5b810190808051906020019092919050505073ffffffffffffffffffffffffffffffffffffffff166370a08231886040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b158015610bcc57600080fd5b505afa158015610be0573d6000803e3d6000fd5b505050506040513d6020811015610bf657600080fd5b81019080805190602001909291905050508501945050505050915091565b60008060008362ffffff1687600081518110610c2c57fe5b602002602001015188600181518110610c4157fe5b60200260200101510360060b81610c5457fe5b05905060008587029050610c69828289611857565b93509350505094509492505050565b600080610c878686868661187b565b9150915094509492505050565b600080610cb386610ca486610cc0565b610cad86610cc0565b8861187b565b9150915094509492505050565b60008060008360020b12610cd7578260020b610cdf565b8260020b6000035b90507ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff2761860000360020b811115610d7d576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260018152602001807f540000000000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600080600183161415610da157700100000000000000000000000000000000610db3565b6ffffcb933bd6fad37aa2d162d1a5940015b70ffffffffffffffffffffffffffffffffff16905060006002831614610ded5760806ffff97272373d413259a46990580e213a8202901c90505b60006004831614610e125760806ffff2e50f5f656932ef12357cf3c7fdcc8202901c90505b60006008831614610e375760806fffe5caca7e10e4e61c3624eaa0941cd08202901c90505b60006010831614610e5c5760806fffcb9843d60f6159c9db58835c9266448202901c90505b60006020831614610e815760806fff973b41fa98c081472e6896dfb254c08202901c90505b60006040831614610ea65760806fff2ea16466c96a3843ec78b326b528618202901c90505b60006080831614610ecb5760806ffe5dee046a99a2a811c461f1969c30538202901c90505b6000610100831614610ef15760806ffcbe86c7900a88aedcffc83b479aa3a48202901c90505b6000610200831614610f175760806ff987a7253ac413176f2b074cf7815e548202901c90505b6000610400831614610f3d5760806ff3392b0822b70005940c7a398e4b70f38202901c90505b6000610800831614610f635760806fe7159475a2c29b7443b29c7fa6e889d98202901c90505b6000611000831614610f895760806fd097f3bdfd2022b8845ad8f792aa58258202901c90505b6000612000831614610faf5760806fa9f746462d870fdf8a65dc1f90e061e58202901c90505b6000614000831614610fd55760806f70d869a156d2a1b890bb3df62baf32f78202901c90505b6000618000831614610ffb5760806f31be135f97d08fd981231505542fcfa68202901c90505b6000620100008316146110225760806f09aa508b5b7a84e1c677de54f3e99bc98202901c90505b6000620200008316146110485760806e5d6af8dedb81196699c329225ee6048202901c90505b60006204000083161461106d5760806d2216e584f5fa1ea926041bedfe988202901c90505b6000620800008316146110905760806b048a170391f7dc42444e8fa28202901c90505b60008460020b13156110c957807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff816110c557fe5b0490505b600064010000000082816110d957fe5b06146110e65760016110e9565b60005b60ff16602082901c0192505050919050565b60008273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff16111561113c57828480945081955050505b61117461116f836c0100000000000000000000000087870373ffffffffffffffffffffffffffffffffffffffff1661196d565b611a47565b90509392505050565b60008373ffffffffffffffffffffffffffffffffffffffff168573ffffffffffffffffffffffffffffffffffffffff1611156111be57838580955081965050505b8473ffffffffffffffffffffffffffffffffffffffff168673ffffffffffffffffffffffffffffffffffffffff1611611203576111fc8585856112a9565b90506112a0565b8373ffffffffffffffffffffffffffffffffffffffff168673ffffffffffffffffffffffffffffffffffffffff1610156112915760006112448786866112a9565b905060006112538789866110fb565b9050806fffffffffffffffffffffffffffffffff16826fffffffffffffffffffffffffffffffff16106112865780611288565b815b9250505061129f565b61129c8585846110fb565b90505b5b95945050505050565b60008273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff1611156112ea57828480945081955050505b60006113308573ffffffffffffffffffffffffffffffffffffffff168573ffffffffffffffffffffffffffffffffffffffff166c0100000000000000000000000061196d565b905061135d611358848388880373ffffffffffffffffffffffffffffffffffffffff1661196d565b611a47565b9150509392505050565b60006401000276a373ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff16101580156113e9575073fffd8963efd1fc6a506488495d951d5263988d2673ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff16105b61145b576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260018152602001807f520000000000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600060208373ffffffffffffffffffffffffffffffffffffffff16901b9050600081905060006fffffffffffffffffffffffffffffffff821160071b808217915082811c92505067ffffffffffffffff821160061b808217915082811c92505063ffffffff821160051b808217915082811c92505061ffff821160041b808217915082811c92505060ff821160031b808217915082811c925050600f821160021b808217915082811c9250506003821160011b808217915082811c925050600182118082179150506080811061153957607f810383901c9150611543565b80607f0383901b91505b6000604060808303901b9050828302607f1c92508260801c80603f1b8217915083811c935050828302607f1c92508260801c80603e1b8217915083811c935050828302607f1c92508260801c80603d1b8217915083811c935050828302607f1c92508260801c80603c1b8217915083811c935050828302607f1c92508260801c80603b1b8217915083811c935050828302607f1c92508260801c80603a1b8217915083811c935050828302607f1c92508260801c8060391b8217915083811c935050828302607f1c92508260801c8060381b8217915083811c935050828302607f1c92508260801c8060371b8217915083811c935050828302607f1c92508260801c8060361b8217915083811c935050828302607f1c92508260801c8060351b8217915083811c935050828302607f1c92508260801c8060341b8217915083811c935050828302607f1c92508260801c8060331b8217915083811c935050828302607f1c92508260801c8060321b82179150506000693627a301d71055774c8582029050600060806f028f6481ab7f045a5af012a19d003aaa8303901d9050600060806fdb2df09e81959a81455e260799a0632f8401901d90508060020b8260020b14611753578873ffffffffffffffffffffffffffffffffffffffff1661172a82610cc0565b73ffffffffffffffffffffffffffffffffffffffff16111561174c578161174e565b805b611755565b815b975050505050505050919050565b60008060008673ffffffffffffffffffffffffffffffffffffffff16633850c7bd6040518163ffffffff1660e01b815260040160e06040518083038186803b1580156117ae57600080fd5b505afa1580156117c2573d6000803e3d6000fd5b505050506040513d60e08110156117d857600080fd5b810190808051906020019092919080519060200190929190805190602001909291908051906020019092919080519060200190929190805190602001909291908051906020019092919050505050505050505090506118498161183a87610cc0565b61184387610cc0565b8961187b565b925092505094509492505050565b60008060006118668685611a6f565b90508481039250848101915050935093915050565b6000808373ffffffffffffffffffffffffffffffffffffffff168573ffffffffffffffffffffffffffffffffffffffff1611156118bd57838580955081965050505b8473ffffffffffffffffffffffffffffffffffffffff168673ffffffffffffffffffffffffffffffffffffffff1611611902576118fb858585611ac5565b9150611964565b8373ffffffffffffffffffffffffffffffffffffffff168673ffffffffffffffffffffffffffffffffffffffff16101561195557611941868585611ac5565b915061194e858785611b80565b9050611963565b611960858585611b80565b90505b5b94509492505050565b6000806000801985870985870292508281108382030391505060008114156119a8576000841161199c57600080fd5b83820492505050611a40565b8084116119b457600080fd5b600084868809905082811182039150808303925060008586600003169050808604955080840493506001818260000304019050808302841793506000600287600302189050808702600203810290508087026002038102905080870260020381029050808702600203810290508087026002038102905080870260020381029050808502955050505050505b9392505050565b600081829150816fffffffffffffffffffffffffffffffff1614611a6a57600080fd5b919050565b6000808260020b8460020b81611a8157fe5b05905060008460020b128015611aaa575060008360020b8560020b81611aa357fe5b0760020b14155b15611ab9578080600190039150505b82810291505092915050565b60008273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff161115611b0657828480945081955050505b8373ffffffffffffffffffffffffffffffffffffffff16611b6f606060ff16846fffffffffffffffffffffffffffffffff16901b86860373ffffffffffffffffffffffffffffffffffffffff168673ffffffffffffffffffffffffffffffffffffffff1661196d565b81611b7657fe5b0490509392505050565b60008273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff161115611bc157828480945081955050505b611c03826fffffffffffffffffffffffffffffffff1685850373ffffffffffffffffffffffffffffffffffffffff166c0100000000000000000000000061196d565b9050939250505056fea26469706673582212206c30dcc159c7189d7d4b3cc4c887573511c5ec97f6f9801bb3b8043f200a743164736f6c63430007060033", abi.encode(msg.sender));

        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        uniswapCalculator = IUniswapCalculator(addr);
    }
}