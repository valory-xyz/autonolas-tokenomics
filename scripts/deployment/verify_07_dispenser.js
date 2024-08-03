const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
const treasuryAddress = parsedData.treasuryAddress;
const olasAddress = parsedData.olasAddress;
const voteWeightingAddress = parsedData.voteWeightingAddress;
const retainerAddress = parsedData.retainerAddress;
const maxNumClaimingEpochs = parsedData.maxNumClaimingEpochs;
const maxNumStakingTargets = parsedData.maxNumStakingTargets;
const minStakingWeight = parsedData.minStakingWeight;
const maxStakingIncentive = parsedData.maxStakingIncentive;

module.exports = [
    olasAddress,
    tokenomicsProxyAddress,
    treasuryAddress,
    voteWeightingAddress,
    retainerAddress,
    maxNumClaimingEpochs,
    maxNumStakingTargets,
    minStakingWeight,
    maxStakingIncentive
];