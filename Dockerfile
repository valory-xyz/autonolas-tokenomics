FROM node:17.3.0
RUN mkdir -p /code
WORKDIR /code
ADD . /code

ENV NODE_OPTIONS=--openssl-legacy-provider
RUN yarn 

CMD [ "npx", "hardhat", "node", "--hostname", "0.0.0.0" ]
