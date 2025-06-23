# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `4d543af4efefea0380a1c5b1d79f5e574b4c26f0` or `tag: v1.3.3-pre-internal-audit`<br> 

## Objectives
The audit focused on WithheldAmount fix in TargetDispenserL2 contract

## Issue
### Medium. Logical issue
```
This is not a bug in the current code.
However, the essence of the fix is ​​in conflict with this: 
function syncWithheldAmount(bytes memory bridgePayload) external payable {}
In the current code, anyone can execute it.
It zeroid withheldAmount = amount - normalizedAmount;
They need to be given equal rights (OwnerOnly).
To discussion!
```
[] 
