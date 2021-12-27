# component-registry
## Setup
1. create ec2 instance
2. when prompted, cerate a new vpc and a new subnet
3. on secirity groups, ensure that the port 8545 is accessible from anywhere

# get code.
1. Get code
```bash
git clone https://github.com/valory-xyz/component-registry.git
```
2. install node & npm
```
curl -fsSL https://deb.nodesource.com/setup_17.x | sudo -E bash -
sudo apt-get install -y nodejs
```
3. install yarn
```bash
npm install -g yarn
```
4. run 
```bash
export NODE_OPTIONS=--openssl-legacy-provider
npx hardhat node --hostname 0.0.0.0
```
# NOTE the server is running TMUX so this has been performed in tmux session 0. 
attach using;
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
