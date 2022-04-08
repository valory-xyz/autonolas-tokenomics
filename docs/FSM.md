# On-Chain Protocol State Machine
Let's first describe the list of possible states:
- Service is non-existent; -> No service has been registered with a specified Id yet or the service is non-recoverable
- Service is pre-registration; -> Agent instance registration is not active yet
- Service is active-registration; -> Agent instance registration is ongoing
- Service is finished-registration; -> All the agent instances slots are registered
- Service is deployed; -> Service is deployed and operates via created multisig contract
- Service is terminated-bonded; -> Some agents are bonded with stake
- Service is terminated-unbonded; -> All agents have left the service and recovered their stake

In v1 the service has a static set of agent instances following activation of the registration.

## States by functions
Now let's see the evolution of states when calling each of the service functions that modify states between function
entrance and exit. We assume that all the input that is passed to the contract is correct. Here we track only the states
of the asynchronous on-chain behavior. By design, any attempts to bring service states to those that are not specified
would throw an error.

### createService()
- **Current state:** non-existent
- **Next state:** pre-registration

### update()
- **Current state:** pre-registration
- **Next state:** pre-registration

### activateRegistration()
- **Current state:** pre-registration
- **Next state:** active-registration

### destroy()
- **Current state:** pre-registration or termination-unbonded
- **Next state:** non-existent

### terminate()
- **Current state:** active-registration or finished-registration or deployed
- **Next state:** terminated-bonded or terminated-unbonded

### unbond()
- **Current state:** expired-registration or terminated-bonded
- **Next state:** expired-registration or terminated-unbonded
   
### registerAgents()
- **Current state:** Service is active-registration
- **Next state:** Service is active-registration or finished-registration
   
### deploy()
- **Current state:** finished-registration
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
  - **update()**
  - **destroy()**

List of next possible states:
1. **Service is active-registration**
   - Function call for this state: **activateRegistration()**


2. **Service is non-existent**
    - Function call for this state: **destroy()**

### Service is active-registration
Functions to call from this state:
  - **registerAgents()**
  - **terminate()**


1. **Service is finished-registration**
    - Function call for this state: **registerAgents()**
    - Condition: Number of agent instances reached its maximum value


2. **Service is terminated-bonded**
    - Function call for this state: **terminate()**
    - Condition: At least one agent instance is registered


3. **Service is terminated-unbonded**
    - Function call for this state: **terminate()**
    - Condition: No single agent instance is registered

### Service is finished-registration
Functions to call from this state:
  - **deploy()**
  - **terminate()**


List of next possible states:
1. **Service is deployed**
    - Function call for this state: **deploy()**


2. **Service is terminated-bonded**
    - Function call for this state: **terminate()**

### Service is terminated-bonded
Condition for this state: Service is terminated and some agents are bonded with agent instances.

Functions to call from this state:
  - **unbond()**


List of next possible states:
1. **Service is terminated-unbonded**
    - Function call for this state: **unbond()**
    - Condition: No single agent instance is registered after the function call

### Service is terminated-unbonded
Condition for this state: Service termination block has passed and all agent instances have left the service and recovered
their stake or have never registered for the service.

Functions to call from this state:
- **destroy()**

List of next possible states:
1. **Service is non-existent**
    - Function call for this state: **destroy()**

