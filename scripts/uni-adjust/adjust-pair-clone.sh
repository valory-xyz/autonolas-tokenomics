#!/bin/bash
# Uniswap clone patching
cp lib/zuniswapv2/lib/solmate/src/tokens/ERC20.sol lib/zuniswapv2/lib/solmate/src/tokens/SERC20.sol
FILE="lib/zuniswapv2/lib/solmate/src/tokens/SERC20.sol"
case "$(uname -s)" in
   Darwin)
     sed -i.bu "s/ERC20/SERC20/g" $FILE
     ;;

   Linux)
     sed -i "s/ERC20/SERC20/g" $FILE
     ;;

   *)
     echo 'Other OS'
     ;;
esac

FILE="lib/zuniswapv2/src/ZuniswapV2Pair.sol"
case "$(uname -s)" in
   Darwin)
     sed -i.bu "s/\"solmate/\"..\/lib\/solmate\/src/g" $FILE
     sed -i.bu "s/ERC20/SERC20/g" $FILE
     sed -i.bu "s/IERC20/ISERC20/g" $FILE
     ;;

   Linux)
     sed -i "s/\"solmate/\"..\/lib\/solmate\/src/g" $FILE
     ;;

   *)
     echo 'Other OS'
     ;;
esac

