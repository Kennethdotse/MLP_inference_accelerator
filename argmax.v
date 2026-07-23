module argmax #(
    parameter N          = 10,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    output reg  done,
    output reg  [ADDR_WIDTH-1:0] best_idx,

    output reg  [ADDR_WIDTH-1:0]         rd_addr,
    input  wire signed [DATA_WIDTH-1:0]  rd_data
);
    localparam S_IDLE = 2'd0, S_ADDR = 2'd1, S_CMP = 2'd2, S_DONE = 2'd3;

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] k;
    reg signed [DATA_WIDTH-1:0] best_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; done <= 0; best_idx <= 0; best_val <= 0; k <= 0;
        end else begin
            done <= 0;
            case (state)
                S_IDLE: if (start) begin
                    k <= 0; rd_addr <= 0; best_idx <= 0;
                    best_val <= {1'b1, {(DATA_WIDTH-1){1'b0}}};
                    state <= S_ADDR;
                end
                S_ADDR: state <= S_CMP;
                S_CMP: begin
                    if (rd_data > best_val) begin
                        best_val <= rd_data;
                        best_idx <= k;
                    end
                    if (k == N-1) begin
                        state <= S_DONE;
                    end else begin
                        k <= k + 1;
                        rd_addr <= k + 1;
                        state <= S_ADDR;
                    end
                end
                S_DONE: begin done <= 1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule