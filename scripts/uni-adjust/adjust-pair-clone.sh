#!/bin/bash
# Uniswap clone patching
FILE="lib/zuniswapv2/src/ZuniswapV2Pair.sol"
case "$(uname -s)" in
   Darwin)
     sed -i.bu "s/\"solmate/\"..\/lib\/solmate\/src/g" $FILE
     ;;

   Linux)
     sed -i "s/\"solmate/\"..\/lib\/solmate\/src/g" $FILE
     ;;

   *)
     echo 'Other OS'
     ;;
esac

