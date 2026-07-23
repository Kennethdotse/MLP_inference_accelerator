module layer_controller #(
    parameter N_IN         = 64,
    parameter N_OUT        = 32,
    parameter DATA_WIDTH   = 8,     // width of x/w/b inputs
    parameter OUT_WIDTH    = 8,     // width of this layer's OUTPUT (can differ!)
    parameter ACC_WIDTH    = 32,
    parameter X_ADDR_WIDTH = 6,
    parameter W_ADDR_WIDTH = 11,
    parameter B_ADDR_WIDTH = 5,
    parameter O_ADDR_WIDTH = 5,
    parameter ACC_SHIFT    = 5,
    parameter OUT_SHIFT    = 0,
    parameter APPLY_RELU   = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    output reg  done,

    output reg  [X_ADDR_WIDTH-1:0]       x_addr,
    input  wire signed [DATA_WIDTH-1:0]  x_data,

    output reg  [W_ADDR_WIDTH-1:0]       w_addr,
    input  wire signed [DATA_WIDTH-1:0]  w_data,

    output reg  [B_ADDR_WIDTH-1:0]       b_addr,
    input  wire signed [DATA_WIDTH-1:0]  b_data,

    output reg  [O_ADDR_WIDTH-1:0]       out_addr,
    output reg  signed [OUT_WIDTH-1:0]   out_data,
    output reg                           out_we
);

    localparam S_IDLE       = 4'd0,
               S_CLR        = 4'd1,
               S_LOOP       = 4'd2,
               S_BIAS_ADDR  = 4'd3,
               S_BIAS_ADD   = 4'd4,
               S_NEXTJ      = 4'd5,
               S_DONE       = 4'd6;

    reg [3:0] state;
    reg [$clog2(N_IN+1)-1:0]  i_cnt;
    reg [$clog2(N_OUT+1)-1:0] j_cnt;

    reg  pe_en, pe_clear;
    wire signed [ACC_WIDTH-1:0] pe_acc_out;

    pe #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) pe_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (pe_en),
        .clear_acc (pe_clear),
        .a         (x_data),
        .b         (w_data),
        .acc_out   (pe_acc_out)
    );

    wire signed [ACC_WIDTH-1:0] shifted_acc = pe_acc_out >>> ACC_SHIFT;
    wire signed [ACC_WIDTH-1:0] biased      = shifted_acc + b_data;
    wire signed [ACC_WIDTH-1:0] requant     = (OUT_SHIFT >= 0) ?
                                               (biased >>> OUT_SHIFT) :
                                               (biased <<< (-OUT_SHIFT));
    wire signed [ACC_WIDTH-1:0] relu_val    = (APPLY_RELU && requant[ACC_WIDTH-1]) ?
                                               {ACC_WIDTH{1'b0}} : requant;

    // Saturate to OUT_WIDTH bits (parameterized -- 8 for hidden layer,
    // wider e.g. 16 for a final layer whose output only feeds argmax)
    localparam signed [ACC_WIDTH-1:0] OUT_MAX = (1 <<< (OUT_WIDTH-1)) - 1;
    localparam signed [ACC_WIDTH-1:0] OUT_MIN = -(1 <<< (OUT_WIDTH-1));
    wire signed [OUT_WIDTH-1:0] sat_val =
        (relu_val > OUT_MAX) ? OUT_MAX[OUT_WIDTH-1:0] :
        (relu_val < OUT_MIN) ? OUT_MIN[OUT_WIDTH-1:0] :
        relu_val[OUT_WIDTH-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            done     <= 1'b0;
            pe_en    <= 1'b0;
            pe_clear <= 1'b0;
            out_we   <= 1'b0;
            i_cnt    <= 0;
            j_cnt    <= 0;
        end else begin
            pe_en  <= 1'b0;
            out_we <= 1'b0;
            done   <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        j_cnt <= 0;
                        state <= S_CLR;
                    end
                end

                S_CLR: begin
                    pe_clear <= 1'b1;
                    i_cnt    <= 0;
                    x_addr   <= 0;
                    w_addr   <= j_cnt;
                    state    <= S_LOOP;
                end

                S_LOOP: begin
                    pe_clear <= 1'b0;
                    pe_en    <= 1'b1;
                    if (i_cnt == N_IN-1) begin
                        b_addr <= j_cnt;
                        state  <= S_BIAS_ADDR;
                    end else begin
                        x_addr <= i_cnt + 1;
                        w_addr <= (i_cnt + 1) * N_OUT + j_cnt;
                        i_cnt  <= i_cnt + 1;
                        state  <= S_LOOP;
                    end
                end

                S_BIAS_ADDR: begin
                    state <= S_BIAS_ADD;
                end

                S_BIAS_ADD: begin
                    out_addr <= j_cnt;
                    out_data <= sat_val;
                    out_we   <= 1'b1;
                    state    <= S_NEXTJ;
                end

                S_NEXTJ: begin
                    if (j_cnt == N_OUT-1) begin
                        state <= S_DONE;
                    end else begin
                        j_cnt <= j_cnt + 1;
                        state <= S_CLR;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule