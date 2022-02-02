# On-Chain Protocol State Machine
Let's first describe the list of possible states:
- Service does not exist;
- Service is inactive;
- Service is active;
- Service is expired;
- Service is terminated;
- Service is deployed;
- Service is at full capacity of agent instances.

## States by functions
Now let's see the evolution of states when calling each of the service functions that modify states between function
entrance and exit. We assume that all the input that is passed to the contract is correct. Here we track only the states
of the asynchronous on-chain behavior.

### createService()
- **Current state:** Service does not exist
  - Input: Service parameters
  - Output: Incremented `service Id`
- **Next state:** Service is inactive

### serviceUpdate()
1. - **Current state:** Service is inactive
     - Input: Service parameters and `service Id`
     - Output: Updates instance of `service Id`
   - **Next state:** Service is inactive


2. - **Current state:** Service is active
     - Input: service parameters without errors and `service Id`
     - Condition: No single agent instance is registered
     - Output: Updates instance of `service Id`
   - **Next state:** Service is active


3- **Current state:** Service is active
     - Input: service parameters without errors and `service Id`
     - Condition: One or more agent instance is registered
     - Output: Error
   - **Next state:** Service is active

### activate()
1. - **Current state:** Service is inactive
   - **Next state:** Service is active


2. - **Current state:** Service is active
     - Output: Error
   - **Next state:** Service is active

### deactivate()
1. - **Current state:** Service is inactive
     - Output: Error
   - **Next state:** Service is inactive


2. - **Current state:** Service is active
     - Condition: No single agent instances is registered
   - **Next state:** Service is inactive


3. - **Current state:** Service is active
     - Condition: One or more agent instance is registered
     - Output: Error
   - **Next state:** Service is active

### destroy()
1. - **Current state:** Service is inactive
   - **Next state:** Service does not exist


2. - **Current state:** Service is active
     - Condition: No single agent instance is registered and termination block is not set
   - **Next state:** Service does not exist


3. - **Current state:** Service is active
     - Condition: Termination block has passed
   - **Next state:** Service does not exist


4. - **Current state:** Service is active
     - Condition: Termination block has not passed
     - Output: Error
   - **Next state:** Service is active


5. - **Current state:** Service is active
     - Condition: One or more agent instance is registered and termination block is empty or has not passed
     - Output: Error
   - **Next state:** Service is active

### setRegistrationWindow()
1. - **Current state:** Service is inactive
     - Input: Registration deadline
   - **Next state:** Service is inactive


2. - **Current state:** Service is active
     - Input: Registration deadline
   - **Next state:** Service is active


3. - **Current state:** Service is expired
     - Input: Registration deadline
     - Condition: Registration deadline is greater than the current time
   - **Next state:** Service is active
   
### registerAgent()
1. - **Current state:** Service is inactive
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** Service is inactive


2. - **Current state:** Service is expired
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** Service is expired


3. - **Current state:** Service is at full capacity of agent instances
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** Service is at full capacity of agent instances


4. - **Current state:** Service is active
     - Input: Operator, canonical agent Id, agent instance address
     - Condition: Agent instance is not registered, canonical agent Id is in the service set of agent Ids, 
   - **Next state:** Service is active or Service is at full capacity of agent instances
   
### createSafe()
1. - **Current state:** Service is inactive
     - Input: Safe parameters
     - Output: Error
   - **Next state:** Service is inactive


2. - **Current state:** Service is active
     - Input: Safe parameters
     - Output: Error
   - **Next state:** Service is active


3. - **Current state:** Service is at full capacity of agent instances
     - Input: Safe parameters
   - **Next state:** Service is deployed

    
## TODO
### check conditions for the state of Service is terminated
### service_leave()
