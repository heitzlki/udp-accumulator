`default_nettype none

//-- 125 MHz -> MII clock divider.
//-- DIV=5  -> 25 MHz, 2-high/3-low (40/60 duty, inside the MII 35-65% spec)
//--          for 100 Mb/s.
//-- DIV=50 -> 2.5 MHz, exact 50% duty, for the 10 Mb/s fallback (also set
//--          speed = <10> in sw/gem1-emio.dtso).
//-- The output is a registered signal that yosys's clkbufmap promotes to a
//-- BUFG net; everything downstream (MAC, app, GEM1 GMII clocks, MAXIGP0)
//-- runs on it.
module clkgen #(
    parameter DIV = 5
) (
    input  wire clk125,
    output reg  clk_mii
);

  reg [5:0] cnt;

  initial begin
    cnt     = 0;
    clk_mii = 0;
  end

  always @(posedge clk125) begin
    if (cnt == DIV - 1) cnt <= 0;
    else cnt <= cnt + 1;
    clk_mii <= (cnt < DIV / 2);
  end

endmodule
