module activation_ram #(
    parameter DEPTH      = 32,
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 8
)(
    input  wire                          clk,
    input  wire                          we,
    input  wire [ADDR_WIDTH-1:0]         waddr,
    input  wire signed [DATA_WIDTH-1:0]  wdata,
    input  wire [ADDR_WIDTH-1:0]         raddr,
    output reg  signed [DATA_WIDTH-1:0]  rdata
);
    reg signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule