#!/bin/bash

DIR=boot_c000_17fff
mkdir -p $DIR
cat os12.rom MMFS.rom basic2.rom > $DIR/beeb_roms.bin
(cd $DIR; xxd -i beeb_roms.bin > beeb_roms.h)

ls -l */beeb_roms.h
