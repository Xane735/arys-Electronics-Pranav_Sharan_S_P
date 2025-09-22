module debounce_persist #(
  parameter [15:0] DB_CYCLES   = 16'd1000,   // high >= DB_CYCLES  -> sig_hi
  parameter [15:0] PERS_CYCLES = 16'd50000,  // high >= PERS_CYCLES-> sig_pers
  parameter [15:0] RCV_CYCLES  = 16'd5000    // low  >= RCV_CYCLES -> sig_lo
)(
  input  wire clk,
  input  wire rst_n,
  input  wire sig_in,    // raw (already masked) flag
  output reg  sig_hi,    // debounced high
  output reg  sig_pers,  // persistent high
  output reg  sig_lo     // debounced low (for recovery)
);

  reg [15:0] cnt_hi;
  reg [15:0] cnt_lo;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_hi   <= 16'd0;
      cnt_lo   <= 16'd0;
      sig_hi   <= 1'b0;
      sig_pers <= 1'b0;
      sig_lo   <= 1'b0;
    end else begin
      if (sig_in) begin
        if (cnt_hi < PERS_CYCLES) cnt_hi <= cnt_hi + 16'd1; // saturate
        cnt_lo <= 16'd0;
      end else begin
        if (cnt_lo < RCV_CYCLES)  cnt_lo <= cnt_lo + 16'd1; // saturate
        cnt_hi <= 16'd0;
      end

      // qualified outputs (registered)
      sig_hi   <= (cnt_hi >= DB_CYCLES);
      sig_pers <= (cnt_hi >= PERS_CYCLES);
      sig_lo   <= (cnt_lo >= RCV_CYCLES);
    end
  end
endmodule
