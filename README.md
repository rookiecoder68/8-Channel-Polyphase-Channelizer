# 8-Channel Polyphase Channelizer

SystemVerilog RTL implementation of an 8-channel polyphase filter-bank
channelizer with a folded 32-tap FIR front end and a pipelined 8-point FFT.
The design accepts signed 16-bit real samples and emits serialized signed
16-bit complex frequency-bin outputs.

## Architecture

The top-level datapath is:

1. `input_buffer` collects eight serial input samples into a frame.
2. `folded_fir` applies the 32-tap Hamming-windowed prototype filter as
   eight polyphase branches. Coefficients and FIR arithmetic use Q1.15
   fixed-point scaling.
3. `fft_8point_pipelined` computes the 8-point FFT through three pipelined
   butterfly stages and serializes the eight complex bins.

The reference clock is 100 MHz (10 ns period). Reset is active-low and
asynchronous.

### Top-level interface

| Port | Direction | Description |
| --- | --- | --- |
| `clk` | input | Clock |
| `rst_n` | input | Active-low asynchronous reset |
| `s_valid` | input | Valid pulse for `s_data` |
| `s_data` | input | Signed 16-bit real input sample |
| `m_valid` | output | Valid pulse for an output bin |
| `m_data_re` | output | Signed 16-bit real component |
| `m_data_im` | output | Signed 16-bit imaginary component |

Output bins are emitted serially in bin order `0` through `7`.

## Repository layout

```text
rtl/                         Synthesizable SystemVerilog RTL
  channelizer_top.sv         Top-level integration module
  input_buffer.sv             Serial-to-frame input buffer
  folded_fir.sv              Folded polyphase FIR
  fft_8point_pipelined.sv    Pipelined 8-point FFT and serializer
tb/                          Simulation and Python reference model
  tb_channelizer_top.sv      Self-checking SystemVerilog testbench
  golden_model_with_stimulus.py
  coeff_gen.py
  *.hex                      Reference coefficients, stimulus, and outputs
  verification_plots.png     Reference-model verification plot
synth/                       Synthesis, timing, and technology files
interiit_prep_front_end_report.pdf
```

## Requirements

- Icarus Verilog (or another SystemVerilog simulator)
- Python 3 with `numpy`, `scipy`, and `matplotlib`
- Yosys for synthesis
- OpenSTA for timing analysis

The commands below assume the repository root is the current directory.

## Run the RTL simulation

The checked-in testbench uses the supplied stimulus and expected-output
vectors. Compile the RTL and testbench, then run the simulator from `tb/` so
the relative coefficient and vector paths resolve correctly:

```sh
iverilog -g2012 -o tb/mysim \
  rtl/input_buffer.sv \
  rtl/folded_fir.sv \
  rtl/fft_8point_pipelined.sv \
  rtl/channelizer_top.sv \
  tb/tb_channelizer_top.sv

(cd tb && vvp mysim)
```

The testbench skips the first three pipeline frames while the FIR history
fills, then checks every real and imaginary output component against the
reference with a tolerance of ±2 LSB.

## Regenerate coefficients and reference vectors

To regenerate the FIR coefficients:

```sh
(cd tb && python3 coeff_gen.py)
```

To regenerate the stimulus, expected FFT output, and verification plot:

```sh
(cd tb && python3 golden_model_with_stimulus.py)
```

These scripts use a 32-tap Hamming-windowed low-pass prototype with cutoff
`1/8`. The stimulus contains a single-tone case, a two-tone case, and a
two-tone case with uniform noise.

## Synthesis and timing

The generic Yosys flow can be run from the repository root:

```sh
yosys -s synth/synth.ys
```

The Nangate 45 nm flow uses `synth/synth_nangate.ys`,
`synth/NangateOpenCellLibrary_typical.lib`, and the OpenSTA constraints in
`synth/constraints.sdc`. Existing mapped netlists and timing reports are
included for reference.

## Fixed-point details

- Input and output samples: signed 16-bit integers.
- FIR coefficients: signed Q1.15 values.
- FIR products are accumulated before arithmetic right-shift and
  round-half-to-even quantization.
- FIR and FFT results are saturated to the signed 16-bit range.
- FFT output is divided by eight before serialization.

## License

No license has been selected for this project yet. Add a license file before
redistributing the RTL.
