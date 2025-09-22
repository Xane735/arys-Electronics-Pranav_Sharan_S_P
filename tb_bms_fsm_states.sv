//==============================================================
// tb_bms_fsm_states.v — Verilog-2001 TB that shows state changes
//==============================================================
`timescale 1ns/1ps

module tb_bms_fsm_states;

  // ---------------- Clock & Reset ----------------
  reg clk   = 1'b0;
  reg rst_n = 1'b0;
  always #5 clk = ~clk;   // 100 MHz

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
  localparam integer DB_V   = 5;     // debounce high (voltage)
  localparam integer PERS_V = 20;    // persistence (voltage)
  localparam integer RCV_V  = 4;     // recovery debounce (voltage)

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
    $dumpfile("bms_fsm_states.vcd");
    $dumpvars(0, tb_bms_fsm_states);
  end

  // ---------- Pretty-print state transitions ----------
  reg [3:0] last_state;
  function [127:0] state_name(input [3:0] s);
    if      (s==4'b0001) state_name = "NORM";
    else if (s==4'b0010) state_name = "WARN";
    else if (s==4'b0100) state_name = "FAULT";
    else if (s==4'b1000) state_name = "SHUTDOWN";
    else                 state_name = "ILLEGAL";
  endfunction

  // Print on every state change (and show key internal debounced/persist flags)
  always @(posedge clk) begin
    if (state_1hot !== last_state) begin
      $display("[%0t ns] STATE: %s  (ov_hi=%0b uv_hi=%0b oc_hi=%0b ot_hi=%0b ut_hi=%0b | "
               //"ov_pers=%0b uv_pers=%0b oc_pers=%0b ut_pers=%0b | "
               "chg_en=%0b)",
        $time, state_name(state_1hot),
        dut.ov_hi, dut.uv_hi, dut.oc_hi, dut.ot_hi, dut.ut_hi,
        chg_en
      );
      // Uncomment next line if you also want to print persist flags every transition:
      // $display("               PERSIST: ov=%0b uv=%0b oc=%0b ut=%0b",
      //           dut.ov_pers, dut.uv_pers, dut.oc_pers, dut.ut_pers);
      last_state <= state_1hot;
    end
  end

  // ---------- Helpers ----------
  task step(int n); begin repeat(n) @(posedge clk); end endtask

  // Drive one flag high for N cycles (then low)
  task pulse_high(ref reg sig, int cycles);
    begin sig = 1'b1; step(cycles); sig = 1'b0; end
  endtask

  // Hold high continuously for N cycles (TB decides when to drop)
  task hold_high(ref reg sig, int cycles);
    begin sig = 1'b1; step(cycles); sig = 1'b0; end
  endtask

  // Reset-and-idle helper
  task do_reset;
    begin
      rst_n = 1'b0; step(5); rst_n = 1'b1; step(2);
      $display("[%0t ns] RESET complete → expect NORM", $time);
    end
  endtask

  // ---------- Stimulus ----------
  initial begin
    // Defaults
    ov_raw = 0; uv_raw = 0; ot_raw = 0; ut_raw = 0; oc_raw = 0;
    msk_ov = 1; msk_uv = 1; msk_ot = 1; msk_ut = 1; msk_oc = 1;
    chg_en = 0;
    fault_clear_en = 0;
    last_state = 4'hx;

    // Bring out of reset
    do_reset();

    // ---------------- 1) UV short spike (<DB_V) → stay NORM ----------------
    $display("\n-- UV short spike (<DB_V) --");
    pulse_high(uv_raw, DB_V-1); step(5);

    // ---------------- 2) UV >= DB_V but < PERS_V → WARN then clear ----------------
    $display("\n-- UV sustained to WARN, then clear after RCV_V --");
    hold_high(uv_raw, DB_V+2);                 // triggers WARN
    step(RCV_V+2);                             // let it clear back to NORM

    // ---------------- 3) UV persistent (>=PERS_V) → SHUTDOWN (policy) ------------
    $display("\n-- UV persistent (>=PERS_V) → FAULT/SHUTDOWN per policy --");
    hold_high(uv_raw, PERS_V+2);               // in our DUT policy, uv_pers contributes to SHUTDOWN
    // Latched in SHUTDOWN; reset to continue tests
    do_reset();

    // ---------------- 4) OV (>=DB_V) → SHUTDOWN (hard) ---------------------------
    $display("\n-- OV debounced high → SHUTDOWN --");
    hold_high(ov_raw, DB_V+2);
    do_reset();

    // ---------------- 5) OC persistent (>=PERS_I) → FAULT -----------------------
    $display("\n-- OC persistent → FAULT --");
    hold_high(oc_raw, PERS_I+2);               // FAULT expected
    // optional: clear path (depends on DUT policy requiring clear_ok + fault_clear_en)
    fault_clear_en = 1'b1; step(RCV_I+2); fault_clear_en = 1'b0;
    step(5);

    // ---------------- 6) OT (>=DB_T) → SHUTDOWN (hard) --------------------------
    $display("\n-- OT debounced high → SHUTDOWN --");
    hold_high(ot_raw, DB_T+2);
    do_reset();

    // ---------------- 7) UT while NOT charging → WARN then FAULT (persist) ------
    $display("\n-- UT (discharge) → WARN, then FAULT on persistence --");
    chg_en = 1'b0;
    hold_high(ut_raw, DB_T+2);                 // WARN
    hold_high(ut_raw, PERS_T+2);               // may escalate to FAULT per DUT policy
    step(RCV_T+2);                             
    do_reset();

    // ---------------- 8) UT while charging → SHUTDOWN (hard) --------------------
    $display("\n-- UT during CHARGE → SHUTDOWN --");
    chg_en = 1'b1;
    hold_high(ut_raw, DB_T+2);
    do_reset();

    // ---------------- 9) Masking check: msk_uv=0, long UV → no change -----------
    $display("\n-- Masking: UV masked → no state change --");
    msk_uv = 1'b0;
    hold_high(uv_raw, PERS_V+5);               // ignored
    msk_uv = 1'b1; step(10);

    $display("\nTB complete. VCD: bms_fsm_states.vcd");
    $finish;
  end

endmodule
