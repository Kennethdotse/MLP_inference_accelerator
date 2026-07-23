`timescale 1ns/1ps

module mlp_top_tb;

    reg clk;
    reg rst_n;
    reg start;
    wire done;
    wire [3:0] predicted_digit;

    // True label for known_input_0.mem, exported by quantize.py
    // (print at the end of quantize.py: "known_input_0.mem -> true label = 7")
    localparam [3:0] EXPECTED_DIGIT = 4'd7;

    mlp_top dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Safety timeout in case the FSM never asserts done (e.g. stuck state)
    integer timeout_cycles;
    localparam MAX_CYCLES = 100000;

    initial begin
        $dumpfile("dump_mlp_top.vcd");
        $dumpvars(0, mlp_top_tb);

        // Power-on reset
        rst_n = 0;
        start = 0;
        #20;
        rst_n = 1;
        #10;

        // Pulse start for exactly one cycle
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for the pipeline to finish (layer1 -> layer2 -> argmax),
        // with a timeout so the sim doesn't hang forever on a bug
        timeout_cycles = 0;
        while (!done && timeout_cycles < MAX_CYCLES) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (timeout_cycles >= MAX_CYCLES) begin
            $display("FAIL: TIMEOUT -- 'done' never asserted after %0d cycles", MAX_CYCLES);
            $finish;
        end

        $display("done asserted after %0d cycles", timeout_cycles);
        $display("predicted_digit = %0d  (expected %0d)", predicted_digit, EXPECTED_DIGIT);

        if (predicted_digit === EXPECTED_DIGIT)
            $display("PASS: full MLP pipeline correctly classified the digit");
        else
            $display("FAIL: predicted_digit does not match expected label");

        #20;
        $finish;
    end

    // Optional: watch done pulse in the log even if the top-level check
    // above already covers it -- useful when eyeballing the waveform
    always @(posedge clk) begin
        if (done)
            $display("[%0t] done pulsed, predicted_digit=%0d", $time, predicted_digit);
    end

endmodule