// =======================================================================
// Ice40Beeb
//
// A BBC Micro Model B implementation for the Ice40
//
// Copyright (C) 2017 David Banks
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/.
// =======================================================================

// The IceStorm sythesis scripts defines use_sb_io to force
// the instantaion of SB_IO (as inferrence broken)
// `define use_sb_io

module beeb
   (
    // Main clock, 100MHz
    input         clk100,
    // ARM SPI slave, to bootstrap load the ROMS
    inout         arm_ss,
    inout         arm_sclk,
    inout         arm_mosi,
    output        arm_miso,
    // SD Card SPI master
    output        ss,
    output        sclk,
    output        mosi,
    input         miso,
    // Switches
    input         sw4,
    // External RAM
    output        RAMWE_b,
    output        RAMOE_b,
    output        RAMCS_b,
    output [17:0] ADR,
    inout [7:0]   DAT,
    // Cassette / Sound
    input         cas_in,
    output        cas_out,
    output        sound,
    // Keyboard
    input         ps2_clk,
    input         ps2_data,
    // Video
    output [3:0]  red,
    output [3:0]  green,
    output [3:0]  blue,
    output        hsync,
    output        vsync
    );

   // ===============================================================
   // System Clock generation
   // ===============================================================

   // Note, it's not possible to use the iCE40 PLL to go from 100MHz to 32MHz/24MHz without some error
   reg            clock32;
   reg            clock24;
   reg [4:0]      clkdiv = 5'b0;
   reg            tmp;
   reg            wegate_b;
   always @(posedge clk100)
     begin
        // clkdiv counts 0..24, i.e. 250ns / 4MHz
        if (clkdiv == 24)
          clkdiv <= 0;
        else
          clkdiv <= clkdiv + 1;
        // 32MHz == 8 ticks in 250ns, so ~every 3 cycles
        if (clkdiv == 0 | clkdiv == 3 | clkdiv == 6 | clkdiv == 9 | clkdiv == 12 | clkdiv == 15 | clkdiv == 18 | clkdiv == 21)
          clock32 <= 1'b1;
        else
          clock32 <= 1'b0;
        // 24MHz == 6 ticks in 250ns, so ~every 4 cycles
        if (clkdiv == 0 | clkdiv == 4 | clkdiv == 8 | clkdiv == 12 | clkdiv == 16 | clkdiv == 20)
          clock24 <= 1'b1;
        else
          clock24 <= 1'b0;
        tmp <= clock32;
     end
   always @(negedge clk100)
     begin
        wegate_b <= !tmp;
     end
   // ===============================================================
   // Reset generation
   // ===============================================================

   wire      booting;
   reg [9:0] pwr_up_reset_counter = 0; // hold reset low for ~1ms
   wire      pwr_up_reset_n = &pwr_up_reset_counter;
   reg       hard_reset_n;

   always @(posedge clock32)
     begin
        if (!pwr_up_reset_n)
          pwr_up_reset_counter <= pwr_up_reset_counter + 1;
        hard_reset_n <= sw4 & pwr_up_reset_n;
     end

   wire reset = !hard_reset_n | booting;

   // ===============================================================
   // LEDs
   // ===============================================================

   wire caps_lock_led_n;
   wire shift_lock_led_n;
   wire break_led_n;

   reg        led1;
   reg        led2;
   reg        led3;
   reg        led4;

   always @(posedge clock32)
     begin
        led1 <= !caps_lock_led_n;  // blue
        led2 <= !shift_lock_led_n; // green
        led3 <= !break_led_n;      // yellow
        led4 <= !sw4;              // red
     end

   // ===============================================================
   // Bootstrap (of ROM content from ARM into RAM )
   // ===============================================================

   wire [15:0] beeb_A;
   wire        beeb_nOE;
   wire        beeb_nWE;

   wire        beeb_RAMCS_b = 1'b0;
   wire        beeb_RAMOE_b;
   wire        beeb_RAMWE_b;
   wire [17:0] beeb_RAMA;


   wire [7:0]  beeb_RAMDin;
   wire [7:0]  beeb_RAMDout = data_pins_in;

   wire        ext_RAMCS_b;
   wire        ext_RAMOE_b;
   wire        ext_RAMWE_b;
   wire [17:0] ext_RAMA;
   wire [7:0]  ext_RAMDin;

   wire        arm_ss_int;
   wire        arm_mosi_int;
   wire        arm_miso_int;
   wire        arm_sclk_int;

   bootstrap BS
     (
      .clk(clk100),
      .booting(booting),
      .progress(),
      // SPI Slave Interface (runs at 20MHz)
      .SCK(arm_sclk_int),
      .SSEL(arm_ss_int),
      .MOSI(arm_mosi_int),
      .MISO(arm_miso_int),
      // RAM from Beeb
      .beeb_RAMCS_b(beeb_RAMCS_b),
      .beeb_RAMOE_b(beeb_RAMOE_b),
      .beeb_RAMWE_b(beeb_RAMWE_b | wegate_b),
      .beeb_RAMA(beeb_RAMA),
      .beeb_RAMDin(beeb_RAMDin),
      // RAM to external SRAM
      .ext_RAMCS_b(ext_RAMCS_b),
      .ext_RAMOE_b(ext_RAMOE_b),
      .ext_RAMWE_b(ext_RAMWE_b),
      .ext_RAMA(ext_RAMA),
      .ext_RAMDin(ext_RAMDin)
   );

   // ===============================================================
   // ARM SPI Port / LED multiplexor
   // ===============================================================

   // FPGA -> ARM signals
   assign arm_miso = booting ? arm_miso_int : led2;

   // ARM -> FPGA signals
