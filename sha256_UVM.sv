import uvm_pkg::*;
`include "uvm_macros.svh"

interface dut_if;
    logic             rst;
    logic             init;
    logic             next;
    logic [511:0]     block;
    logic             ready;
    logic [255:0]     digest;
    logic             digest_valid;
endinterface

module tb_top;
    
    logic clk;

    // instantiate interfaces for DUT and model
    dut_if if1();
    dut_if if2();
    
    // instantiate DUT/model and connect them to the interfaces
    sha256_hier dut1( 
        .clk            (clk), 
        .rst            (if1.rst),
        .init           (if1.init),
        .next           (if1.next),
        .block          (if1.block),
        .ready          (if1.ready),
        .digest         (if1.digest),
        .digest_valid   (if1.digest_valid)
    );

    sha256_hier_trans model( 
        .clk            (clk), 
        .rst            (if2.rst),
        .init           (if2.init),
        .next           (if2.next),
        .block          (if2.block),
        .ready          (if2.ready),
        .digest         (if2.digest),
        .digest_valid   (if2.digest_valid)
    );
    
    // clock generator
    initial begin
        clk = '0;
        forever #5 clk = ~clk;
    end
    
    initial begin
        // Place the interface into the UVM configuration database
        uvm_config_db#(virtual dut_if)::set(null, "*", "dut_vif", if1);
        uvm_config_db#(virtual dut_if)::set(null, "*", "model_vif", if2);
        // Start the test
        run_test("comparison_test");
    end
    
    // Dump waves
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end
    
endmodule

class sha256_transaction extends uvm_sequence_item;
    // object factory registration macro
    `uvm_object_utils(sha256_transaction)

    // declare rand for inputs
    rand logic [511:0] block;
         logic [255:0] digest;

    // set constraints on rand inputs
    constraint c_block { block >= 0; block < 2**512; }

    // object factory default constructor
    function new (string name = "");
        super.new(name);
    endfunction

    // function to help display item contents
    virtual function string convert2string();
        return $sformatf("block=%0h, digest=%0h", block, digest);
    endfunction

endclass //sha256_transaction

class sha256_sequence extends uvm_sequence#(sha256_transaction);
    // object factory registration macro
    `uvm_object_utils(sha256_sequence)

    // object factory default constructor
    function new (string name = "");
        super.new(name);
    endfunction

    task body;
        repeat(3) begin // parameterize num tests?
            logic [511:0] temp;
            req = sha256_transaction::type_id::create("req");
            start_item(req);
            
            // no randomize() support in Questa
            temp[31:0]    = $urandom(); // max 32 bits
            temp[63:32]   = $urandom();
            temp[95:64]   = $urandom();
            temp[127:96]  = $urandom();
            temp[159:128] = $urandom();
            temp[191:160] = $urandom();
            temp[223:192] = $urandom();
            temp[255:224] = $urandom();
            temp[287:256] = $urandom();
            temp[319:288] = $urandom();
            temp[351:320] = $urandom();
            temp[383:352] = $urandom();
            temp[415:384] = $urandom();
            temp[447:416] = $urandom();
            temp[479:448] = $urandom();
            temp[511:480] = $urandom();

            req.block   = temp;

            `uvm_info(get_type_name(),
                            $sformatf("Create item: %s", req.convert2string()), UVM_MEDIUM)

            finish_item(req);
        end
    endtask: body

endclass //sha256_sequence

class dut_driver extends uvm_driver #(sha256_transaction);
    // component factory registration macro
    `uvm_component_utils(dut_driver)

    // declare virtual interface handle and object for incoming data
    virtual dut_if              vif;
            sha256_transaction  req;

    // component factory default constructor
    function new(string name = "dut_driver", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        // Get virtual interaface reference from config database
        if(!uvm_config_db#(virtual dut_if)::get(this, "", "dut_vif", vif)) begin
            `uvm_error(get_type_name(), "Failed to get virtual interface handle")
        end
        req = sha256_transaction::type_id::create("req", this);
    endfunction 

    // drive first transaction
    virtual task run_phase(uvm_phase phase);
        // clear input signals
        set_default_state();

        forever begin
            send_reset_signal();
            drive_next_item();
            phase.raise_objection(this);
            wait_until_ready();
            #(10); // additional delay for scoreboard operations
            phase.drop_objection(this);
            #(10); // allow test to complete without sending extra reset signals
        end

    endtask

    virtual task set_default_state();
        vif.init  = '0;
        vif.next  = '0;
        vif.block = '0;
        vif.rst   = '0;
    endtask;

    virtual task send_reset_signal();
        `uvm_info(get_type_name(), "Sending reset signal...", UVM_MEDIUM)
        vif.rst = 1'b1;
        #(20);
        vif.rst = '0;
    endtask

    virtual task drive_next_item();
        seq_item_port.get_next_item(req);
        vif.block = req.block;
        vif.init  = 1'b1;
        #(10);
        vif.init  = '0;
        `uvm_info(get_type_name(),
                  $sformatf("Driving item: %s", req.convert2string()), UVM_MEDIUM)
        seq_item_port.item_done();
    endtask;

    virtual task wait_until_ready();
        while(!vif.ready) begin
            #(10);
        end
    endtask

