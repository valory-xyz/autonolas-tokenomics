#!/bin/bash
# Original Uniswap V2Pair patching
FILE="node_modules/@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol"
x=$(npx hardhat run scripts/uni-adjust/adjust.js)
case "$(uname -s)" in
   Darwin)
     sed -i.bu "s/96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f/$x/g" $FILE
     ;;

   Linux)
     sed -i "s/96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f/$x/g" $FILE
     ;;

   *)
     echo 'Other OS' 
     ;;
esac

