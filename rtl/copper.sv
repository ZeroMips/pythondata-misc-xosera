// copper.sv
//
// vim: set et ts=4 sw=4
//
// Copyright (c) 2021 Ross Bamford - https://github.com/roscopeco
//
// See top-level LICENSE file for license information. (Hint: MIT)
//
// The copper is controlled by XR register 0x1. Register format
//
//      [15]    - Copper enable
//      [14:11] - Reserved
//      [10:0]  - Copper initial PC
//
// Copper programs (aka 'The Copper List') live in AUX memory at 
// 0xA000. This memory segment is 2K in size.
//
// When enabled, the copper will run through as much of the program 
// as it possibly can each frame. The program is restarted at the 
// PC contained in the control register after each vblank. 
//
// You should **definitely** set up a program for the copper before
// you enable it. Once enabled, it is always running in sync with
// the pixel clock. There is no specific 'stop' or 'done' instruction
// (though the wait instruction can be used with both X and Y ignored
// as a "wait for end of frame" instruction).
//
// In the general case, most copper instructions take four pixels,
// to execute, except for WAIT and SWAP, which take five pixels.
//
// Additionally, the first instruction executed in a frame, or 
// after the copper is first enabled will take five pixels 
// (as it has to pre-fetch the first instruction). The actual
// execution is always on the last pixel of the instruction.
//
// These timings will need to be taken into account when computing
// WAIT and SKIP offsets - often you will want to use an offset 
// a number of pixels before the pixel you want the next instruction
// to actually execute on.
//
// Also note that the first instruction in a frame is pre-fetched
// at the end of the vertical blanking period such that the execution
// main execution will occur exactly on the first pixel of the frame
// (or, for WAIT and SKIP, the second, since their execution is 
// delayed by a pixel).
//
// If the copper encounters an illegal instruction, ~~it will halt
// and catch fire~~ that instruction will be ignored (wasting four pixels,
// which I guess might prove useful if you need a NOP).
//
// This means:
//
//      * Your copper program might run out of time and not finish
//      * Doing exact-pixel stuff with the copper is hard
//      * If your program does reach the end during a frame, and doesn't
//        have a terminating wait, it will run through the rest of copper
//        memory and maybe eventually start again if there's time.
//      * Assuming the common use-case of "wait for position, do thing", 
//        then none of this probably matters much...
//
// As far as the copper is concerned, all coordinates are in native
// resolution (i.e. 640x480 or 848x480). They do not account for any
// pixel doubling or other settings you may have made.
//
// The copper broadly follows the Amiga copper in terms of instructions
// (though we may add more as time progresses). There are multiple
// variants of the MOVE instruction that each move to a different place.
//
// The copper can directly MOVE to the following:
//
//      * Any Xosera XR register (including the copper control register)
//      * Xosera font memory
//      * Xosera color memory
//      * Xosera copper memory
//
// The copper **cannot** directly MOVE to the following, and this is
// by design:
//
//      * Xosera main registers
//      * Video RAM
//
// This means it's possible to change the copper program that runs on a 
// frame-by-frame basis (both from copper code and m68k program code) by 
// odifying the copper control/ register. The copper supports jumps within 
// the same frame with the JMP instruction. 
//
// Self-modifying code is supported (by modifying copper memory from your
// copper code) and of course m68k program code can modify that memory at
// will using the Xosera registers. 
//
// When modifying copper code from the m68k, and depending on the nature of
// your modifications, you may need to sync with vblank to avoid display
// artifacts.
//
// Instructions and format
//
//      MMNEMONIC - ENCODING [word1],[word2]
//          
//          ... Documentation ...
//
//
//  
//      WAIT  - [0000 oYYY YYYY YYYY],[oXXX XXXX XXXX FFFF]
//
//          Wait for a given screen position to be reached.
//
//
//      SKIP  - [0010 oYYY YYYY YYYY],[oXXX XXXX XXXX FFFF] 
//
//          Skip if a given screen position has been reached.
//
//
//      JMP   - [0100 oAAA AAAA AAAA],[oooo oooo oooo oooo]
//
//          Jump to the given copper RAM address.
//
//
//      MOVER - [1001 FFFF AAAA AAAA],[DDDD DDDD DDDD DDDD]
//
//          Move 16-bit data to XR registers.
//
//
//      MOVEF - [1010 AAAA AAAA AAAA],[DDDD DDDD DDDD DDDD]
//
//          Move 16-bit data to XR_TILE_MEM memory.
//
//
//      MOVEP - [1011 oooo AAAA AAAA],[DDDD DDDD DDDD DDDD]
//
//          Move 16-bit data to XR_COLOR_MEM (palette) memory.
//
//
//      MOVEC - [1100 oAAA AAAA AAAA],[DDDD DDDD DDDD DDDD]
//
//          Move 16-bit data to XR_COPPER_MEM memory.
//
//  
//      Y - Y position (11 bits)
//      X - X position (11 bits)
//      F - Flags
//      R - Register
//      A - Address
//      D - Data
//      o - Not used / don't care
//
//      Flags for WAIT and SKIP:
//      [0] = Ignore vertical position
//      [1] = Ignore horizontal position
//
`default_nettype none               // mandatory for Verilog sanity
`timescale 1ns/1ps                  // mandatory to shut up Icarus Verilog

