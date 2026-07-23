module mlp_top (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    output wire done,
    output wire [3:0] predicted_digit
);

    // ---------------- Layer 1: input(64) -> hidden(32) ----------------
    wire [10:0] w1_addr; wire signed [7:0] w1_data;
    wire [4:0]  b1_addr; wire signed [7:0] b1_data;
    wire [5:0]  x_addr;  wire signed [7:0] x_data;
    wire [4:0]  a1_waddr; wire signed [7:0] a1_wdata; wire a1_we;
    wire l1_done;

    weight_rom #(.DEPTH(2048), .ADDR_WIDTH(11), .MEM_FILE("w1.mem")) w1_rom (
        .clk(clk), .addr(w1_addr), .data_out(w1_data)
    );
    weight_rom #(.DEPTH(32), .ADDR_WIDTH(5), .MEM_FILE("b1.mem")) b1_rom (
        .clk(clk), .addr(b1_addr), .data_out(b1_data)
    );
    weight_rom #(.DEPTH(64), .ADDR_WIDTH(6), .MEM_FILE("known_input_0.mem")) input_rom (
        .clk(clk), .addr(x_addr), .data_out(x_data)
    );

    // ACC_SHIFT = FX_IN+FX_W1-FX_B1 = 5, OUT_SHIFT = FX_B1-FX_A1 = 3
    // OUT_WIDTH=8: hidden activations confirmed to fit int8 with no clipping
    layer_controller #(
        .N_IN(64), .N_OUT(32),
        .DATA_WIDTH(8), .OUT_WIDTH(8),
        .X_ADDR_WIDTH(6), .W_ADDR_WIDTH(11), .B_ADDR_WIDTH(5), .O_ADDR_WIDTH(5),
        .ACC_SHIFT(5),
        .OUT_SHIFT(3),
        .APPLY_RELU(1)
    ) layer1 (
        .clk(clk), .rst_n(rst_n), .start(start), .done(l1_done),
        .x_addr(x_addr), .x_data(x_data),
        .w_addr(w1_addr), .w_data(w1_data),
        .b_addr(b1_addr), .b_data(b1_data),
        .out_addr(a1_waddr), .out_data(a1_wdata), .out_we(a1_we)
    );

    // ---------------- hidden activation storage (8-bit) ----------------
    wire [4:0] a1_raddr; wire signed [7:0] a1_rdata;

    activation_ram #(.DEPTH(32), .ADDR_WIDTH(5), .DATA_WIDTH(8)) hidden_mem (
        .clk(clk),
        .we(a1_we), .waddr(a1_waddr), .wdata(a1_wdata),
        .raddr(a1_raddr), .rdata(a1_rdata)
    );

    // ---------------- Layer 2: hidden(32) -> output(10) ----------------
    wire [8:0] w2_addr; wire signed [7:0] w2_data;
    wire [3:0] b2_addr; wire signed [7:0] b2_data;
    wire [3:0] out_waddr; wire signed [15:0] out_wdata; wire out_we;
    wire l2_done;

    weight_rom #(.DEPTH(320), .ADDR_WIDTH(9), .MEM_FILE("w2.mem")) w2_rom (
        .clk(clk), .addr(w2_addr), .data_out(w2_data)
    );
    weight_rom #(.DEPTH(10), .ADDR_WIDTH(4), .MEM_FILE("b2.mem")) b2_rom (
        .clk(clk), .addr(b2_addr), .data_out(b2_data)
    );

    // ACC_SHIFT = FX_A1+FX_W2-FX_B2 = 1
    // OUT_WIDTH=16: final logits (e.g. 3011, -2349) do NOT fit in int8 --
    // this only feeds argmax, never another MAC layer, so keep it wide
    // and skip saturation-induced ranking corruption
    layer_controller #(
        .N_IN(32), .N_OUT(10),
        .DATA_WIDTH(8), .OUT_WIDTH(16),
        .X_ADDR_WIDTH(5), .W_ADDR_WIDTH(9), .B_ADDR_WIDTH(4), .O_ADDR_WIDTH(4),
        .ACC_SHIFT(1),
        .OUT_SHIFT(0),
        .APPLY_RELU(0)
    ) layer2 (
        .clk(clk), .rst_n(rst_n), .start(l1_done), .done(l2_done),
        .x_addr(a1_raddr), .x_data(a1_rdata),
        .w_addr(w2_addr), .w_data(w2_data),
        .b_addr(b2_addr), .b_data(b2_data),
        .out_addr(out_waddr), .out_data(out_wdata), .out_we(out_we)
    );

    // ---------------- output storage (16-bit) + argmax ----------------
    wire [3:0] out_raddr; wire signed [15:0] out_rdata;

    activation_ram #(.DEPTH(10), .ADDR_WIDTH(4), .DATA_WIDTH(16)) output_mem (
        .clk(clk),
        .we(out_we), .waddr(out_waddr), .wdata(out_wdata),
        .raddr(out_raddr), .rdata(out_rdata)
    );

    argmax #(.N(10), .DATA_WIDTH(16), .ADDR_WIDTH(4)) am (
        .clk(clk), .rst_n(rst_n), .start(l2_done), .done(done),
        .best_idx(predicted_digit),
        .rd_addr(out_raddr), .rd_data(out_rdata)
    );

endmodule