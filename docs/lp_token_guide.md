# LP Token Guide
## UniswapV2
To illustrate the mechanism, the well-known DAI / wETH pair is used: https://app.zerion.io/tokens/UNI-V2-0xa478c2975ab1ea89e8196811f51a7b7ade33eb11

That LP token has the following address: `0xa478c2975ab1ea89e8196811f51a7b7ade33eb11`.

- Get a description of what is inside the LP token pool, one of the tokens has to be [OLAS](https://etherscan.io/address/0x0001A500A6B18995B03f44bb040A5fFc28E45CB0).
  In this example, we consider DAI in place of OLAS. DAI token has the following address: `0x6B175474E89094C44Da98b954EedeAC495271d0F`.
- Open an ETH explorer in a chosen network (here the ETH mainnet is used): https://etherscan.io/token/0xa478c2975ab1ea89e8196811f51a7b7ade33eb11#readContract
  - Read the output of methods `token0()`, `token1()`:
    - `token0: 0x6B175474E89094C44Da98b954EedeAC495271d0F`,
    - `token1: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`.
    In the example, these addresses are DAI and wETH addresses. In the case of OLAS-wETH LP token, these addresses have to match with OLAS and wETH addresses.
- Check the pool address:
  - Verification logic (no need to do it every time):
    - Open the Uniswap documentation and find its router address: https://docs.uniswap.org/contracts/v2/reference/smart-contracts/router-02.
    - On that page, one can find the following text: `UniswapV2Router02 is deployed at 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D address on the Ethereum mainnet, and the Ropsten, Rinkeby, Görli, and Kovan testnets. It was built from commit 6961711.`
    - Open the contract reading page: https://etherscan.io/address/0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D#readContract.
    - Read the `factory()` method and check that it returns the following address: `0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f`.

  - Open the UniswapV2Factory contract: https://etherscan.io/address/0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f#readContract
  - Call the `getPair()` method with `OLAS token address` and `wETH token address` as inputs. In our DAT-wETH examples, the inputs are the following:
    - `0x6B175474E89094C44Da98b954EedeAC495271d0F`,
    - `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`.
  - The output will be the LP token address. In this example, this is the following address: `0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11`.
  - If the address match with the given original LP-token address (in this example, `0xa478c2975ab1ea89e8196811f51a7b7ade33eb11`), everything is correct.
- In correctly created LP token, the first internal transaction must be originated by the UniswapV2Factory address: https://etherscan.io/address/0xa478c2975ab1ea89e8196811f51a7b7ade33eb11#internaltx.
- Optionally, the followign link works for well-known LP tokens: https://v2.info.uniswap.org/pair/0xa478c2975ab1ea89e8196811f51a7b7ade33eb11.
  However, the absence of requested token information does not mean there is something wrong with the token. In that case just use the verification described above.