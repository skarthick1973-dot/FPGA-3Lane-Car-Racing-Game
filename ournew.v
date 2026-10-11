//=============================================================================
// Project: 3-Lane Car Racing Game (Dual Control: PS/2 + Onboard Buttons)
// Board  : Enixs FC-01A (Altera Cyclone II EP2C8T144C8)
// Controls:
//   - KEY0 (Pin 113): Steer Left / Start Game Backup
//   - KEY1 (Pin 114): Steer Right Backup
//   - SW0  (Pin 72) : Toggle Start/Restart
//   - SW7  (Pin 92) : System Reset (Keep UP)
//   - PS/2 Keyboard : Space/A/D (Kept fully synthesized)
//=============================================================================

module ournew(
    input  wire        clk_50m,    // Pin 88 (50 MHz Crystal)
    input  wire        reset_n,    // Pin 92 (SW7: Active-low reset, keep UP)
    input  wire        sw_start,   // Pin 72 (SW0: Onboard start backup)
    input  wire        btn_left_n, // Pin 113 (KEY0: Move left / start backup)
    input  wire        btn_right_n,// Pin 114 (KEY1: Move right backup)

    input  wire        ps2_clk,    // Pin 142 (KBCLK)
    input  wire        ps2_data,   // Pin 141 (KBDAT)

    output wire        vga_hs,     // Pin 137
    output wire        vga_vs,     // Pin 139

    output reg  [3:0]  vga_r,      // Pins 122, 121, 120, 119
    output reg  [3:0]  vga_g,      // Pins 132, 129, 126, 125
    output reg  [3:0]  vga_b,      // Pins 136, 135, 134, 133

    output wire [7:0]  led         // Pins 112, 101, 100, 99, 97, 96, 94, 93
);

    ///////////////////////////////////////////////////////////
    // 1. CLOCK DIVIDER (50 MHz -> 25 MHz)
    ///////////////////////////////////////////////////////////
    reg clk25;
    always @(posedge clk_50m or negedge reset_n) begin
        if (!reset_n)
            clk25 <= 1'b0;
        else
            clk25 <= ~clk25;
    end

    ///////////////////////////////////////////////////////////
    // 2. VGA TIMING (640x480 @ 60Hz)
    ///////////////////////////////////////////////////////////
    reg [9:0] hcnt;
    reg [9:0] vcnt;

    always @(posedge clk25 or negedge reset_n) begin
        if (!reset_n) begin
            hcnt <= 10'd0;
            vcnt <= 10'd0;
        end else begin
            if (hcnt == 10'd799) begin
                hcnt <= 10'd0;
                if (vcnt == 10'd524)
                    vcnt <= 10'd0;
                else
                    vcnt <= vcnt + 1'b1;
            end else begin
                hcnt <= hcnt + 1'b1;
            end
        end
    end

    assign vga_hs   = ~((hcnt >= 10'd656) && (hcnt < 10'd752));
    assign vga_vs   = ~((vcnt >= 10'd490) && (vcnt < 10'd492));
    wire video_on   = (hcnt < 10'd640) && (vcnt < 10'd480);
    wire frame_tick = (vcnt == 10'd480) && (hcnt == 10'd0);

    ///////////////////////////////////////////////////////////
    // 3. PS/2 KEYBOARD RECEIVER
    ///////////////////////////////////////////////////////////
    reg [1:0] ps2_clk_sync;
    reg [1:0] ps2_data_sync;
    always @(posedge clk_50m or negedge reset_n) begin
        if (!reset_n) begin
            ps2_clk_sync  <= 2'b11;
            ps2_data_sync <= 2'b11;
        end else begin
            ps2_clk_sync  <= {ps2_clk_sync[0], ps2_clk};
            ps2_data_sync <= {ps2_data_sync[0], ps2_data};
        end
    end

    reg [5:0] clk_filter;
    reg       clean_ps2_clk;
    reg       clean_ps2_clk_d;

    always @(posedge clk_50m or negedge reset_n) begin
        if (!reset_n) begin
            clk_filter      <= 6'd0;
            clean_ps2_clk   <= 1'b1;
            clean_ps2_clk_d <= 1'b1;
        end else begin
            if (ps2_clk_sync[1] == clean_ps2_clk)
                clk_filter <= 6'd0;
            else begin
                clk_filter <= clk_filter + 1'b1;
                if (clk_filter == 6'd60) begin
                    clean_ps2_clk <= ps2_clk_sync[1];
                    clk_filter    <= 6'd0;
                end
            end
            clean_ps2_clk_d <= clean_ps2_clk;
        end
    end

    wire ps2_fall = (clean_ps2_clk_d == 1'b1 && clean_ps2_clk == 1'b0);

    reg [10:0] shift_reg;
    reg [3:0]  bit_count;
    reg [7:0]  rx_scancode;
    reg        scancode_valid;

    always @(posedge clk_50m or negedge reset_n) begin
        if (!reset_n) begin
            shift_reg      <= 11'd0;
            bit_count      <= 4'd0;
            rx_scancode    <= 8'd0;
            scancode_valid <= 1'b0;
        end else begin
            scancode_valid <= 1'b0;
            if (ps2_fall) begin
                shift_reg <= {ps2_data_sync[1], shift_reg[10:1]};
                if (bit_count == 4'd10) begin
                    bit_count      <= 4'd0;
                    rx_scancode    <= shift_reg[8:1];
                    scancode_valid <= 1'b1;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

    reg is_break;
    reg kb_req_start;
    reg kb_req_left;
    reg kb_req_right;

    always @(posedge clk_50m or negedge reset_n) begin
        if (!reset_n) begin
            is_break     <= 1'b0;
            kb_req_start <= 1'b0;
            kb_req_left  <= 1'b0;
            kb_req_right <= 1'b0;
        end else begin
            if (scancode_valid) begin
                if (rx_scancode == 8'hF0)
                    is_break <= 1'b1;
                else begin
                    if (!is_break) begin
                        if (rx_scancode == 8'h29 || rx_scancode == 8'h5A) kb_req_start <= 1'b1;
                        if (rx_scancode == 8'h1C || rx_scancode == 8'h6B) kb_req_left  <= 1'b1;
                        if (rx_scancode == 8'h23 || rx_scancode == 8'h74) kb_req_right <= 1'b1;
                    end
                    is_break <= 1'b0;
                end
            end else if (frame_tick) begin
                kb_req_left  <= 1'b0;
                kb_req_right <= 1'b0;
                if (state == 2'd1)
                    kb_req_start <= 1'b0;
            end
        end
    end

    ///////////////////////////////////////////////////////////
    // 4. ONBOARD PUSHBUTTON CONDITIONING (Active-Low)
    ///////////////////////////////////////////////////////////
    wire btn_left_press  = ~btn_left_n;  // KEY0 pressed
    wire btn_right_press = ~btn_right_n; // KEY1 pressed

    // Guaranteed Combined Triggers:
    wire trigger_left  = kb_req_left  || btn_left_press;
    wire trigger_right = kb_req_right || btn_right_press;
    wire trigger_start = kb_req_start || sw_start || btn_left_press || btn_right_press;

    ///////////////////////////////////////////////////////////
    // 5. GAME STATE MACHINE & 3 LANES
    ///////////////////////////////////////////////////////////
    parameter START = 2'd0;
    parameter PLAY  = 2'd1;
    parameter OVER  = 2'd2;

    reg [1:0] state;

    parameter LANE0 = 10'd200; // Left
    parameter LANE1 = 10'd320; // Center
    parameter LANE2 = 10'd440; // Right

    reg [1:0] player_lane;
    reg [9:0] player_x;

    always @(*) begin
        case (player_lane)
            2'd0:    player_x = LANE0;
            2'd1:    player_x = LANE1;
            2'd2:    player_x = LANE2;
            default: player_x = LANE1;
        endcase
    end

    ///////////////////////////////////////////////////////////
    // 6. RANDOM GENERATOR (LFSR)
    ///////////////////////////////////////////////////////////
    reg [7:0] lfsr;
    always @(posedge clk25 or negedge reset_n) begin
        if (!reset_n)
            lfsr <= 8'hA5;
        else if (frame_tick)
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
    end

    ///////////////////////////////////////////////////////////
    // 7. ENEMY CARS & COORDINATES
    ///////////////////////////////////////////////////////////
    reg [9:0] enemy_y1;
    reg [9:0] enemy_y2;
    reg [1:0] enemy_lane1;
    reg [1:0] enemy_lane2;
    reg [9:0] enemy_x1;
    reg [9:0] enemy_x2;

    always @(*) begin
        case (enemy_lane1)
            2'd0:    enemy_x1 = LANE0;
            2'd1:    enemy_x1 = LANE1;
            2'd2:    enemy_x1 = LANE2;
            default: enemy_x1 = LANE0;
        endcase

        case (enemy_lane2)
            2'd0:    enemy_x2 = LANE0;
            2'd1:    enemy_x2 = LANE1;
            2'd2:    enemy_x2 = LANE2;
            default: enemy_x2 = LANE2;
        endcase
    end

    wire col1 = (player_lane == enemy_lane1) && (enemy_y1 >= 10'd325) && (enemy_y1 <= 10'd440);
    wire col2 = (player_lane == enemy_lane2) && (enemy_y2 >= 10'd325) && (enemy_y2 <= 10'd440);
    wire collision = col1 || col2;

    reg [4:0] lane_debounce;
    reg [5:0] over_lockout;

    always @(posedge clk25 or negedge reset_n) begin
        if (!reset_n) begin
            state         <= START;
            player_lane   <= 2'd1; // Center Lane
            enemy_y1      <= 10'd0;
            enemy_y2      <= 10'd240;
            enemy_lane1   <= 2'd0;
            enemy_lane2   <= 2'd2;
            lane_debounce <= 5'd0;
            over_lockout  <= 6'd0;
        end else if (frame_tick) begin
            if (lane_debounce > 0)
                lane_debounce <= lane_debounce - 1'b1;

            case (state)
                START: begin
                    player_lane   <= 2'd1; // Center
                    enemy_y1      <= 10'd0;
                    enemy_y2      <= 10'd240;
                    enemy_lane1   <= 2'd0;
                    enemy_lane2   <= 2'd2;
                    lane_debounce <= 5'd0;
                    over_lockout  <= 6'd0;
                    if (trigger_start)
                        state <= PLAY;
                end

                PLAY: begin
                    // Shift Left: KEY0 or 'A'
                    if (trigger_left && (player_lane > 2'd0) && (lane_debounce == 0)) begin
                        player_lane   <= player_lane - 1'b1;
                        lane_debounce <= 5'd12;
                    end
                    // Shift Right: KEY1 or 'D'
                    else if (trigger_right && (player_lane < 2'd2) && (lane_debounce == 0)) begin
                        player_lane   <= player_lane + 1'b1;
                        lane_debounce <= 5'd12;
                    end

                    // Enemy 1 Fall
                    if (enemy_y1 >= 10'd480) begin
                        enemy_y1    <= 10'd0;
                        enemy_lane1 <= (lfsr[1:0] == 2'd3) ? 2'd0 : lfsr[1:0];
                    end else begin
                        enemy_y1 <= enemy_y1 + 10'd4;
                    end

                    // Enemy 2 Fall
                    if (enemy_y2 >= 10'd480) begin
                        enemy_y2    <= 10'd0;
                        enemy_lane2 <= (lfsr[3:2] == 2'd3) ? 2'd2 : lfsr[3:2];
                    end else begin
                        enemy_y2 <= enemy_y2 + 10'd5;
                    end

                    if (collision) begin
                        state        <= OVER;
                        over_lockout <= 6'd45; // 0.75-second display hold
                    end
                end

                OVER: begin
                    if (over_lockout > 0)
                        over_lockout <= over_lockout - 1'b1;
                    else begin
                        if (trigger_start)
                            state <= START;
                    end
                end

                default: state <= START;
            endcase
        end
    end

    ///////////////////////////////////////////////////////////
    // 8. GRAPHICS RENDERING
    ///////////////////////////////////////////////////////////
    wire road = (hcnt >= 10'd130) && (hcnt <= 10'd510);
    wire [9:0] road_scroll = vcnt + enemy_y1;
    wire lane_mark = ((hcnt >= 10'd258 && hcnt <= 10'd262) || (hcnt >= 10'd378 && hcnt <= 10'd382)) 
                     && (road_scroll[5]);

    wire player_car = (hcnt >= player_x - 10'd18) && (hcnt <= player_x + 10'd18) &&
                      (vcnt >= 10'd380)           && (vcnt <= 10'd440);

    wire enemy1 = (hcnt >= enemy_x1 - 10'd18) && (hcnt <= enemy_x1 + 10'd18) &&
                  (vcnt >= enemy_y1)          && (vcnt <= enemy_y1 + 10'd55);

    wire enemy2 = (hcnt >= enemy_x2 - 10'd18) && (hcnt <= enemy_x2 + 10'd18) &&
                  (vcnt >= enemy_y2)          && (vcnt <= enemy_y2 + 10'd55);

    always @(posedge clk25 or negedge reset_n) begin
        if (!reset_n) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else if (!video_on) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else begin
            case (state)
                START: begin
                    if (vcnt >= 10'd210 && vcnt <= 10'd250 && hcnt >= 10'd180 && hcnt <= 10'd460) begin
                        vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'hF;
                    end else begin
                        vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h4;
                    end
                end

                PLAY: begin
                    if (player_car) begin
                        vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'h0; // Green Player Car
                    end else if (enemy1 || enemy2) begin
                        vga_r <= 4'hF; vga_g <= 4'h2; vga_b <= 4'h2; // Red Enemy Cars
                    end else if (lane_mark) begin
                        vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'hF; // White Dashed Markers
                    end else if (road) begin
                        vga_r <= 4'h3; vga_g <= 4'h3; vga_b <= 4'h3; // Gray Asphalt Road
                    end else begin
                        vga_r <= 4'h0; vga_g <= 4'h8; vga_b <= 4'h0; // Green Borders
                    end
                end

                OVER: begin
                    if (player_car || enemy1 || enemy2) begin
                        vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'h0; // Yellow Crash Marker
                    end else begin
                        vga_r <= 4'h8; vga_g <= 4'h0; vga_b <= 4'h0; // Red Game Over Screen
                    end
                end

                default: begin
                    vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
                end
            endcase
        end
    end

    ///////////////////////////////////////////////////////////
    // 9. ONBOARD DIAGNOSTIC LEDS
    ///////////////////////////////////////////////////////////
    assign led[0] = (state == START);
    assign led[1] = (state == PLAY);
    assign led[2] = (state == OVER);
    assign led[3] = collision;
    assign led[4] = (player_lane == 2'd0); // Left Lane Active
    assign led[5] = (player_lane == 2'd1); // Center Lane Active
    assign led[6] = (player_lane == 2'd2); // Right Lane Active
    assign led[7] = trigger_start;

endmodule
