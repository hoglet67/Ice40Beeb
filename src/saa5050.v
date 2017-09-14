//  SAA5050 teletext generator
//
//  Synchronous implementation for FPGA.  Certain TV-specific functions are
//  not implemented.  e.g.
//
//  No /SI pin - 'TEXT' mode is permanently enabled
//  No remote control features (/DATA, DLIM)
//  No large character support
//  No support for box overlay (BLAN, PO, DE)
//
//  FIXME: Hold graphics not supported - this needs to be added
//
//  Copyright (c) 2011 Mike Stirling
//  Copyright (c) 2015 Stephen J. Leary (sleary@vavi.co.uk)
//
//  All rights reserved
//
//  Redistribution and use in source and synthezised forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
//  * Redistributions in synthesized form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
//  * Neither the name of the author nor the names of other contributors may
//    be used to endorse or promote products derived from this software without
//    specific prior written agreement from the author.
//
//  * License is granted for non-commercial use only.  A fee may not be charged
//    for redistributions as source code or in synthesized/hardware form without
//    specific prior written agreement from the author.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
//  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.

module saa5050
  (
   CLOCK,
   CLKEN,
   nRESET,
   DI_CLOCK,
   DI_CLKEN,
   DI,
   GLR,
   DEW,
   CRS,
   LOSE,
   R,
   G,
   B,
   Y
   );

   input CLOCK;
   input CLKEN;
   input nRESET;
   input DI_CLOCK;
   input DI_CLKEN;
   input [6: 0] DI;
   input        GLR;
   input        DEW;
   input        CRS;
   input        LOSE;
   output       R;
   output       G;
   output       B;
   output       Y;

   //  6 MHz dot clock enable

   reg          R;
   reg          G;
   reg          B;
   reg          Y;

   //  Register inputs in the bus clock domain
   reg [6: 0]   di_r;
   reg          dew_r;
   reg          lose_r;

   //  Data input registered in the pixel clock domain
   reg [6: 0]   code;
   wire [3: 0]  line_addr;
   wire [11: 0] rom_address1;
   wire [11: 0] rom_address2;
   wire [7: 0]  rom_data1;
   wire [7: 0]  rom_data2;
   //  Delayed display enable derived from LOSE by delaying for one character
   reg          disp_enable;

   //  Latched timing signals for detection of falling edges
   reg          dew_latch;
   reg          lose_latch;
   reg          disp_enable_latch;

   //  Row and column addressing is handled externally.  We just need to
   //  keep track of which of the 10 lines we are on within the character...
   reg [3: 0]   line_counter;

   //  ... and which of the 12 pixels we are on within each line
   reg [3: 0]   pixel_counter;

   //  We also need to count frames to implement the flash feature.
   //  The datasheet says this is 0.75 Hz with a 3:1 on/off ratio, so it
   //  is probably a /64 counter, which gives us 0.78 Hz
   reg [5: 0]   flash_counter;

   //  Output shift register
   reg [11: 0]  shift_reg;

   //  Flash mask
   wire         flash;

   //  Current display state
   //  Foreground colour (B2, G1, R0)
   reg [2: 0]   fg;

   //  Background colour (B2, G1, R0)
   reg [2: 0]   bg;
   reg          conceal;
   reg          gfx;
   reg          gfx_sep;
   reg          gfx_hold;
   reg          is_flash;
   reg          double_high;

   // One-shot versions of certain control signals to support "Set-After" semantics
   reg [2:0]    fg_next;
   reg          alpha_next;
   reg          gfx_next;
   reg          gfx_release_next;
   reg          is_flash_next;
   reg          double_high_next;
   reg          unconceal_next;

   // Once char delayed versions of all of the regs seen by the ROM/Shift Register/Output Stage
   // This is to compensate for the one char delay through the control state machine
   reg [6:0]    code_r;
   reg          disp_enable_r;
   reg [2:0]    fg_r;
   reg [2:0]    bg_r;
   reg          conceal_r;
   reg          is_flash_r;

   // Last graphics character, for use by graphics hold
   reg          last_gfx_sep;
   reg [6:0]    last_gfx;
   wire         hold_active;

   //  Set in first row of double height
   reg          double_high1;

   //  Set in second row of double height
   reg          double_high2;

   //  Generate flash signal for 3:1 ratio
   assign flash = flash_counter[5] & flash_counter[4];

   //  Sync inputs
   always @(posedge DI_CLOCK or negedge nRESET) begin

      if (nRESET === 1'b0) begin
         di_r <= 7'b0;
         dew_r <= 1'b0;
         lose_r <= 1'b0;

      end else if (DI_CLKEN === 1'b1 ) begin
         di_r <= DI;
         dew_r <= DEW;
         lose_r <= LOSE;
      end
   end

   //  Register data into pixel clock domain
   always @(posedge CLOCK or negedge nRESET) begin

      if (nRESET === 1'b0) begin
         code          <= 0;
         code_r        <= 0;
         disp_enable_r <= 1'b0;
         fg_r          <= 0;
         bg_r          <= 0;
         conceal_r     <= 1'b0;
         is_flash_r    <= 1'b0;
      end else if (CLKEN === 1'b1 ) begin
         code <= di_r;
         if (pixel_counter == 0) begin
            code_r        <= code;
            disp_enable_r <= disp_enable;
            fg_r          <= fg;
            bg_r          <= bg;
            conceal_r     <= conceal;
            is_flash_r    <= is_flash;
         end
      end
   end


   //  Character row and pixel counters
   always @(posedge CLOCK or negedge nRESET) begin

      if (nRESET === 1'b0) begin
         dew_latch         <= 1'b0;
         lose_latch        <= 1'b0;
         disp_enable       <= 1'b0;
         disp_enable_latch <= 1'b0;
         double_high1      <= 1'b0;
         double_high2      <= 1'b0;
         line_counter      <= 4'b0000;
         pixel_counter     <= 3'b000;
         flash_counter     <= 6'b000000;

      end else if (CLKEN === 1'b1 ) begin

         //  Register syncs for edge detection
         dew_latch <= dew_r;
         lose_latch <= lose_r;
         disp_enable_latch <= disp_enable;

         //  When first entering double-height mode start on top row
         if (double_high === 1'b1 & double_high1 === 1'b0 &
             double_high2 === 1'b0) begin
            double_high1 <= 1'b1;
         end

         //  Count pixels between 0 and 11
         if (pixel_counter === 11) begin

            //  Start of next character and delayed display enable
            pixel_counter <= 3'b000;
            disp_enable <= lose_latch;

         end else begin
            pixel_counter <= pixel_counter + 1;
         end

         //  Rising edge of LOSE is the start of the active line
         if (lose_r === 1'b1 & lose_latch === 1'b0) begin

            //  Reset pixel counter - small offset to make the output
            //  line up with the cursor from the video ULA
            pixel_counter <= 4'b0110;
         end

         //  Count frames on end of VSYNC (falling edge of DEW)
         if (dew_r === 1'b0 & dew_latch === 1'b1) begin
            flash_counter <= flash_counter + 1;
         end

         if (dew_r === 1'b1) begin
            //  Reset line counter and double height state during VSYNC
            line_counter <= 4'b0000;
            double_high1 <= 1'b0;
            double_high2 <= 1'b0;
         end else begin
            //  Count lines on end of active video (falling edge of disp_enable)
            if (disp_enable === 1'b0 & disp_enable_latch === 1'b1) begin
               if (line_counter === 9) begin
                  line_counter <= 4'b0000;

                  //  Keep track of which row we are on for double-height
                  //  The double_high flag can be cleared before the end of a row, but if
                  //  double height characters are used anywhere on a row then the double_high1
                  //  flag will be set and remain set until the next row.  This is used
                  //  to determine that the bottom half of the characters should be shown if
                  //  double_high is set once again on the row below.
                  double_high1 <= 1'b0;
                  double_high2 <= double_high1;
               end
               else begin
                  line_counter <= line_counter + 1;
               end
            end
         end
      end
   end

   //  Control character handling

   always @(posedge CLOCK or negedge nRESET) begin

      if (!nRESET) begin
         // Current Attributes
         fg               <= 3'b111;
         bg               <= 3'b000;
         conceal          <= 1'b0;
         gfx              <= 1'b0;
         gfx_sep          <= 1'b0;
         gfx_hold         <= 1'b0;
         is_flash         <= 1'b0;
         double_high      <= 1'b0;
         // One-shot versions to support "Set-After" semantics
         fg_next          <= 3'b000;
         gfx_next         <= 1'b0;
         alpha_next       <= 1'b0;
         gfx_release_next <= 1'b0;
         is_flash_next    <= 1'b0;
         double_high_next <= 1'b0;
         unconceal_next   <= 1'b0;
         // Last graphics character
         last_gfx         <= 0;
         last_gfx_sep     <= 1'b0;
      end else if (CLKEN === 1'b1 ) begin
         if (disp_enable === 1'b0) begin
            //  Reset to start of line defaults
            fg               <= 3'b111;
            bg               <= 3'b000;
            conceal          <= 1'b0;
            gfx              <= 1'b0;
            gfx_sep          <= 1'b0;
            gfx_hold         <= 1'b0;
            is_flash         <= 1'b0;
            double_high      <= 1'b0;
            // One-shot versions to support "Set-After" semantics
            fg_next          <= 3'b000;
            gfx_next         <= 1'b0;
            alpha_next       <= 1'b0;
            gfx_release_next <= 1'b0;
            is_flash_next    <= 1'b0;
            double_high_next <= 1'b0;
            unconceal_next   <= 1'b0;
            // Last graphics character
            last_gfx         <= 0;
            last_gfx_sep     <= 1'b0;
         end else if (pixel_counter === 0 ) begin
            // One-shot versions to support "Set-After" semantics
            fg_next          <= 3'b000;
            gfx_next         <= 1'b0;
            alpha_next       <= 1'b0;
            gfx_release_next <= 1'b0;
            is_flash_next    <= 1'b0;
            double_high_next <= 1'b0;
            unconceal_next   <= 1'b0;
            // Latch the last graphic character (inc seperation), to support graphics hold
            if (code[5]) begin
               last_gfx         <= code;
               last_gfx_sep     <= gfx_sep;
            end
            //  Latch new control codes at the start of each character
            if (code[6:5] === 2'b00) begin
               if (code[3] === 1'b0) begin
                  // 0 would be black but is not allowed so has no effect
                  if (code[2:0] != 3'b000) begin
                     // Colour and graphics setting clears conceal mode - Set After
                     unconceal_next <= 1'b1;
                     // Select the foreground colout - Set After
                     fg_next <= code[2:0];
                     // Select graphics or alpha mode - Set After
                     if (code[4]) begin
                        gfx_next <= 1'b1;
                     end else begin
                        alpha_next <= 1'b1;
                        gfx_release_next <= 1'b1;
                     end
                  end
               end else begin

                  case (code[4: 0])
                    // FLASH - Set After
                    5'b01000: is_flash_next <= 1'b1;
                    //  STEADY - Set At
                    5'b01001: is_flash <= 1'b0;
                    //  NORMAL HEIGHT - Set At
                    5'b01100:
                      begin
                         double_high <= 1'b0;
                         // Graphics hold character is cleared by a *change* of height
                         if (!double_high)
                           last_gfx <= 0;
                      end
                    //  DOUBLE HEIGHT - Set After
                    5'b01101:
                      begin
                         double_high_next <= 1'b1;  //  NORMAL HEIGHT
                         // Graphics hold character is cleared by a *change* of height
                         // DMB: possible bug here ???
                         if (!double_high)
                           last_gfx <= 0;
                      end
                    //  CONCEAL - Set At
                    5'b11000: conceal <= 1'b1;
                    //  CONTIGUOUS GFX - Set At
                    5'b11001: gfx_sep <= 1'b0;
                    //  SEPARATED GFX - Set At
                    5'b11010: gfx_sep <= 1'b1;
                    //  BLACK BACKGROUND - Set At
                    5'b11100: bg <= 3'b000;
                    //  NEW BACKGROUND - Set At
                    5'b11101: bg <= (fg_next != 3'b000) ? fg_next : fg;
                    //  HOLD GFX - Set At
                    5'b11110: gfx_hold <= 1'b1;
                    //  RELEASE GFX - Set After
                    5'b11111: gfx_release_next <= 1'b1;
                  endcase
               end
            end
            // Delay the "Set After" control code effect until the next character
            if (fg_next != 3'b000)
              fg <= fg_next;
            if (gfx_next)
              gfx <= 1'b1;
            if (alpha_next)
              gfx <= 1'b0;
            if (is_flash_next)
              is_flash <= 1'b1;
            if (double_high_next)
              double_high <= 1'b1;
            if (gfx_release_next)
              gfx_hold <= 1'b0;
            // Note, conflicts can arise as setting/clearing happen in different cycles
            // e.g. 03 (Alpha Yellow) 18 (Conceal) should leave us in a conceal state
            if (conceal & unconceal_next)
              conceal <= 1'b0;
         end
      end
   end

   // --------------------------------------------------------------------
   // Character ROM
   // --------------------------------------------------------------------

   //  Generate character rom address in pixel clock domain
   //  This is done combinatorially since all the inputs are already
   //  registered and the address is re-registered by the ROM
   assign line_addr = (double_high === 1'b0)  ? line_counter :
                      (double_high2 === 1'b0) ? {1'b0, line_counter[3:1]} :
                      ({1'b0, line_counter[3:1]} + 4'd5);

   assign hold_active = gfx_hold & (code_r[6:5] == 2'b00);

   assign rom_address1 = ((double_high === 1'b0) & (double_high2 === 1'b1)) ? 12'b0 :
                         hold_active ? {gfx, last_gfx, line_addr} :
                         {gfx, code_r, line_addr};

   //  Reference row for character rounding
   assign rom_address2 = ((CRS & !double_high) | (double_high & line_counter[0])) ?
                         rom_address1 + 1'b1 :
                         rom_address1 - 1'b1;

   saa5050_rom char_rom1 (
                          .clock(CLOCK),
                          .address(rom_address1),
                          .q(rom_data1)
                          );

   saa5050_rom char_rom2 (
                          .clock(CLOCK),
                          .address(rom_address2),
                          .q(rom_data2)
                          );

   // --------------------------------------------------------------------
   //  Shift register
   // --------------------------------------------------------------------

   reg [11:0] a;
   reg [11:0] b;

   always @(posedge CLOCK or negedge nRESET) begin

      if (nRESET === 1'b0) begin

         shift_reg <= 12'b0;

      end else if (CLKEN === 1'b1 ) begin

         if (disp_enable_r === 1'b1 & pixel_counter === 0) begin

            // Character rounding

            // a is the current row of pixels, doubled up
            a = { rom_data1[5] , rom_data1[5] ,
                  rom_data1[4] , rom_data1[4] ,
                  rom_data1[3] , rom_data1[3] ,
                  rom_data1[2] , rom_data1[2] ,
                  rom_data1[1] , rom_data1[1] ,
                  rom_data1[0] , rom_data1[0] };

            // b is the adjacent row of pixels, doubled up
            b = { rom_data2[5] , rom_data2[5] ,
                  rom_data2[4] , rom_data2[4] ,
                  rom_data2[3] , rom_data2[3] ,
                  rom_data2[2] , rom_data2[2] ,
                  rom_data2[1] , rom_data2[1] ,
                  rom_data2[0] , rom_data2[0] };

            //  If bit 7 of the ROM data is set then this is a graphics
            //  character and separated/hold graphics modes apply.
            //  We don't just assume this to be the case if gfx=1 because
            //  these modes don't apply to caps even in graphics mode
            if (rom_data1[7] === 1'b1) begin
               //  Apply a mask for separated graphics mode
               if ((!hold_active & gfx_sep) | (hold_active & last_gfx_sep)) begin
                  a[10] = 1'b0;
                  a[11] = 1'b0;
                  a[4] = 1'b0;
                  a[5] = 1'b0;
                  if (line_counter === 2 | line_counter === 6 | line_counter === 9) begin
                     a = 12'b0;
                  end
               end
            end else begin
               a = a |
                   ({ 1'b0, a[11:1]} & b & ~{1'b0 , b[11:1]}) |
                   ({ a[10:0], 1'b0} & b & ~{b[10:0] , 1'b0});
            end

            //  Load the shift register with the ROM bit pattern
            //  at the start of each character while disp_enable is asserted.
            shift_reg <= a;

         end else begin
            shift_reg <= {shift_reg[10:0], 1'b0};
         end
      end
   end

   //  Output pixel calculation.
   wire pixel = shift_reg[11] & ~((flash & is_flash_r) | conceal_r);

   always @(posedge CLOCK) begin

      if (nRESET === 1'b0) begin
         R <= 1'b0;
         G <= 1'b0;
         B <= 1'b0;
      end else if (CLKEN === 1'b1 ) begin
         //  Generate mono output
         Y <= pixel;
         //  Generate colour output
         if (pixel === 1'b1) begin
            R <= fg[0];
            G <= fg[1];
            B <= fg[2];
         end else begin
            R <= bg[0];
            G <= bg[1];
            B <= bg[2];
         end
      end
   end

endmodule
