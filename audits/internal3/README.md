# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `4e5f57f192c54ed7c8572159d20e1a5d79cdd4d0` or `v1.0.2.pre-internal-audi`<br> 

## Objectives
The audit focused on changes in Depository contract in this repo.

## Flatten version
```bash
surya flatten Depository.sol > ../audits/internal3/analysis/contracts/Depository.sol
```

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
sol2uml storage contracts/ -f png -c Depository -o audits/internal3/analysis/storage         
Generated png file /home/andrey/valory/autonolas-tokenomics/audits/internal3/analysis/storage/Depository.png
```
New `Depository` does not depend on the previous implementation of the `Depository` and does not "share" a common storage. <br>
OK.

### Test issue
```bash
foundryup: installed - forge 0.2.0 (114e69d 2023-07-25T11:33:13.343757341Z)
foundryup: installed - cast 0.2.0 (114e69d 2023-07-25T11:33:13.343757341Z)
foundryup: installed - anvil 0.1.0 (114e69d 2023-07-25T11:34:03.828754696Z)
foundryup: installed - chisel 0.1.0 (114e69d 2023-07-25T11:34:03.832976273Z)

forge test --hh -vv                        
[⠊] Compiling...
[⠆] Installing solc version 0.8.21
[⠒] Successfully installed solc 0.8.21
[⠒] Installing solc version 0.8.20
[⠊] Successfully installed solc 0.8.20
[⠒] Compiling 11 files with 0.6.6
[⠢] Compiling 13 files with 0.5.16
[⠆] Compiling 75 files with 0.8.20
[⠊] Compiling 77 files with 0.8.21
[⠰] Solc 0.5.16 finished in 658.32ms
[⠔] Solc 0.6.6 finished in 923.66ms
[⠘] Solc 0.8.21 finished in 6.98s
[⠒] Solc 0.8.20 finished in 8.19s
Compiler run successful!
The application panicked (crashed).
Message:  No artifact for contract lib/zuniswapv2/src/ZuniswapV2Library.sol:ZuniswapV2Library
Location: /home/runner/work/foundry/foundry/utils/src/lib.rs:288

This is a bug. Consider reporting it at https://github.com/foundry-rs/foundry
Ref:
https://github.com/foundry-rs/foundry/issues/5396

Solution: As workaround failback to
https://github.com/foundry-rs/foundry/releases/tag/nightly-cc5637a979050c39b3d06bc4cc6134f0591ee8d0
mkdir t
cd t
wget https://github.com/foundry-rs/foundry/releases/download/nightly-cc5637a979050c39b3d06bc4cc6134f0591ee8d0/foundry_nightly_linux_amd64.tar.gz
tar -xvzf  foundry_nightly_linux_amd64.tar.gz 
cd ..
./t/forge test --hh -vv
[⠢] Compiling...
[⠰] Installing solc version 0.8.21
[⠃] Successfully installed solc 0.8.21
No files changed, compilation skipped

Running 1 test for test/Treasury.t.sol:TreasuryTest
[PASS] testAmount() (gas: 162523)
Test result: ok. 1 passed; 0 failed; finished in 3.45ms

Running 3 tests for test/Depository.t.sol:DepositoryTest
[PASS] testCreateDepositRedeemClose() (gas: 215859)
[PASS] testCreateProduct() (gas: 121371)
[PASS] testDeposit() (gas: 205719)
Test result: ok. 3 passed; 0 failed; finished in 4.36ms

Running 3 tests for test/Dispenser.t.sol:DispenserTest
[PASS] testIncentives(uint64,uint64) (runs: 256, μ: 716879, ~: 716890)
[PASS] testIncentivesLoopDirect(uint64,uint64) (runs: 256, μ: 15706259, ~: 15705243)
[PASS] testIncentivesLoopEvenOdd(uint64,uint64) (runs: 256, μ: 5990193, ~: 5990193)
Test result: ok. 3 passed; 0 failed; finished in 14.42s
```
[x] fixed

### Security issues.
#### Instrumental analysis
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal3/analysis/slither_full.txt) <br>
All false positives. <br>

Minor issue: <br>
- address public OLAS can be made a constant. you may not do it. <br>
- Add version. To distinguish between contracts explicitly. <br>
[x] fixed

#### Notes
```bash
scribble contracts/Depository.sol --output-mode files --arm 
Compile errors encountered:
SolcJS 0.8.19:
ParserError: Source file requires different compiler version (current compiler is 0.8.19+commit.7dd6d404.Linux.g++) - note that nightly builds are considered to be strictly less than the released version
 --> contracts/Depository.sol:2:1:
  |
2 | pragma solidity ^0.8.20;
  | ^^^^^^^^^^^^^^^^^^^^^^^^
This tool requires a non-trivial hack to work with multiple and modern versions of Solidity.
It is proposed to use forge or echidna.
```
[x] Ran foundry tests in this repository and [autonolas-v1](https://github.com/valory-xyz/autonolas-v1).


### Update 26-07-23.
Update between `b512b7c8728cbf98472ee622c0f72689fc6d9851` - `05d3af5bd557b735bd626b96d6c89e048b781b37` added no bugs in codebase. <br>
All fixes did not change the code execution logic and are equivalent. <br>

