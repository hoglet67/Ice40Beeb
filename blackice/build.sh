#!/bin/bash

TOP=beeb
NAME=beeb
PACKAGE=tq144:4k
SRCS="../src/adc.v ../src/address_decode.v ../src/ALU.v ../src/bbc.v ../src/beeb.v ../src/bootstrap.v ../src/clocks.v ../src/cpu.v ../src/keyboard.v ../src/m6522.v ../src/mc6845.v ../src/ps2_intf.v ../src/pwm_dac.v ../src/saa5050_rom.v ../src/saa5050.v ../src/vidproc.v"

yosys -q -f "verilog -Duse_sb_io" -l ${NAME}.log -p "synth_ice40 -top ${TOP} -abc2 -blif ${NAME}.blif" ${SRCS}
arachne-pnr -d 8k -P ${PACKAGE} -p blackice.pcf ${NAME}.blif -o ${NAME}.txt
icepack ${NAME}.txt ${NAME}.bin
icetime -d hx8k -P ${PACKAGE} -t ${NAME}.txt
truncate -s 135104 ${NAME}.bin
