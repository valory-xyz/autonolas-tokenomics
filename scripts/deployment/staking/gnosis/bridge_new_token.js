/*global process*/

const main = async () => {
    // Approve bridged token for the transfer amount
    // Call relayTokens function from the OmniBridge contract to initiate a deployment
    // Reference: https://docs.gnosischain.com/bridges/Token%20Bridge/omnibridge
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
