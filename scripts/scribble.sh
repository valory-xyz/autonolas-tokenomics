#!/bin/bash

scribble contracts/$1 --output-mode files --arm 
npx hardhat test
scribble contracts/$1 --disarm