endclass //dut_driver

class model_driver extends dut_driver; // model class inherits from DUT
    // component factory registration macro
    `uvm_component_utils(model_driver)

    // declare FIFO ports for incoming data objects
    uvm_tlm_analysis_fifo#(sha256_transaction) driver_fifo;  

    // component factory default constructor
    function new(string name = "model_driver", uvm_component parent);
        super.new(name, parent);
    endfunction

    // build components
    virtual function void build_phase(uvm_phase phase);
        // get virtual interface reference from config database
        if(!uvm_config_db#(virtual dut_if)::get(this, "", "model_vif", vif)) begin
            `uvm_error(get_type_name(), "Failed to get virtual interface handle")
        end
        req         = sha256_transaction::type_id::create("req", this);
        driver_fifo = new("driver_fifo", this);
    endfunction

    // overload task to drive transactions from FIFO instead of sequencer port
    virtual task drive_next_item();
        // request item from FIFO
        driver_fifo.get(req);
        `uvm_info(get_type_name(),
                $sformatf("Driving item: %s", req.convert2string()), UVM_MEDIUM)
        // wiggle pins through interface
        vif.block = req.block;
        vif.init  = 1'b1;
        #(10);
        vif.init  = '0;
    endtask;

endclass //model_driver

class dut_monitor extends uvm_monitor; 
    // component factory registration macro
    `uvm_component_utils(dut_monitor)

    // declare virtual interface handle, analysis ports, data objects
    virtual dut_if                                  vif;
            uvm_analysis_port#(sha256_transaction)  input_ap;
            uvm_analysis_port#(sha256_transaction)  output_ap;
            sha256_transaction                      input_obj;
            sha256_transaction                      output_obj;

    // component factory default constructor
    function new(string name = "dut_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction //new()

    // instantiate components
    virtual function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual dut_if)::get(this, "", "dut_vif", vif)) begin
            `uvm_error(get_type_name(), "Failed to get virtual interface handle")
        end
        input_ap   = new("input_ap", this);
        output_ap  = new("output_ap", this);
        input_obj  = sha256_transaction::type_id::create("input_obj", this);
        output_obj = sha256_transaction::type_id::create("output_obj", this);
    endfunction 

    virtual task run_phase(uvm_phase phase);
        forever begin
            fork
                begin
                    capture_input();
                end
                begin
                    capture_output();
                end
            join
        end
    endtask //run_phase

    virtual task capture_input();
        //@(some event when input data on VIF is valid)
        @(posedge vif.init);
        // populate objects with inputs from sequencer
        input_obj.block  = vif.block;
        output_obj.block = vif.block;
        // print input
        `uvm_info(get_type_name(), "Cloning input", UVM_MEDIUM)
        // send input to model
        input_ap.write(input_obj);
    endtask //capture_input

    virtual task capture_output();
        //@(some event when output data on VIF is valid)
        @(posedge vif.digest_valid);
        // populate object with output from virtual interface
        output_obj.digest = vif.digest;
        // print output
        `uvm_info(get_type_name(), "Captured output", UVM_MEDIUM)
        // send object through output analysis port
        output_ap.write(output_obj);
    endtask //capture_output

endclass //dut_monitor

class model_monitor extends dut_monitor; // model class inherits from DUT
    // component factory registration macro
    `uvm_component_utils(model_monitor)

    // component factory default constructor
    function new(string name = "model_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction //new()

    // instantiate interface, ports, objects
    virtual function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual dut_if)::get(this, "", "model_vif", vif)) begin
            `uvm_error(get_type_name(), "Failed to get virtual interface handle")
        end
        output_ap  = new("output_ap", this);
        output_obj = sha256_transaction::type_id::create("output_obj", this);
    endfunction 

    // overload task since model needs only to capture inputs (not clone)
    virtual task capture_input();
        //@(some event when input data on VIF is valid)
        @(posedge vif.init);
        // populate object with input to model
        output_obj.block = vif.block;
    endtask //capture_input

endclass //model_monitor

class comparison_scoreboard extends uvm_scoreboard;
    // component factory registration macro
    `uvm_component_utils(comparison_scoreboard)

    // declare FIFO ports, objects, counters
    uvm_tlm_analysis_fifo#(sha256_transaction)  dut_fifo;  
    uvm_tlm_analysis_fifo#(sha256_transaction)  model_fifo;
    sha256_transaction                          dut_item;
    sha256_transaction                          model_item;
    int                                         num_match;
    int                                         num_mismatch;

        // component factory default constructor
    function new(string name = "comparison_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction //new()
    
    // instantiate FIFO analysis ports
    function void build_phase(uvm_phase phase);
        dut_fifo    = new("dut_fifo", this);
        model_fifo  = new("model_fifo", this);
    endfunction //build_phase

    // using run so task continues to process final FIFO items after run_phase ends
    task run();
        // create new data objects
        dut_item   = sha256_transaction::type_id::create("dut_item", this);
        model_item = sha256_transaction::type_id::create("model_item", this);

        forever begin
            // fork and get data from each fifo
            fork
                begin
                    `uvm_info(get_type_name(),"DUT FIFO ready for item", UVM_HIGH)
                    dut_fifo.get(dut_item);
                end
                begin
                    `uvm_info(get_type_name(),"Model FIFO ready for item", UVM_HIGH)
                    model_fifo.get(model_item);
                end
            join
            compare_items(dut_item, model_item);
        end
                
    endtask //run

    function void report_phase(uvm_phase phase);
        `uvm_info(get_type_name(), $sformatf("Matches: %0d", num_match), UVM_MEDIUM)
        `uvm_info(get_type_name(), $sformatf("Mismatches: %0d", num_mismatch), UVM_MEDIUM)
    endfunction//report_phase

    function void compare_items(sha256_transaction dut_item, model_item);
        `uvm_info(get_type_name(), "Comparing digest...", UVM_MEDIUM)
        `uvm_info(get_type_name(), $sformatf("  dut: %0h", dut_item.digest), UVM_MEDIUM)
        `uvm_info(get_type_name(), $sformatf("model: %0h", model_item.digest), UVM_MEDIUM)

        // compare output of items
        if(dut_item.digest==model_item.digest) begin
            `uvm_info(get_type_name(),"Digest matches", UVM_MEDIUM)
            num_match++;
        end
        else begin
            `uvm_warning(get_type_name(),"Digest DOES NOT match")
            num_mismatch++;
        end

    endfunction //compare_items

endclass //comparison_scoreboard

class sha256_env extends uvm_env;
    // component factory registration macro
    `uvm_component_utils(sha256_env)
    
    // create handles for components
    sha256_sequence                     seq;
    uvm_sequencer#(sha256_transaction)  seqr;
    dut_driver                          dut_drv;
    dut_monitor                         dut_mon;
    model_driver                        model_drv;
    model_monitor                       model_mon;
    comparison_scoreboard               scbd;

    // component factory default constructor
    function new(string name = "sha256_env", uvm_component parent);
        super.new(name, parent);
    endfunction

    // instantiate components
    function void build_phase(uvm_phase phase);
        seq       = sha256_sequence::type_id::create("seq", this);
        seqr      = uvm_sequencer#(sha256_transaction)::type_id::create("seqr", this);
        dut_drv   = dut_driver::type_id::create("dut_drv", this);
        dut_mon   = dut_monitor::type_id::create("dut_mon", this);
        model_drv = model_driver::type_id::create("model_drv", this);
        model_mon = model_monitor::type_id::create("model_mon", this);
        scbd      = comparison_scoreboard::type_id::create("scbd", this);
    endfunction

    // connect monitors to FIFOs, sequencer to drivers
    function void connect_phase(uvm_phase phase);
        dut_drv.seq_item_port.connect(seqr.seq_item_export);
        dut_mon.input_ap.connect(model_drv.driver_fifo.analysis_export);
        dut_mon.output_ap.connect(scbd.dut_fifo.analysis_export);
        model_mon.output_ap.connect(scbd.model_fifo.analysis_export);
    endfunction

endclass //sha256_env
  
class comparison_test extends uvm_test;
    // component factory registration macro
    `uvm_component_utils(comparison_test)
    
    // create handle to environment
    sha256_env env;

    // component factory default constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // instantiate environment
    function void build_phase(uvm_phase phase);
        env = sha256_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        // raise objection to keep phase alive
        phase.raise_objection(this);
        // print notice
        `uvm_info(get_type_name(),"Starting sequence...", UVM_MEDIUM)
        // start sequence on sequencer
        env.seq.start(env.seqr);
        // drop objection to allow phase to complete
        phase.drop_objection(this);
    endtask
    
endclass //comparison_test