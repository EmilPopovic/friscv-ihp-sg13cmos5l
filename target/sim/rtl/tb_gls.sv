// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popovic <mail@emilpopovic.me>

`timescale 1ns/1ps

// Gate-level test of the final netlist on a 4-state simulator (Icarus).
module tb_gls;

localparam real         ClkPeriod = 13.33;
localparam int unsigned TckHalf   = 2;
localparam int unsigned Timeout   = 400000;

localparam logic [31:0] IdCode   = 32'h0000_0db3;
localparam logic [31:0] Scratch0 = 32'h0300_0000;
localparam logic [31:0] Parked   = 32'd1;

localparam logic [4:0] IrIdcode = 5'h01;
localparam logic [4:0] IrDtmcs  = 5'h10;
localparam logic [4:0] IrDmi    = 5'h11;

localparam logic [6:0] DmControl  = 7'h10;
localparam logic [6:0] SbCs       = 7'h38;
localparam logic [6:0] SbAddress0 = 7'h39;
localparam logic [6:0] SbData0    = 7'h3c;

localparam logic [31:0] SbaWordRead = (32'd2 << 17) | (32'd1 << 20);
localparam logic [31:0] SbaWord     = 32'd2 << 17;
localparam logic [31:0] SbaBusy     = 32'd1 << 21;
localparam logic [31:0] SbaErrors   = (32'd7 << 12) | (32'd1 << 22);

//////////
// Pads //
//////////

logic clk    = 1'b0;
logic rst_n  = 1'b0;
logic tck    = 1'b0;
logic tms    = 1'b1;
logic tdi    = 1'b0;
logic trst_n = 1'b0;

wire clk_PAD         = clk;
wire rst_n_PAD       = rst_n;
wire jtag_tck_PAD    = tck;
wire jtag_tms_PAD    = tms;
wire jtag_tdi_PAD    = tdi;
wire jtag_trst_n_PAD = trst_n;
wire uart0_rx_PAD    = 1'b1;
wire [1:0] boot_PAD  = 2'd0;  // Park and debug

wire       heartbeat_PAD, jtag_tdo_PAD, uart0_tx_PAD;
wire       qspi0_sck_PAD, hb_ck_PAD, hb_rst_PAD;
wire [2:0] qspi0_cs_PAD;
wire [1:0] hb_cs_PAD;

// Bidirectional pads with weak pulldowns (1 if driven to 1, 0 otherwise)
wire [7:0] gpio_a_PAD;
wire [3:0] qspi0_io_PAD;
wire [7:0] hb_dq_PAD;
wire       hb_rwds_PAD;

pulldown pd_gpio [7:0] (gpio_a_PAD);
pulldown pd_qspi [3:0] (qspi0_io_PAD);
pulldown pd_dq   [7:0] (hb_dq_PAD);
pulldown pd_rwds       (hb_rwds_PAD);

RVSoC9108 dut (
    .clk_PAD         ( clk_PAD         ),
    .rst_n_PAD       ( rst_n_PAD       ),
    .heartbeat_PAD   ( heartbeat_PAD   ),
    .jtag_tck_PAD    ( jtag_tck_PAD    ),
    .jtag_tms_PAD    ( jtag_tms_PAD    ),
    .jtag_tdi_PAD    ( jtag_tdi_PAD    ),
    .jtag_trst_n_PAD ( jtag_trst_n_PAD ),
    .jtag_tdo_PAD    ( jtag_tdo_PAD    ),
    .uart0_rx_PAD    ( uart0_rx_PAD    ),
    .uart0_tx_PAD    ( uart0_tx_PAD    ),
    .boot_PAD        ( boot_PAD        ),
    .gpio_a_PAD      ( gpio_a_PAD      ),
    .qspi0_io_PAD    ( qspi0_io_PAD    ),
    .qspi0_sck_PAD   ( qspi0_sck_PAD   ),
    .qspi0_cs_PAD    ( qspi0_cs_PAD    ),
    .hb_dq_PAD       ( hb_dq_PAD       ),
    .hb_rwds_PAD     ( hb_rwds_PAD     ),
    .hb_ck_PAD       ( hb_ck_PAD       ),
    .hb_cs_PAD       ( hb_cs_PAD       ),
    .hb_rst_PAD      ( hb_rst_PAD      )
);

always #(ClkPeriod / 2) clk = ~clk;

int unsigned cycles = 0;
always @(posedge clk) cycles <= cycles + 1;

int unsigned errors = 0;

task automatic fail(input string what);
    $display("FAIL: %s (cycle %0d)", what, cycles);
    errors++;
endtask

//////////
// JTAG //
//////////

// Pulse TCK, TDO sampled before the rising edge
task automatic pulse(input logic tms_i, input logic tdi_i, output logic tdo_o);
    tms = tms_i;
    tdi = tdi_i;
    repeat (TckHalf) @(posedge clk);
    tdo_o = jtag_tdo_PAD;
    tck = 1'b1;
    repeat (TckHalf) @(posedge clk);
    tck = 1'b0;
endtask

`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-but-set-variable"
// Move through the JTAG state machine, ignore TDO
task automatic move(input logic [7:0] path, input int unsigned steps);
    logic unused;

    for (int unsigned i = 0; i < steps; i++) begin
        pulse(path[i], 1'b0, unused);
    end
endtask
`pragma diagnostic pop

// Shift data into JTAG chain, LSB first
task automatic shift(input logic [63:0] data, input int unsigned size, output logic [63:0] result);
    logic bit_out;

    result = '0;
    for (int unsigned i = 0; i < size; i++) begin
        pulse(i + 1 == size, data[i], bit_out);
        result[i] = bit_out;
    end
endtask

`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-but-set-variable"
// Shift an instruction into the JTAG IR
task automatic shift_ir(input logic [4:0] ir);
    logic [63:0] unused;

    move(8'b0011, 4);
    shift({59'd0, ir}, 5, unused);
    move(8'b01, 2);
endtask
`pragma diagnostic pop

// Shift data into the JTAG DR
task automatic shift_dr(input logic [63:0] data, input int unsigned size,
                        output logic [63:0] result);
    move(8'b001, 3);
    shift(data, size, result);
    move(8'b01, 2);
endtask

// DMI access, retry if busy
task automatic dmi(input logic [6:0] address, input logic [31:0] data,
                   input logic [1:0] op, output logic [31:0] read_data);
    logic [63:0] response;

    for (int unsigned retry = 0; retry < 8; retry++) begin
        shift_ir(IrDmi);
        shift_dr({23'd0, address, data, op}, 41, response);
        move(8'b0, 8);
        shift_dr('0, 41, response);

        if (response[1:0] == 2'd0) begin
            read_data = response[33:2];
            return;
        end

        if (response[1:0] != 2'd3) begin
            fail("DMI access failed");
            read_data = 'x;
            return;
        end

        shift_ir(IrDtmcs);
        shift_dr(64'd1 << 16, 32, response);
    end

    fail("DMI stayed busy");
    read_data = 'x;
endtask

`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-but-set-variable"
// Write to a DMI register
task automatic dmi_write(input logic [6:0] address, input logic [31:0] data);
    logic [31:0] unused;

    dmi(address, data, 2'd2, unused);
endtask
`pragma diagnostic pop

// Read from a DMI register
task automatic dmi_read(input logic [6:0] address, output logic [31:0] data);
    dmi(address, '0, 2'd1, data);
endtask

// Wait for the system bus to become idle
task automatic sba_wait();
    logic [31:0] status;

    for (int unsigned i = 0; i < 100; i++) begin
        dmi_read(SbCs, status);

        if (^status === 1'bx) begin
            fail($sformatf("SBCS reads %h", status));
            return;
        end

        if (!(status & SbaBusy)) begin
            if (status & SbaErrors) begin
                fail($sformatf("system bus error, SBCS %h", status));
            end
            return;
        end
    end

    fail("system bus stayed busy");
endtask

// Read a word from the system bus
task automatic sba_read(input logic [31:0] address, output logic [31:0] data);
    dmi_write(SbCs, SbaWordRead);
    dmi_write(SbAddress0, address);
    sba_wait();
    dmi_read(SbData0, data);
endtask

// Write a word to the system bus
task automatic sba_write(input logic [31:0] address, input logic [31:0] data);
    dmi_write(SbCs, SbaWord);
    dmi_write(SbAddress0, address);
    dmi_write(SbData0, data);
    sba_wait();
endtask

///////////
// Tests //
///////////

// Check that the output pads are known after a reset
task automatic check_outputs();
    logic [9:0] pads;

    pads = {heartbeat_PAD, uart0_tx_PAD, qspi0_sck_PAD, qspi0_cs_PAD,
            hb_ck_PAD, hb_cs_PAD, hb_rst_PAD};

    if (^pads === 1'bx) begin
        fail($sformatf("output pads unknown after reset: %b", pads));
    end
endtask

task automatic check_jtag();
    logic [63:0] value;

    // Test-Logic-Reset, then Run-Test/Idle
    move(8'b0111111, 7);

    // Read the IDCODE register
    shift_ir(IrIdcode);
    shift_dr('0, 32, value);
    // Check the IDCODE matches the expected value
    if (value[31:0] !== IdCode) begin
        fail($sformatf("IDCODE %h, expected %h", value[31:0], IdCode));
    end

    // Same for DTMCS
    shift_ir(IrDtmcs);
    shift_dr('0, 32, value);
    if (value[3:0] !== 4'd1 || value[9:4] !== 6'd7) begin
        fail($sformatf("DTMCS %h", value[31:0]));
    end

    dmi_write(DmControl, 32'd1);
endtask

// Confirm that the core is parked in the boot ROM by reading SCB.SCRATCH0
task automatic check_parked();
    logic [31:0] value;

    for (int unsigned i = 0; i < 20; i++) begin
        sba_read(Scratch0, value);

        if (value === Parked) begin
            return;
        end

        repeat (500) @(posedge clk);
    end

    fail($sformatf("boot ROM did not park, SCRATCH0 %h", value));
endtask

// Check first and last word of each OCM way (readback)
task automatic check_ocm();
    localparam int unsigned Words = 8;
    logic [31:0] address [Words] = '{
        32'h0000_0000, 32'h0000_07fc, 32'h0000_0800, 32'h0000_0ffc,
        32'h0000_1000, 32'h0000_17fc, 32'h0000_1800, 32'h0000_1ffc
    };
    logic [31:0] value;

    for (int unsigned i = 0; i < Words; i++) begin
        sba_write(address[i], 32'h5a0f_f0a5 ^ (i * 32'h0101_0101));
    end

    for (int unsigned i = 0; i < Words; i++) begin
        sba_read(address[i], value);

        if (value !== (32'h5a0f_f0a5 ^ (i * 32'h0101_0101))) begin
            fail($sformatf("OCM %h reads %h", address[i], value));
        end
    end
endtask

initial begin
    fork
        begin
            repeat (Timeout) @(posedge clk);
            fail("timeout");
            $display("FAIL (%0d errors, %0d cycles)", errors, cycles);
            $finish;
        end
    join_none

    repeat (20) @(posedge clk);
    rst_n  = 1'b1;
    trst_n = 1'b1;
    repeat (20) @(posedge clk);

    check_outputs();
    $display("reset done (cycle %0d)", cycles);
    check_jtag();
    $display("jtag done (cycle %0d)", cycles);
    check_parked();
    $display("park done (cycle %0d)", cycles);
    check_ocm();

    if (errors == 0) begin
        $display("PASS (%0d cycles)", cycles);
    end else begin
        $display("FAIL (%0d errors, %0d cycles)", errors, cycles);
    end

    $finish;
end

endmodule
