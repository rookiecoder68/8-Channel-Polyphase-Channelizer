#!/bin/sh
set -eu

yosys -s synth_nangate.ys

# OpenSTA 2.0.17 accepts the mapped cells but not the SystemVerilog
# signed-net declaration emitted by Yosys.
tmp_netlist=$(mktemp)
trap 'rm -f "$tmp_netlist"' EXIT
sed -E 's/\bsigned[[:space:]]+//g' \
    synth_nangate_netlist.v > "$tmp_netlist"
mv "$tmp_netlist" synth_nangate_netlist.v

sta timing.sta