`ifdef use_sb_io
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   arm_spi_pins [2:0]
     (
      .PACKAGE_PIN({arm_ss, arm_mosi, arm_sclk}),
      .OUTPUT_ENABLE(!booting),
      .D_OUT_0({led1, led3, led4}),
      .D_IN_0({arm_ss_int, arm_mosi_int, arm_sclk_int})
      );
`else
   assign {arm_ss, arm_mosi, arm_sclk} = booting ? 3'bZ : {led1, led3, led4};
   assign {arm_ss_int, arm_mosi_int, arm_sclk_int} = {arm_ss, arm_mosi, arm_sclk};
`endif


   // ===============================================================
   // External RAM
   // ===============================================================

   assign RAMCS_b = ext_RAMCS_b;
   assign RAMOE_b = ext_RAMOE_b;
   assign RAMWE_b = ext_RAMWE_b;
   assign ADR     = ext_RAMA;

`ifdef use_sb_io
   // IceStorm cannot infer bidirectional I/Os
   wire [7:0] data_pins_in;
   wire [7:0] data_pins_out = ext_RAMDin;
   wire       data_pins_out_en = !ext_RAMWE_b;
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   sram_data_pins [7:0]
     (
      .PACKAGE_PIN(DAT),
      .OUTPUT_ENABLE(data_pins_out_en),
      .D_OUT_0(data_pins_out),
      .D_IN_0(data_pins_in)
      );
`else
   assign DAT = (ext_RAMWE_b) ? 8'bz : ext_RAMDin;
   wire [7:0] data_pins_in = DAT;
`endif



   // ===============================================================
   // Keyboard
   // ===============================================================

   wire       ps2_clk_int;
   wire       ps2_data_int;

`ifdef use_sb_io
    SB_IO #(
        .PIN_TYPE(6'b0000_01),
        .PULLUP(1'b1)
    ) ps2_io [1:0] (
        .PACKAGE_PIN({ps2_clk, ps2_data}),
        .D_IN_0({ps2_clk_int, ps2_data_int})
    );
`else
   assign ps2_clk_int = ps2_clk;
   assign ps2_data_int = ps2_data;
`endif

   // ===============================================================
   // Audio DAC
   // ===============================================================

   wire [15:0] audio;

   pwm_sddac dac
     (
     .clk_i             (clk100),
     .reset             (reset),
     .dac_i             (audio[15:6]),
     .dac_o             (sound)
      );

   assign cas_out  = 1'b0;

   // ===============================================================
   // Video
   // ===============================================================

   wire       r;
   wire       g;
   wire       b;
   wire       hs;
   wire       vs;

   assign red   = {r, r, r, r};
   assign green = {g, g, g, g};
   assign blue  = {b, b, b, b};
   assign hsync = !(vs | hs);
   assign vsync = 1'b0;

   // TODO: Add scan convertor

   // ===============================================================
   // Mist BBC Core
   // ===============================================================

   bbc BBC
     (

      .CLK32M_I(clock32),
      .CLK24M_I(clock24),
      .RESET_I(reset),

      .HSYNC(hs),
      .VSYNC(vs),

      .VIDEO_CLKEN(),
      .VIDEO_R(r),
      .VIDEO_G(g),
      .VIDEO_B(b),

      // RAM Interface (CPU)
      .ext_A(beeb_RAMA),
      .ext_nOE(beeb_RAMOE_b),
      .ext_nWE(beeb_RAMWE_b),
      .ext_Din(beeb_RAMDin),
      .ext_Dout(beeb_RAMDout),

      .MEM_SYNC(),   // signal to synchronite sdram state machine

      // Keyboard interface
      .PS2_CLK(ps2_clk_int),
      .PS2_DAT(ps2_data_int),

      // audio signal.
      .AUDIO_L(audio),
      .AUDIO_R(),

      // externally pressed "shift" key for autoboot
      .SHIFT(1'b0),

      // SD Card
      .ss(ss),
      .sclk(sclk),
      .mosi(mosi),
      .miso(miso),

      // analog joystick input
      .joy_but(2'b0),
      .joy0_axis0(8'h00),
      .joy0_axis1(8'h00),
      .joy1_axis0(8'h00),
      .joy1_axis1(8'h00),

      // boot settings
      .DIP_SWITCH(8'b00000000),

      // LEDs
      .caps_lock_led_n(caps_lock_led_n),
      .shift_lock_led_n(shift_lock_led_n),
      .break_led_n(break_led_n)
      );

endmodule
