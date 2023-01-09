#!/bin/bash
# Real Uniswap
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

# Uniswap simulation
FILE="lib/unifap-v2/src/UnifapV2Pair.sol"
x=$(npx hardhat run scripts/uni-adjust/adjust.js)
case "$(uname -s)" in
   Darwin)
     sed -i.bu "s/d1d193543731c8e1f46834a814b5cba11190896c4b5256f84588a284db998d60/$x/g" $FILE
     ;;

   Linux)
     sed -i "s/d1d193543731c8e1f46834a814b5cba11190896c4b5256f84588a284db998d60/$x/g" $FILE
     ;;

   *)
     echo 'Other OS'
     ;;
esac

