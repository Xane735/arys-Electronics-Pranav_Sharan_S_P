module bms_fsm #(
  // Voltage thresholds
  parameter integer DB_V   = 1000,
  parameter integer PERS_V = 50000,
  parameter integer RCV_V  = 5000,
  // Temperature thresholds
  parameter integer DB_T   = 1000,
  parameter integer PERS_T = 50000,
  parameter integer RCV_T  = 5000,
  // Current thresholds
  parameter integer DB_I   = 500,
  parameter integer PERS_I = 10000,
  parameter integer RCV_I  = 2000
)(
  input  wire clk,
  input  wire rst_n,

  // Raw flags
  input  wire ov_raw, uv_raw, ot_raw, ut_raw, oc_raw,

  // Masks (1 = enable monitoring)
  input  wire msk_ov, msk_uv, msk_ot, msk_ut, msk_oc,

  input  wire chg_en,          // charging mode indicator
  input  wire fault_clear_en,  // optional manual-clear for FAULT

  output reg  [3:0] state_1hot // {SHUTDOWN, FAULT, WARN, NORM}
);

  // ------------ Masked inputs ------------
  wire ov, uv, ot, ut, oc;
  assign ov = ov_raw & msk_ov;
  assign uv = uv_raw & msk_uv;
  assign ot = ot_raw & msk_ot;
  assign ut = ut_raw & msk_ut;
  assign oc = oc_raw & msk_oc;

  // ------------ Debounce/persist per category ------------
  wire ov_hi, ov_pers, ov_lo;
  wire uv_hi, uv_pers, uv_lo;
  wire ot_hi, ot_lo;
  wire ut_hi, ut_pers,  ut_lo;
  wire oc_hi, oc_pers,  oc_lo;

  debounce_persist #(.DB_CYCLES(DB_V), .PERS_CYCLES(PERS_V), .RCV_CYCLES(RCV_V))
  dp_ov (.clk(clk), .rst_n(rst_n), .sig_in(ov), .sig_hi(ov_hi), .sig_pers(ov_pers), .sig_lo(ov_lo));

  debounce_persist #(.DB_CYCLES(DB_V), .PERS_CYCLES(PERS_V), .RCV_CYCLES(RCV_V))
  dp_uv (.clk(clk), .rst_n(rst_n), .sig_in(uv), .sig_hi(uv_hi), .sig_pers(uv_pers), .sig_lo(uv_lo));

  debounce_persist #(.DB_CYCLES(DB_T), .PERS_CYCLES(PERS_T), .RCV_CYCLES(RCV_T))
  dp_ot (.clk(clk), .rst_n(rst_n), .sig_in(ot), .sig_hi(ot_hi), .sig_pers(/*unused*/), .sig_lo(ot_lo));

  debounce_persist #(.DB_CYCLES(DB_T), .PERS_CYCLES(PERS_T), .RCV_CYCLES(RCV_T))
  dp_ut (.clk(clk), .rst_n(rst_n), .sig_in(ut), .sig_hi(ut_hi), .sig_pers(ut_pers), .sig_lo(ut_lo));

  debounce_persist #(.DB_CYCLES(DB_I), .PERS_CYCLES(PERS_I), .RCV_CYCLES(RCV_I))
  dp_oc (.clk(clk), .rst_n(rst_n), .sig_in(oc), .sig_hi(oc_hi), .sig_pers(oc_pers), .sig_lo(oc_lo));

  // ------------ Severity (priority: SHUTDOWN > FAULT > WARN) ------------
  reg want_shutdown, want_fault, want_warn, clear_ok;

  always @* begin
    // Hard shutdown causes (policy):
    //  - Over-temp (OT) debounced high
    //  - Under-temp while charging
    //  - Over-voltage debounced high
    //  - Over-current debounced high (strict)
    //  - Undervoltage persistent (treat as hard)
    want_shutdown = ot_hi | (ut_hi & chg_en) | ov_hi | oc_hi | uv_pers;

    // Fault (persistent but not "hard"):
    want_fault    = (ov_pers | uv_pers | oc_pers | (ut_pers & ~chg_en));

    // Warn (early alerts)
    want_warn     = (uv_hi | oc_hi | (ut_hi & ~chg_en));

    // Recovery (all relevant categories stable low long enough)
    clear_ok      = ov_lo & uv_lo & ut_lo & oc_lo; // (ot_lo not needed)
  end

  // ------------ FSM ------------

  localparam [1:0] S_NORM  = 2'd0;
  localparam [1:0] S_WARN  = 2'd1;
  localparam [1:0] S_FAULT = 2'd2;
  localparam [1:0] S_SHUT  = 2'd3;

  reg [1:0] cur, nxt;

  // Next-state logic
  always @* begin
    nxt = cur;
    case (cur)
      S_SHUT: begin
        // Latch in SHUTDOWN until reset
        nxt = S_SHUT;
      end
      default: begin
        if (want_shutdown)
          nxt = S_SHUT;
        else if (want_fault)
          nxt = S_FAULT;
        else if (want_warn)
          nxt = S_WARN;
        else if (cur == S_WARN) begin
          if (clear_ok) nxt = S_NORM;
        end else if (cur == S_FAULT) begin
          // Option to manually clear fault
          if (fault_clear_en && clear_ok) nxt = S_WARN; 
        end else begin
          nxt = S_NORM;
        end
      end
    endcase
  end

  // State register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) cur <= S_NORM;
    else        cur <= nxt;
  end
    // NORMAL -> 1 , WARN -> 2 , FAULT -> 4 , SHUTDOWN -> 8
  always @* begin
    case (cur)
      S_NORM : state_1hot = 4'b0001;
      S_WARN : state_1hot = 4'b0010;
      S_FAULT: state_1hot = 4'b0100;
      S_SHUT : state_1hot = 4'b1000;
      default: state_1hot = 4'b0001;
    endcase
  end

endmodule
