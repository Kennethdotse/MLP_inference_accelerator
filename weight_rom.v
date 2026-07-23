module weight_rom #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 2048,          // number of entries in the .mem file
    parameter ADDR_WIDTH = 11,            // must satisfy 2^ADDR_WIDTH >= DEPTH
    parameter MEM_FILE   = "w1.mem"
)(
    input  wire                          clk,
    input  wire [ADDR_WIDTH-1:0]         addr,
    output reg  signed [DATA_WIDTH-1:0]  data_out
);
    reg signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial $readmemh(MEM_FILE, mem);

    always @(posedge clk)
        data_out <= mem[addr];

endmodule