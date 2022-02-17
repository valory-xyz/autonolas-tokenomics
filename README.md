# On-chain Protocol
On-chain protocol provides the functionality to mint agent `components` and canonical `agents` via the ERC721 standard.
It stores instances associated with components and agents, supplies a set of read-only functions to inquire the state
of entities.

The protocol also provides the capability of creating `services` that are based on canonical agents. Each service
instance bears a set of canonical agent Ids it is composed of with the number of agent instances for each Id. For the
service deployment `operators` supply agent instances to a specific service via registration. Once all the required
agent instances are provided by operators, the service can be deployed forming a Gnosis Safe contract governed by
a group of agent instances.

## Definitions and data structures
- [`Multihash`](https://multiformats.io/multihash/): a self-describing hash, a protocol for differentiating outputs
from various well-established hash functions. Multihash is a hashing standard for [`IPFS`](https://docs.ipfs.io/concepts/what-is-ipfs/),
a distributed system for storing and accessing files, websites, applications, and data. Please note that IPSF uses the
`sha2-256 - 256 bits` as their hashing function. From the definition, `sha2-256` has a `0x12` code in hex, and its
length is 32, or `0x20` in hex. This means that each IPFS link starts with `1220` value in hash, and the link itself
can perfectly fit the `bytes32` data structure. Note that if the IPFS hashing changes, the size of Multihash data
structure needs to be updated, although old links would still work (as per IPFS standard).
- `Agent Component`: a piece of code + configuration in the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
framework, it is a skill, connection, protocol or contract. Each component is identified by its IPFS hash.
- `Canonical Agent`: a configuration and optionally code making up the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
framework, this is the agent config file which points to various agent components. The agent code and config are
identified by its IPFS hash.
- `Agent Instance`: an instance of a canonical agent. Each agent instance must have, at a minimum, a single
cryptographic key-pair, whose address identifies the agent.
- `Operator`: an individual operating an agent instance (or multiple). The operator must have, at a minimum, a single 
cryptographic key-pair whose address identifies the operator. This key-pair MUST be different from the ones used
by the agent.
- `Service`: defines a set (or singleton) of canonical agents (and therefore components), a set of service extension
contracts, a number of agents instances per canonical agents.



## Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity 0.8.0.
- The standard versions of Node.js along with Yarn are required to proceed further

## Install the dependencies
The dependency list is managed by the `package.json` file,
and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the follwing command to install the project:
```
yarn install
```

## Core components
The contracts, deploy scripts, regular scripts and tests are located in the following folders respectively:
```
contracts
deploy
scripts
test
```
The tests are logically separated into unit and integration ones.

## Compile the code and run
Compile the code:
```
npx hardhat compile
```
Run the tests:
```
npx hardhat test
```
Run the script without the node deployment:
```
npx hardhat run scripts/name_of_the_script.js
```
Run the code with its deployment on the node:
```
npx hardhat node
```

## Linters
- [`ESLint`](https://eslint.org) is used for JS code.
- [`solhint`](https://github.com/protofire/solhint) is used for Solidity linting.


## Github workflows
The PR process is managed by github workflows, where the code undergoes
several steps in order to be verified. Those include:
- code isntallation
- running linters
- running tests

## Setup for server deployment
1. create ec2 instance
2. when prompted, cerate a new vpc and a new subnet
3. on secirity groups, ensure that the port 8545 is accessible from anywhere

# get code.
1. Get the code
```bash
git clone https://github.com/valory-xyz/onchain-protocol.git
```
2. Install node & npm
```
curl -fsSL https://deb.nodesource.com/setup_17.x | sudo -E bash -
sudo apt-get install -y nodejs
```
3. Install yarn
```bash
npm install -g yarn
```
4. Run 
```bash
export NODE_OPTIONS=--openssl-legacy-provider
npx hardhat node --hostname 0.0.0.0
```
## NOTE the server is running TMUX so this has been performed in tmux session 0. 
Attach using:
```bash
tmux attach
```

## Tear down
1. delete instance;
    https://eu-central-1.console.aws.amazon.com/ec2/v2/home?region=eu-central-1#InstanceDetails:instanceId=i-06f5960371f5bb069
2. delete vpc 
   https://eu-central-1.console.aws.amazon.com/vpc/home?region=eu-central-1#VpcDetails:VpcId=vpc-0575d2b1619ac2977
3. delete subnet
    https://eu-central-1.console.aws.amazon.com/vpc/home?region=eu-central-1#subnets:SubnetId=subnet-0f069a3ef9a828f97
4. delete security group
    https://eu-central-1.console.aws.amazon.com/ec2/v2/home?region=eu-central-1#SecurityGroup:securityGroupId=sg-032fd920e5ce5f5f6
