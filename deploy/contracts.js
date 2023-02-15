/*global ethers*/

const { expect } = require("chai");

module.exports = async () => {
    const signers = await ethers.getSigners();
    const deployer = signers[0];

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
    };

    // Write the setup json file
    const initDeployFile = "initDeploy.json";
    const fs = require("fs");
    fs.writeFileSync(initDeployFile, JSON.stringify(initDeployJSON));
};
