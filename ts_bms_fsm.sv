//==============================================================
// tb_bms_fsm.v  — Verilog-2001 testbench with VCD dump
//==============================================================
`timescale 1ns/1ps

module tb_bms_fsm;

  // ---------------- Clock & Reset ----------------
  reg clk   = 1'b0;
  reg rst_n = 1'b0;
  always #5 clk = ~clk;   // 100 MHz clock

  // ---------------- DUT I/O ----------------
  // Raw flags
  reg ov_raw, uv_raw, ot_raw, ut_raw, oc_raw;
  // Masks (1 = enabled)
  reg msk_ov, msk_uv, msk_ot, msk_ut, msk_oc;
  // Mode / control
  reg chg_en;
  reg fault_clear_en;

  wire [3:0] state_1hot; // {SHUTDOWN, FAULT, WARN, NORM}

  // ---------- Instantiate DUT with small thresholds for quick sim ----------
  // (Tweak these to your real design values later.)
  localparam integer DB_V   = 5;     // 5 cycles to warn on voltage
  localparam integer PERS_V = 20;    // 20 cycles to fault on voltage
  localparam integer RCV_V  = 4;     // 4 cycles low to clear voltage

  localparam integer DB_T   = 5;
  localparam integer PERS_T = 20;
  localparam integer RCV_T  = 4;

  localparam integer DB_I   = 3;
  localparam integer PERS_I = 12;
  localparam integer RCV_I  = 3;

  bms_fsm #(
    .DB_V(DB_V), .PERS_V(PERS_V), .RCV_V(RCV_V),
    .DB_T(DB_T), .PERS_T(PERS_T), .RCV_T(RCV_T),
    .DB_I(DB_I), .PERS_I(PERS_I), .RCV_I(RCV_I)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .ov_raw(ov_raw), .uv_raw(uv_raw), .ot_raw(ot_raw), .ut_raw(ut_raw), .oc_raw(oc_raw),
    .msk_ov(msk_ov), .msk_uv(msk_uv), .msk_ot(msk_ot), .msk_ut(msk_ut), .msk_oc(msk_oc),
    .chg_en(chg_en),
    .fault_clear_en(fault_clear_en),
    .state_1hot(state_1hot)
  );

  // ---------- VCD dump ----------
  initial begin
    $dumpfile("bms_fsm_tb.vcd");
    $dumpvars(0, tb_bms_fsm);
  end

  // ---------- Utilities ----------
  task show;
    begin
      $display("[%0t ns] state_1hot=%b  ov=%0b uv=%0b ot=%0b ut=%0b oc=%0b  chg=%0b",
               $time, state_1hot, ov_raw, uv_raw, ot_raw, ut_raw, oc_raw, chg_en);
    end
  endtask

  // ---------- Stimulus ----------
  initial begin
    // Defaults
    ov_raw = 0; uv_raw = 0; ot_raw = 0; ut_raw = 0; oc_raw = 0;
    msk_ov = 1; msk_uv = 1; msk_ot = 1; msk_ut = 1; msk_oc = 1;
    chg_en = 0;
    fault_clear_en = 0;

    // Reset
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1; @(posedge clk); show();   // expect NORM (0001)

    // 1) Brief undervoltage spike < DB_V  -> should stay NORM
    uv_raw = 1;
    repeat (DB_V-1) @(posedge clk);
    uv_raw = 0;
    repeat (5) @(posedge clk); show();   // expect still NORM

    // 2) UV >= DB_V but < PERS_V -> WARN then recover after RCV_V
    uv_raw = 1;
    repeat (DB_V+2) @(posedge clk); show(); // expect WARN (0010)
    uv_raw = 0;
    repeat (RCV_V+2) @(posedge clk); show(); // expect back to NORM (0001)

    // 3) Overcurrent persistent >= PERS_I -> FAULT
    oc_raw = 1;
    repeat (PERS_I+2) @(posedge clk); show(); // expect FAULT (0100)
    oc_raw = 0;

    // Optional manual clear path (depends on DUT policy)
    fault_clear_en = 1;
    repeat (RCV_I+2) @(posedge clk);
    fault_clear_en = 0; show(); // expect WARN or NORM per DUT policy (here WARN->NORM path gated)

    // 4) Over-temp (OT) >= DB_T -> immediate SHUTDOWN (latched)
    ot_raw = 1;
    repeat (DB_T+1) @(posedge clk); show(); // expect SHUTDOWN (1000)
    ot_raw = 0;
    repeat (10) @(posedge clk); show();     // remain SHUTDOWN (latched)

    // 5) Reset to recover from SHUTDOWN
    rst_n = 0; repeat (3) @(posedge clk); rst_n = 1; @(posedge clk); show(); // NORM

    // 6) Undertemp while charging -> SHUTDOWN
    chg_en = 1;
    ut_raw = 1;
    repeat (DB_T+1) @(posedge clk); show(); // expect SHUTDOWN
    ut_raw = 0;

    // Finish
    repeat (10) @(posedge clk);
    $display("TB complete. Open bms_fsm_tb.vcd in GTKWave.");
    $finish;
  end

endmodule
