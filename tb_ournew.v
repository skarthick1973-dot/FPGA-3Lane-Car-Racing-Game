`timescale 1ns / 1ps

module tb_ournew;

    // Inputs to DUT
    reg        clk_50m;
    reg        reset_n;
    reg        sw_start;
    reg        btn_left_n;
    reg        btn_right_n;
    reg        ps2_clk;
    reg        ps2_data;

    // Outputs from DUT
    wire       vga_hs;
    wire       vga_vs;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire [7:0] led;

    // Instantiate your exact module name: ournew
    ournew uut (
        .clk_50m    (clk_50m),
        .reset_n    (reset_n),
        .sw_start   (sw_start),
        .btn_left_n (btn_left_n),
        .btn_right_n(btn_right_n),
        .ps2_clk    (ps2_clk),
        .ps2_data   (ps2_data),
        .vga_hs     (vga_hs),
        .vga_vs     (vga_vs),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b),
        .led        (led)
    );

    // 50 MHz Master Clock (20 ns period)
    initial begin
        clk_50m = 1'b0;
        forever #10 clk_50m = ~clk_50m;
    end

    // Stimulus
    initial begin
        // Reset active
        reset_n     = 1'b0;
        sw_start    = 1'b0;
        btn_left_n  = 1'b1;
        btn_right_n = 1'b1;
        ps2_clk     = 1'b1;
        ps2_data    = 1'b1;
        #100;

        // Release reset
        reset_n     = 1'b1;
        #200;

        // Start game
        sw_start    = 1'b1;
        #500;

        // Steering test: Press KEY0 (Left)
        btn_left_n  = 1'b0;
        #40000;
        btn_left_n  = 1'b1;
        #10000;

        // Steering test: Press KEY1 (Right)
        btn_right_n = 1'b0;
        #40000;
        btn_right_n = 1'b1;
        #10000;

        #150000;
        $stop;
    end

endmodule
