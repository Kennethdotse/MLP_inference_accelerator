module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              en,
    input  wire                              clear_acc,
    input  wire signed [DATA_WIDTH-1:0]      a,
    input  wire signed [DATA_WIDTH-1:0]      b,
    output wire signed [ACC_WIDTH-1:0]       acc_out
);

    wire signed [2*DATA_WIDTH-1:0] product;
    reg  signed [ACC_WIDTH-1:0]    acc;

    assign product = a * b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= {ACC_WIDTH{1'b0}};
        else if (clear_acc)
            acc <= {ACC_WIDTH{1'b0}};
        else if (en)
            acc <= acc + product;
    end

    assign acc_out = acc;

endmodule