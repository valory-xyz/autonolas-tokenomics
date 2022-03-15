# On-Chain Protocol State Machine
Let's first describe the list of possible states:
- Service is non-existent; -> No service has been registered with a specified Id yet or the service is non-recoverable
- Service is pre-registration; -> Agent instance registration is not active yet
- Service is active-registration; -> Agent instance registration is ongoing
- Service is expired-registration; -> Deadline for agent instance registration has passed
- Service is finished-registration; -> All the agent instances slots are registered
- Service is deployed; -> Service is deployed and operates via created safe contract
- Service is terminated-bonded; -> Some agents are bonded with stake
- Service is terminated-unbonded; -> All agents have left the service and recovered their stake
- Service is destroyed; -> Service is no longer available: in the code it is a synonym to a non-existent state


TBD: we need the bonding mechanism implemented as part of agent registration.

In v1 the service has a static set of agent instances;

Can service owner slash? If yes, single control; if no, need honest majority which we imply anyway; -> answer is no

## States by functions
Now let's see the evolution of states when calling each of the service functions that modify states between function
entrance and exit. We assume that all the input that is passed to the contract is correct. Here we track only the states
of the asynchronous on-chain behavior.

### createService()
- **Current state:** Service is non-existent
  - Input: Service parameters
  - Output: Incremented `service Id`
- **Next state:** Service is pre-registration

### update()
1. - **Current state:** Service is pre-registration
     - Input: Service parameters and `service Id`
     - Output: Updates instance of `service Id`
   - **Next state:** Service is pre-registration


2. - **Current state:** Service is active-registration
     - Input: service parameters without errors and `service Id`
     - Condition: No single agent instance is registered
     - Output: Updates instance of `service Id`
   - **Next state:** Service is active-registration


3- **Current state:** Service is active-registration
     - Input: service parameters without errors and `service Id`
     - Condition: One or more agent instance is registered
     - Output: Error
   - **Next state:** Service is active-registration

### activateRegistration()
1. - **Current state:** Service is pre-registration
   - **Next state:** Service is active-registration


2. - **Current state:** Service is active-registration
     - Output: Error
   - **Next state:** Service is active-registration

### deactivateRegistration()
1. - **Current state:** Service is pre-registration
     - Output: Error
   - **Next state:** Service is pre-registration


2. - **Current state:** Service is active-registration
     - Condition: No single agent instances is registered
   - **Next state:** Service is pre-registration


3. - **Current state:** Service is active-registration
     - Condition: One or more agent instance is registered
     - Output: Error
   - **Next state:** Service is active-registration

### destroy()
1. - **Current state:** Service is pre-registration
   - **Next state:** Service is destroyed


2. - **Current state:** Service is active-registration
     - Condition: No single agent instance is registered and the termination block is not set
   - **Next state:** Service is destroyed


3. - **Current state:** Service is active-registration
     - Condition: Termination block has passed
   - **Next state:** Service is destroyed


4. - **Current state:** Service is active-registration
     - Condition: Termination block has not passed
     - Output: Error
   - **Next state:** Service is active-registration


5. - **Current state:** Service is active-registration
     - Condition: One or more agent instance is registered and the termination block is empty or has not passed
     - Output: Error
   - **Next state:** Service is active-registration

### setRegistrationDeadline()
1. - **Current state:** Service is pre-registration
     - Input: Registration deadline
   - **Next state:** Service is pre-registration


2. - **Current state:** Service is active-registration
     - Input: Registration deadline
   - **Next state:** Service is active-registration


3. - **Current state:** expired-registration
     - Input: Registration deadline
     - Condition: Registration deadline is greater than the current time
   - **Next state:** Service is active-registration

### terminate()
1. - **Current state:** Any except for non-existent or destroyed
     - Input: Service Id
   - **Next state:** Service is terminated-bonded or terminated-unbonded

### unbond()
1. - **Current state:** expired-registration or terminated-bonded
     - Input: Operator, service Id
   - **Next state:** Service is expired-registration or terminated-unbonded
   
### registerAgent()
1. - **Current state:** Service is pre-registration
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** Service is pre-registration


2. - **Current state:** expired-registration
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** expired-registration


3. - **Current state:** finished-registration
     - Input: Operator, canonical agent Id, agent instance address
     - Output: Error
   - **Next state:** finished-registration


