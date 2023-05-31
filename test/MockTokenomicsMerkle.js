/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");

describe("Tokenomics Merkle", async () => {
    const defaultHashIPSF = "0x" + "0".repeat(64);
    let tokenomicsMerkle;

    // These should not be in beforeEach.
    beforeEach(async () => {
        const TokenomicsMerkle = await ethers.getContractFactory("MockTokenomicsMerkle");
        tokenomicsMerkle = await TokenomicsMerkle.deploy();
        await tokenomicsMerkle.deployed();
    });

    context("Merkle proofs", async function () {
        it("Donate and claim", async function () {
            const donate = [[1, 100], [2, 200], [3, 300]];

            const merkleTree = StandardMerkleTree.of(donate, ["uint256", "uint256"]);

            // Make a donation
            let donationAmount = 0;
            for (let i = 0; i < donate.length; i++) {
                donationAmount += donate[i][1];
            }
            const roundId = await tokenomicsMerkle.callStatic.donate(merkleTree.root, defaultHashIPSF, {value: donationAmount});
            await tokenomicsMerkle.donate(merkleTree.root, defaultHashIPSF, {value: donationAmount});

            // Claim for unit 1 and 2
            const proofStruct = merkleTree.getMultiProof([0, 1]);

            const unitIds = [donate[0][0], donate[1][0]];
            const amounts = [donate[0][1], donate[1][1]];
            const multiProof = {merkleProof: proofStruct.proof, proofFlags: proofStruct.proofFlags};
            await tokenomicsMerkle.claim(roundId, unitIds, amounts, multiProof);

            // Try to claim same amounts again
            await expect(
                tokenomicsMerkle.claim(roundId, unitIds, amounts, multiProof)
            ).to.be.revertedWithCustomError(tokenomicsMerkle, "AlreadyClaimed");
        });

        it("Donate less and try to claim more", async function () {
            const donate = [[1, 100], [2, 200], [3, 300]];

            const merkleTree = StandardMerkleTree.of(donate, ["uint256", "uint256"]);

            // Make a donation
            const roundId = await tokenomicsMerkle.callStatic.donate(merkleTree.root, defaultHashIPSF, {value: 1});
            await tokenomicsMerkle.donate(merkleTree.root, defaultHashIPSF, {value: 1});

            // Try to claim for unit 1 and 2
            const proofStruct = merkleTree.getMultiProof([0, 1]);

            const unitIds = [donate[0][0], donate[1][0]];
            const amounts = [donate[0][1], donate[1][1]];
            const multiProof = {merkleProof: proofStruct.proof, proofFlags: proofStruct.proofFlags};
            await expect(
                tokenomicsMerkle.claim(roundId, unitIds, amounts, multiProof)
            ).to.be.revertedWithCustomError(tokenomicsMerkle, "InsufficientBalance");
        });

        it("Donate and try to claim with wrong proofs", async function () {
            const donations = [[[1, 100], [2, 200], [3, 300]], [[1, 600], [2, 500], [3, 400]]];

            const merkleTrees = new Array();
            merkleTrees.push(StandardMerkleTree.of(donations[0], ["uint256", "uint256"]));
            merkleTrees.push(StandardMerkleTree.of(donations[1], ["uint256", "uint256"]));

            // Make two donations
            const donationAmounts = new Array(2).fill(0);
            for (let j = 0; j < donations.length; j++) {
                for (let i = 0; i < donations[j].length; i++) {
                    donationAmounts[j] += donations[j][i][1];
                }
            }
            const roundIds = [0, 1];
            await tokenomicsMerkle.donate(merkleTrees[0].root, defaultHashIPSF, {value: donationAmounts[0]});
            await tokenomicsMerkle.donate(merkleTrees[1].root, defaultHashIPSF, {value: donationAmounts[1]});

            // Try to claim for unit 1 and 2
            const proofStructs = [merkleTrees[0].getMultiProof([0, 1]), merkleTrees[1].getMultiProof([0, 1])];

            const unitIds = [[donations[0][0][0], donations[0][1][0]], [donations[1][0][0], donations[1][1][0]]];
            const amounts = [[donations[0][0][1], donations[0][1][1]], [donations[1][0][1], donations[1][1][1]]];
            const multiProofs = [{merkleProof: proofStructs[0].proof, proofFlags: proofStructs[0].proofFlags},
                {merkleProof: proofStructs[1].proof, proofFlags: proofStructs[1].proofFlags}];

            // Try to claim from different rounds
            await expect(
                tokenomicsMerkle.claim(roundIds[1], unitIds[0], amounts[0], multiProofs[0])
            ).to.be.revertedWithCustomError(tokenomicsMerkle, "ClaimProofFailed");
            await expect(
                tokenomicsMerkle.claim(roundIds[0], unitIds[1], amounts[1], multiProofs[1])
            ).to.be.revertedWithCustomError(tokenomicsMerkle, "ClaimProofFailed");

            // Claim with correct proofs
            await tokenomicsMerkle.claim(roundIds[0], unitIds[0], amounts[0], multiProofs[0]);
            await tokenomicsMerkle.claim(roundIds[1], unitIds[1], amounts[1], multiProofs[1]);
        });
    });
});
