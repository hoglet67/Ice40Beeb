#!/bin/bash

SRCS="../src/adc.v ../src/address_decode.v ../src/ALU.v ../src/bbc.v ../src/beeb.v ../src/bootstrap.v ../src/clocks.v ../src/cpu.v ../src/keyboard.v ../src/m6522.v ../src/mc6845.v ../src/ps2_intf.v ../src/pwm_dac.v ../src/saa5050_rom.v ../src/saa5050.v ../src/vidproc.v ../src/sn76489.v ../src/tone_generator.v"

iverilog ../src/beeb_tb.v $SRCS
./a.out  
gtkwave -g -a signals.gtkw dump.vcd
