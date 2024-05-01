# UVM (Universal Verification Methodology)
This project verifies the functional accuracy of a modified SHA-256 module compared to a model SHA-256 module. UVM is used for portability, encapsulating monitor, driver, and sequencer in an agent class. The code leverages polymorphism where applicable, for example when builing the Model agent based on the DUT agent. This code can easily be adapted to fit more test cases or to test different designs.

![UVM diagram for SHA256](https://github.com/calewoodward/uvm_sha256/blob/main/sha256_UVM_block.png?raw=true)