4. - **Current state:** Service is active-registration
     - Input: Operator, canonical agent Id, agent instance address
     - Condition: Agent instance is not registered, canonical agent Id is in the service set of agent Ids, 
   - **Next state:** Service is active-registration or finished-registration
   
### createSafe()
1. - **Current state:** Service is pre-registration
     - Input: Safe parameters
     - Output: Error
   - **Next state:** Service is pre-registration


2. - **Current state:** Service is active-registration
     - Input: Safe parameters
     - Output: Error
   - **Next state:** Service is active-registration


3. - **Current state:** finished-registration
     - Input: Safe parameters
   - **Next state:** Service is deployed

    
## List of states and functions leading to other states

Let's consider the change of states via the means of function calls from each specific state. Note that if the function
being called from the current state is not included in the list of next possible states, its execution must not change
the current state.

### Service is non-existent
Functions to call from this state:
   - **createService()**

List of next possible states:
1. **Service is pre-registration**.
   - Function call for this state: **createService()**
   - Output: Unique incremented `service Id`

### Service is pre-registration
Functions to call from this state:
  - **activateRegistration()**
  - **destroy()**
  - **update()**
  - **setRegistrationDeadline()**
  - **terminate()**

List of next possible states:
1. **Service is active-registration**
   - Function call for this state: **activateRegistration()**


2. **Service is destroyed**
    - Function call for this state: **destroy()**


3. **Service is terminated-unbonded**
    - Function call for this state: **terminate()**

### Service is active-registration
Functions to call from this state:
  - **deactivateRegistration()**
  - **destroy()**
  - **registerAgent()**
  - **update()**. Condition: No single agent instance is registered
  - **setRegistrationDeadline()**
  - **terminate()**


List of next possible states:
1. **Service is pre-registration**
   - Function call for this state: **deactivateRegistration()**
   - Condition: No single agent instance is registered


2. **Service is destroyed**
    - Function call for this state: **destroy()**
    - Condition: No single agent instance is registered


3. **Service is finished-registration**
    - Function call for this state: **registerAgent()**
    - Condition: Number of agent instances reached its maximum value


4. **Service is terminated-bonded**
    - Function call for this state: **terminate()**
    - Condition: At least one agent instance is registered


5. **Service is terminated-unbonded**
    - Function call for this state: **terminate()**
    - Condition: No single agent instance is registered

### Service is finished-registration
Functions to call from this state:
  - **createSafe()**
  - **terminate()**


List of next possible states:
1. **Service is deployed**
    - Function call for this state: **createSafe()**


2. **Service is terminated-bonded**
    - Function call for this state: **terminate()**

### Service is expired-registration
Condition for this state: Agent instance registration time has passed and previous service state was `active-registration`

Functions to call from this state:
  - **deactivateRegistration()**
  - **destroy()**
  - **update()**. Condition: No single agent instance is registered.
  - **setRegistrationDeadline()**
  - **terminate()**


List of next possible states:
1. **Service is active-registration**
    - Function call for this state: **setRegistrationDeadline()**
    - Condition: Updated block is greater than the current block and no single agent instance is currently registered


2. **Service is pre-registration**
    - Function call for this state: **deactivateRegistration()**
    - Condition: No single agent instance is currently registered


3. **Service is destroyed**
    - Function call for this state: **destroy()**
    - Condition: No single agent instance is currently registered


4. **Service is terminated-bonded**
    - Function call for this state: **terminate()**
    - Condition: At least one agent instance is still registered after the function call


5. **Service is terminated-unbonded**
    - Function call for this state: **terminate()**
    - Condition: No single agent instance is currently registered.
    
### Service is terminated-bonded
Condition for this state: Service is terminated and some agents are bonded with agent instances.

Functions to call from this state:
  - **unbond()**


List of next possible states:
1. **Service is terminated-bonded**
    - Function call for this state: **unbond()**
    - Condition: At least one agent instance is still registered after the function call


2. **Service is terminated-unbonded**
    - Function call for this state: **unbond()**
    - Condition: No single agent instance is registered after the function call

### Service is terminated-unbonded
Condition for this state: Service termination block has passed and all agent instances have left the service and recovered their stake or have never registered for the service

Functions to call from this state:
- **destroy()**
- **update()** -> Can be called, but will not do anything useful

List of next possible states:
1. **Service is destroyed**
    - Function call for this state: **destroy()**

