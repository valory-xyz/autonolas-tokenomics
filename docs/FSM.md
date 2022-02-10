# On-Chain Protocol State Machine
Let's first describe the list of possible states:
- Service does not exist;
- Service is inactive;
- Service is active;
- Service is not able to register agent instances;
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
     - Condition: No single agent instance is registered and the termination block is not set
   - **Next state:** Service does not exist


3. - **Current state:** Service is active
     - Condition: Termination block has passed
   - **Next state:** Service does not exist


4. - **Current state:** Service is active
     - Condition: Termination block has not passed
     - Output: Error
   - **Next state:** Service is active


5. - **Current state:** Service is active
     - Condition: One or more agent instance is registered and the termination block is empty or has not passed
     - Output: Error
   - **Next state:** Service is active

### setRegistrationWindow()
1. - **Current state:** Service is inactive
     - Input: Registration deadline
   - **Next state:** Service is inactive


2. - **Current state:** Service is active
     - Input: Registration deadline
   - **Next state:** Service is active


3. - **Current state:** Service is not able to register agent instances
     - Input: Registration deadline
     - Condition: Registration deadline is greater than the current time
   - **Next state:** Service is active
   
### registerAgent()
1. - **Current state:** Service is inactive
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** Service is inactive


2. - **Current state:** Service is not able to register agent instances
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** Service is not able to register agent instances


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

    
## List of states and functions leading to other states
Let's consider the change of states via the means of function calls from each specific state. Note that if the function
being called from the current state is not included in the list of next possible states, its execution does not change
the current state.

### Service does not exist
Functions to call from this state:
   - **createService()**

List of next possible states:
1. **Service is inactive**.
   - Function call for this state: **createService()**
   - Output: Unique incremented `service Id`

### Service is inactive
Functions to call from this state:
  - **activate()**
  - **destroy()**
  - **serviceUpdate()**
  - **setRegistrationWindow()**
  - **setTerminationBlock**


List of next possible states:
1. **Service is active**
   - Function call for this state: **activate()**


2. **Service does not exist**
    - Function call for this state: **destroy()**

### Service is active
Functions to call from this state:
  - **deactivate()**
  - **destroy()**
  - **registerAgent()**
  - **serviceUpdate()**. Condition: No single agent instance is registered
  - **setRegistrationWindow()**
  - **setTerminationBlock()**


List of next possible states:
1. **Service is inactive**
   - Function call for this state: **deactivate()**
   - Condition: No single agent instance is registered


2. **Service does not exist**
    - Function call for this state: **destroy()**
    - Condition: No single agent instance is registered or the termination block has passed


3. **Service is at full capacity of agent instances**
    - Function call for this state: **registerAgent()**
    - Condition: Number of agent instances reached its maximum value

### Service is at full capacity of agent instances
Functions to call from this state:
  - **createSafe()**
  - **setRegistrationWindow()**
  - **setTerminationBlock()**


List of next possible states:
1. **Service is deployed**
    - Function call for this state: **createSafe()**

### Service is not able to register agent instances
Condition for this state: Agent instance registration time has passed

Functions to call from this state:
  - **activate()**
  - **deactivate()**
  - **destroy()**
  - **serviceUpdate()**. Condition: No single agent instance is registered or previous service state was `inactive`
  - **createSafe()**
  - **setRegistrationWindow()**
  - **setTerminationBlock()**

List of next possible states:
1. **Service is active**
    - Function call for this state: **setRegistrationWindow()**
    - Condition: Previous service state was `active` and updated time is greater than the current time


2. **Service is inactive**
    - Function call for this state: **setRegistrationWindow()**
    - Condition: Previous service state was `inactive` and updated time is greater than the current time


2. **Service does not exist**
    - Function call for this state: **destroy()**
    - Condition: Previous service state was `inactive`. Or, no single agent instance is registered or the termination block has passed


3. **Service is deployed**
    - Function call for this state: **createSafe()**
    - Condition: Previous service state was `at full capacity of agent instances`


4. **Service is at full capacity of agent instances**
    - Function call for this state: **setRegistrationWindow()**
    - Condition: Previous service state was `at full capacity of agent instances` and updated time is greater than the current time
    
### Service is terminated
Condition for this state: Service termination block has passed

Functions to call from this state:
  - **activate()**
  - **deactivate()**
  - **destroy()**
  - **serviceUpdate()**. Condition: No single agent instance is registered or previous service state was `inactive`
  - **setRegistrationWindow()**
  - **setTerminationBlock()**


List of next possible states:
1. **Service does not exist**
    - Function call for this state: **destroy()**
    - Condition: Previous service state was `inactive` or no single agent instance is registered


2. **Service is active**
    - Function call for this state: **setTerminationBlock()**
    - Condition: Previous service state was `active` and updated termination block is equal to zero or greater than the current block number


2. **Service is inactive**
    - Function call for this state: **setTerminationBlock()**
    - Condition: Previous service state was `inactive` and updated termination block is equal to zero or greater than the current block number

    
3. **Service is deployed**
    - Function call for this state: **setTerminationBlock()**
    - Condition: Previous service state was `deployed` and updated termination block is equal to zero or greater than the current block number


4. **Service is at full capacity of agent instances**
    - Function call for this state: **setTerminationBlock()**
    - Condition: Previous service state was `at full capacity of agent instances` and updated termination block is equal to zero or greater than the current block number

