#!/bin/bash
FILE="./node_modules/@uniswap/lib/contracts/libraries/BitMath.sol"
case "$(uname -s)" in
   Darwin)
     echo 'Mac OS X'
     sed -i.bu "s/uint128(-1)/type(uint128).max/g" $FILE
     sed -i.bu "s/uint64(-1)/type(uint64).max/g" $FILE
     sed -i.bu "s/uint32(-1)/type(uint32).max/g" $FILE
     sed -i.bu "s/uint16(-1)/type(uint16).max/g" $FILE
     sed -i.bu "s/uint8(-1)/type(uint8).max/g" $FILE 
     ;;

   Linux)
     echo 'Linux'
     sed -i "s/uint128(-1)/type(uint128).max/g" $FILE                                      
     sed -i "s/uint64(-1)/type(uint64).max/g" $FILE   
     sed -i "s/uint32(-1)/type(uint32).max/g" $FILE
     sed -i "s/uint16(-1)/type(uint16).max/g" $FILE
     sed -i "s/uint8(-1)/type(uint8).max/g" $FILE 
     ;;

   *)
     echo 'Other OS'
     ;;
esac

FILE="./node_modules/@uniswap/lib/contracts/libraries/FixedPoint.sol"
case "$(uname -s)" in
   Darwin)
     echo 'Mac OS X'
     sed -i.bu "s/uint112(-1)/type(uint112).max/g" $FILE
     sed -i.bu "s/uint224(-1)/type(uint224).max/g" $FILE
     sed -i.bu "s/uint144(-1)/type(uint144).max/g" $FILE
     ;;

   Linux)
     echo 'Linux'
     sed -i "s/uint112(-1)/type(uint112).max/g" $FILE
     sed -i "s/uint224(-1)/type(uint224).max/g" $FILE
     sed -i "s/uint144(-1)/type(uint144).max/g" $FILE
     ;;

   *)
     echo 'Other OS'
     ;;
esac

FILE="./node_modules/@uniswap/lib/contracts/libraries/FullMath.sol"
case "$(uname -s)" in
   Darwin)
     echo 'Mac OS X'
     sed -i.bu "s/uint256(-1)/type(uint256).max/g" $FILE
     sed -i.bu "s/-d/(~d+1)/g" $FILE
     sed -i.bu "s/(-pow2)/(~pow2+1)/g" $FILE
     ;;

   Linux)
     echo 'Linux'
     sed -i.bu "s/uint256(-1)/type(uint256).max/g" $FILE
     sed -i.bu "s/-d/(~d+1)/g" $FILE                                      
     sed -i.bu "s/(-pow2)/(~pow2+1)/g" $FILE  
     ;;

   *)
     echo 'Other OS'
     ;;
esac
