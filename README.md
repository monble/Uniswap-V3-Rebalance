### Uniswap V3 Rebalance - service for automatic profit generation from LP Uniswap V3
You can rebalancing any CLAMM Uniswap V3 position using this smart-contract. You send one of the tokens to the contract balance, set up the desired pool and can take the current tick from slot0() to track the status of the position. You can also view whether a position is out of range or not using the inRange() function.
### Local deployment and Usage
Install Foundry
```
https://book.getfoundry.sh/
```
To utilize the contracts and deploy to a local testnet, you can install the code in your repo with forge:
```
forge install https://github.com/monble/UniswapV3Rebalance/
```
You can manage tests in ..src/Rebalance.t.sol
```solidity
    import {Test, console} from "forge-std/Test.sol";
    import {Rebalance} from "src/Rebalance.sol";
    import {IERC20} from "src/additions/erc20.sol";
    
    contract RebalanceTest is Test {
        Rebalance public rebalance;
    
        function setUp() public {
            rebalance = new Rebalance();
            rebalance.initialize();
        }
    
        function test_UniswapCalculator() public view {
        (,,,int24 tickNow, bool inRange) = rebalance.slot0();
        assertNotEq(tickNow, 0);
        assertEq(inRange,false);
        }
    
        function test_Rebalance() public {
            deal(address(rebalance.token1()), address(this), 1 ether);
            IERC20(rebalance.token1()).transfer(address(rebalance), 1 ether);
            assertEq(IERC20(rebalance.token1()).balanceOf(address(rebalance)), 1 ether);
    
            (,,,int24 tickNow,) = rebalance.slot0();
            tickNow = tickNow - tickNow % 10;
            rebalance.rebalance(tickNow - 1000, tickNow + 1000);
    
            (,,,tickNow,) = rebalance.slot0();
            tickNow = tickNow - tickNow % 10;
            rebalance.rebalance(tickNow - 300, tickNow + 700);
    
            (,,,tickNow,) = rebalance.slot0();
            tickNow = tickNow - tickNow % 10;
            rebalance.withdraw(tickNow - 10, tickNow + 10);
        }
    
    
        function test_ChangePool() public {
            rebalance.setPool(0x85C31FFA3706d1cce9d525a00f1C7D4A2911754c, 1000 gwei);
            assertEq(address(rebalance.token1()),0x68f180fcCe6836688e9084f035309E29Bf0A2095);
        }
    }
```
To run tests you need to use a fork of the OP Mainnet network
Run in terminal: 
```
forge test --fork-url https://rpc.ankr.com/optimism -vvvv
```
### Settings
You can change settings in ..src/Rebalance.sol
```solidity
address public constant univ3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
address public constant oneinch = 0x1111111254EEB25477B68fb85Ed929f73A960582;
IUniswapV3PositionsNFT public constant nftManager = IUniswapV3PositionsNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
IUniswapV3Pool public pool = IUniswapV3Pool(0x1fb3cf6e48F1E7B10213E7b6d87D4c073C7Fdb7b);
```

### Action List
1. Change the values of pool, nftManager, univ3Router addresses
2. Deploy smart-contract on any EVM network with Solidity compiler version 0.8.13
3. Call initialize() function
4. Send one of tokens to Rebalance contract.
5. Get tickNow from slot() Rebalance
6. Call rebalance(tickLower, tickUpper) where tickLower may be = tickNow - 500 and tickUpper may be = tickNow + 500
7. Call withdraw(tickLower, tickUpper) where tickLower may be = tickNow - 500 and tickUpper may be = tickNow + 500M