`include "xosera_pkg.sv"

module copper(
    input   wire logic          clk,    
    input   wire logic          reset_i,
    output       logic          xr_ram_wr_en_o,         // General, for all RAM block writes
    output       logic [15:0]   xr_ram_wr_addr_o,       // General, for all RAM block writes
    output       logic [15:0]   xr_ram_wr_data_o,       // General, for all RAM block writes
    output       logic [10:0]   coppermem_rd_addr_o,
    output       logic          coppermem_rd_en_o,
    input   wire logic [15:0]   coppermem_rd_data_i,
    input   wire logic          regs_xr_reg_sel_i,
    input   wire logic          regs_tilemem_sel_i,
    input   wire logic          regs_colormem_sel_i,
    input   wire logic          regs_coppermem_sel_i,
    input   wire logic          copp_reg_wr_i,          // strobe to write internal config register number
    input   wire logic  [3:0]   copp_reg_num_i,         // internal config register number
    input   wire logic [15:0]   copp_reg_data_i,        // data for internal config register
    input   wire logic [10:0]   h_count_i,
    input   wire logic [10:0]   v_count_i
    );

// instruction register
typedef enum logic [3:0] {
    INSN_WAIT       = 4'b0000,
    INSN_SKIP       = 4'b0010,
    INSN_JUMP       = 4'b0100,
    INSN_MOVER      = 4'b1001,
    INSN_MOVEF      = 4'b1010,
    INSN_MOVEP      = 4'b1011,
    INSN_MOVEC      = 4'b1100
} instruction_t;

logic [31:0]  r_insn;

// execution state
typedef enum logic [2:0] {
    STATE_INIT      = 3'b000,
    STATE_WAIT      = 3'b001,
    STATE_LATCH1    = 3'b010,
    STATE_LATCH2    = 3'b011,
    STATE_EXEC      = 3'b100,
    STATE_EX_WAIT   = 3'b101,
    STATE_EX_SKIP   = 3'b110
} copper_ex_state_t;

logic  [2:0]  copper_ex_state   = STATE_INIT;

// init PC is the initial PC value after vblank
// It comes from the copper control register.
logic [10:0]  copper_init_pc;
logic [10:0]  copper_pc;
logic         copper_en;

/* verilator lint_off UNUSED */
logic [3:0]   reg_reserved;
/* verilator lint_on UNUSED */

logic         ram_rd_strobe     = 1'b0;

assign coppermem_rd_en_o        = ram_rd_strobe;
assign coppermem_rd_addr_o      = copper_pc;

logic [15:0]  ram_wr_data_out;
logic [15:0]  ram_wr_addr_out;

logic         xr_wr_strobe;

assign xr_ram_wr_en_o           = xr_wr_strobe;
assign xr_ram_wr_addr_o         = ram_wr_addr_out;
assign xr_ram_wr_data_o         = ram_wr_data_out;

logic         copp_reset;
always_comb   copp_reset  = h_count_i == xv::VISIBLE_WIDTH + xv::H_FRONT_PORCH + xv::H_SYNC_PULSE + xv::H_BACK_PORCH - 5 &&
                            v_count_i == xv::VISIBLE_HEIGHT + xv::V_FRONT_PORCH + xv::V_SYNC_PULSE + xv::V_BACK_PORCH - 1;

logic         v_reached;
logic         h_reached;

always_ff @(posedge clk) begin
    if (reset_i) begin
        copper_en               <= 1'b0;
        copper_init_pc          <= 11'h0;
        copper_pc               <= 11'h0;

        copper_ex_state         <= STATE_INIT;
        ram_rd_strobe           <= 1'b0;

        xr_wr_strobe            <= 1'b0;
    end
    else begin
        // video register write
        if (copp_reg_wr_i) begin
            case (copp_reg_num_i[3:0])
                xv::XR_COPP_CTRL[3:0]: begin
                    copper_en       <= copp_reg_data_i[15];
                    reg_reserved    <= copp_reg_data_i[14:11];
                    copper_init_pc  <= copp_reg_data_i[10:0];
                end
                default: ;
            endcase
        end

        // Main logic
        if (copp_reset) begin
            copper_ex_state         <= STATE_INIT;
            copper_pc               <= copper_init_pc;
            ram_rd_strobe           <= 1'b0;

            xr_wr_strobe            <= 1'b0;
        end
        else begin
            case (copper_ex_state)
                // State 0 - Initial begin fetch first word
                // This state is only used for the first instruction, or
                // when the copper has stalled due to contention.
                //
                // Normally, the next instruction fetch is started by the
                // EXEC state of the previous instruction.
                STATE_INIT: begin
                    if (copper_en) begin
                        // Only proceed if copper is enabled
                        copper_ex_state <= STATE_WAIT;
                        ram_rd_strobe   <= 1'b1;
                    end
                end
                // State 1 - Wait for copper RAM - Usually will jump 
                // directly here after execution of previous instruction.
                STATE_WAIT: begin
                    // Reset strobe in case previous was a MOVEx
                    // In this case, the write will happen this cycle...
                    xr_wr_strobe        <= 1'b0;

                    // Need to also check this here, as in normal running
                    // we don't go back to STATE_INIT...
                    if (copper_en) begin
                        // If copper is enabled, proceed
                        copper_ex_state <= STATE_LATCH1;
                        copper_pc       <= copper_pc + 1;
                        ram_rd_strobe   <= 1'b1;
                    end
                    else begin
                        // else, go back to INIT state and stay there...
                        copper_ex_state <= STATE_INIT;
                        ram_rd_strobe   <= 1'b0;
                    end
                end
                // State 2 - Wait for copper RAM
                STATE_LATCH1: begin
                    r_insn[31:16]   <= coppermem_rd_data_i;
                    copper_ex_state <= STATE_LATCH2;
                end
                // State 3 - Latch second word
                STATE_LATCH2: begin
                    ram_rd_strobe   <= 1'b0;
                    r_insn[15:0]    <= coppermem_rd_data_i;
                    copper_ex_state <= STATE_EXEC;
                end
                // State 4 - Execution
                STATE_EXEC: begin

                    case (r_insn[31:28])
                        INSN_WAIT: begin
                            v_reached       <= v_count_i >= r_insn[26:16];
                            h_reached       <= h_count_i >= r_insn[14:4];
                            copper_ex_state <= STATE_EX_WAIT;
                        end
                        INSN_SKIP: begin
                            v_reached       <= v_count_i >= r_insn[26:16];
                            h_reached       <= h_count_i >= r_insn[14:4];
                            copper_ex_state <= STATE_EX_SKIP;
                        end
                        INSN_JUMP: begin
                            // jmp
                            copper_pc               <= r_insn[26:16];
                            copper_ex_state         <= STATE_WAIT;
                            ram_rd_strobe           <= 1'b1;
                        end
                        // All move instructions have a second wait state, 
                        // during which next instruction read is also set
                        // up...
                        INSN_MOVER: begin
                            // mover
                            if (!regs_xr_reg_sel_i) begin
                                xr_wr_strobe            <= 1'b1;
                                ram_wr_addr_out[15:8]   <= 8'h0;
                                ram_wr_addr_out[7:0]    <= r_insn[23:16];
                                ram_wr_data_out         <= r_insn[15:0];

                                // Setup fetch next instruction
                                copper_pc               <= copper_pc + 1;
                                copper_ex_state         <= STATE_WAIT;
                                ram_rd_strobe           <= 1'b1;
                            end
                        end
                        INSN_MOVEF: begin
                            // movef
                            if (!regs_tilemem_sel_i) begin
                                xr_wr_strobe            <= 1'b1;
                                ram_wr_addr_out[15:12]  <= xv::XR_TILE_MEM[15:12];
                                ram_wr_addr_out[11:0]   <= r_insn[27:16];
                                ram_wr_data_out         <= r_insn[15:0];

                                // Setup fetch next instruction
                                copper_pc               <= copper_pc + 1;
                                copper_ex_state         <= STATE_WAIT;
                                ram_rd_strobe           <= 1'b1;
                            end
                        end
                        INSN_MOVEP: begin
                            // movep
                            if (!regs_colormem_sel_i) begin
                                xr_wr_strobe            <= 1'b1;
                                ram_wr_addr_out[15:8]   <= xv::XR_COLOR_MEM[15:8];
                                ram_wr_addr_out[7:0]    <= r_insn[23:16];
                                ram_wr_data_out         <= r_insn[15:0];

                                // Setup fetch next instruction
                                copper_pc               <= copper_pc + 1;
                                copper_ex_state         <= STATE_WAIT;
                                ram_rd_strobe           <= 1'b1;
                            end
                        end
                        INSN_MOVEC: begin
                            // movec
                            if (!regs_coppermem_sel_i) begin
                                xr_wr_strobe            <= 1'b1;
                                ram_wr_addr_out[15:11]  <= xv::XR_COPPER_MEM[15:11];
                                ram_wr_addr_out[10:0]   <= r_insn[26:16];
                                ram_wr_data_out         <= r_insn[15:0];
                        
                                // Setup fetch next instruction
                                copper_pc               <= copper_pc + 1;
                                copper_ex_state         <= STATE_WAIT;
                                ram_rd_strobe           <= 1'b1;
                            end
                        end
                        default: begin
                            // illegal instruction; just setup fetch for 
                            // next instruction
                            copper_pc       <= copper_pc + 1;
                            copper_ex_state <= STATE_WAIT;
                            ram_rd_strobe   <= 1'b1;
                        end
                    endcase // Instruction                  
                end
                // State 5 - Second state for WAIT instructions. This is where
                // the actual position is checked.
                STATE_EX_WAIT: begin
                    // executing wait
                    if (r_insn[0]) begin
                        // Ignoring vertical position
                        if (r_insn[1]) begin
                            // Ignoring horizontal position - wait
                            // forever, nothing to do... 
                        end
                        else begin
                            // Checking only horizontal position
                            if (h_reached) begin
                                // Setup fetch next instruction
                                copper_pc           <= copper_pc + 1;
                                copper_ex_state     <= STATE_WAIT;
                                ram_rd_strobe       <= 1'b1;
                            end
                            else begin
                                copper_ex_state     <= STATE_EXEC;
                            end
                        end
                    end 
                    else begin
                        // Not ignoring vertical position
                        if (r_insn[1]) begin
                            // Checking only vertical position
                            if (v_reached) begin
                                // Setup fetch next instruction
                                copper_pc           <= copper_pc + 1;
                                copper_ex_state     <= STATE_WAIT;
                                ram_rd_strobe       <= 1'b1;
                            end
                            else begin
                                copper_ex_state     <= STATE_EXEC;
                            end
                        end
                        else begin
                            // Checking both horizontal and
                            // vertical positions
                            if (h_reached && v_reached) begin
                                // Setup fetch next instruction
                                copper_pc           <= copper_pc + 1;
                                copper_ex_state     <= STATE_WAIT;
                                ram_rd_strobe       <= 1'b1;
                            end
                            else begin
                                copper_ex_state     <= STATE_EXEC;
                            end
                        end
                    end
                end
                // State 6 - Second state for SKIP instructions. This is where
                // the actual position is checked.
                STATE_EX_SKIP: begin
                    // skip
                    if (r_insn[0]) begin
                        // Ignoring vertical position
                        if (r_insn[1]) begin
                            // Ignoring horizontal position, so
                            // always skip.
                            copper_pc       <= copper_pc + 3;
                        end
                        else begin
                            // Checking only horizontal position
                            if (h_reached) begin
                                copper_pc       <= copper_pc + 3;
                            end
                            else begin
                                copper_pc       <= copper_pc + 1;
                            end
                        end
                    end 
                    else begin
                        // Not ignoring vertical position
                        if (r_insn[1]) begin
                            // Checking only vertical position
                            if (v_reached) begin
                                copper_pc       <= copper_pc + 3;
                            end
                            else begin
                                copper_pc       <= copper_pc + 1;
                            end
                        end
                        else begin
                            // Checking both horizontal and
                            // vertical positions
                            if (h_reached && v_reached) begin
                                copper_pc       <= copper_pc + 3;
                            end
                            else begin
                                copper_pc       <= copper_pc + 1;
                            end
                        end
                    end

                    // Setup fetch next instruction
                    copper_ex_state     <= STATE_WAIT;
                    ram_rd_strobe       <= 1'b1;
                end
                default: ; // Should never happen
            endcase // Execution state
        end
    end
end

endmodule

`default_nettype wire               // restore default
