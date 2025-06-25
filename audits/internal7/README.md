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
[x] Fixed 

## Re-audit 25.06.25
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `d4de5d273bc9ce9ff652f1734c8822c3954e6090` or `tag: v1.3.3-pre-internal-audit`<br>

## Issue
### Notes/Question
```
processDataMaintenance(bytes memory data, bool updateWithheldAmount) 
let updateWithheldAmount == true
->
_processData(data);
->
uint256 localWithheldAmount = 0;
if (limitAmount == 0) {
                // Withhold OLAS for further usage
                localWithheldAmount += amount;
..
localWithheldAmount += targetWithheldAmount;
        // Adjust withheld amount, if at least one target has not passed the validity check
        if (localWithheldAmount > 0) {
            withheldAmount += localWithheldAmount;
        }
 // Update total to-be-deposited amount
            totalAmount += amount;
-> back to processDataMaintenance
            // Update withheld amount
            localWithheldAmount -= totalAmount;
            withheldAmount = localWithheldAmount;
Is there a source of some discrepancy here? It turns out that we are erasing (minus) what adjust at `_processData`
Please, double check logic.
```
[x] Fixed 


