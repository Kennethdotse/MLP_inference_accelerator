# MLP Inference Accelerator in Verilog

A parameterized Verilog implementation of a small multilayer perceptron (MLP) for handwritten digit classification, targeting a Zynq UltraScale+ FPGA. The network uses 8-bit fixed-point weights and runs on a time-multiplexed datapath: one multiply-accumulate (MAC) unit per layer, sequenced by a finite-state machine.

**Status:** simulation-verified. Synthesis, timing closure, and board bring-up have not been done yet.

## Model

The weights in this repo were trained offline and exported as `.mem` files. The training and quantization scripts are not included.

| | |
|---|---|
| Dataset | scikit-learn `load_digits` (1,797 grayscale 8x8 images, 10 classes) |
| Architecture | 64 -> 32 (ReLU) -> 10 |
| Weights | 8-bit signed fixed point, one power-of-2 scale per tensor (see `qformat.txt`) |

The dataset is not MNIST. The same RTL structure applies to larger networks by changing layer sizes and ROM depths.

## Verification

| Check | Result | Scope |
|---|---|---|
| Float and int8 accuracy | 96.94% (349/360) | 360 held-out images, measured offline in Python. Not reproducible from this repo. |
| Full RTL pipeline | Correct class (7), 2,561 cycles | **One image** (`known_input_0`) |

The RTL has been run on a single image. It has not been run on the full test set.

## Architecture

```
mlp_top
├── weight_rom       x5   w1, b1, w2, b2, input image (loaded with $readmemh)
├── layer_controller x2   one per layer; each owns one pe
│     └── pe                  signed multiply-accumulate
├── activation_ram   x2   hidden activations, output logits
└── argmax                picks the predicted digit
```

**Time-multiplexed MAC.** A fully parallel version of this network would need 64x32 + 32x10 = 2,368 multipliers. Here each layer reuses one `pe`. The `layer_controller` FSM clears the accumulator, streams one (input, weight) pair per clock for all inputs of a neuron, then adds the bias, rescales, applies ReLU, saturates, and writes the result. The cost is latency: 2,561 cycles per inference.

**Weight addressing.** Weights are flattened row-major, so the weight from input `i` to neuron `j` is at address `i * N_OUT + j`. ROM reads take one cycle, so the controller issues addresses one cycle ahead of the MAC.

**Fixed-point alignment.** Each tensor has its own Q-format. `ACC_SHIFT` and `OUT_SHIFT` in each `layer_controller` instance realign scales between the accumulator, bias, and next layer's input. For this model: X=6, W1=6, b1=7, A1=4, W2=5, b2=8.

**Output width.** Hidden activations are 8-bit. The final layer outputs 16-bit, because its raw logits exceed the int8 range, and clipping them to 8 bits made classes tie in `argmax`.

## Repository layout

```
pe.v                  MAC unit
weight_rom.v          parameterized ROM
activation_ram.v      parameterized RAM
argmax.v              index of the largest of N values
layer_controller.v    FSM that sequences a full layer through one pe
mlp_top.v             top-level wiring
mlp_top_tb.v          full-pipeline testbench (one image)

w1.mem  b1.mem        layer 1 weights (2048) and biases (32)
w2.mem  b2.mem        layer 2 weights (320) and biases (10)
known_input_0.mem     one quantized test image (label 7)
qformat.txt           fractional bits and shift amounts
```

## Running the simulation

Icarus Verilog:

```bash
iverilog -o mlp_sim pe.v weight_rom.v activation_ram.v argmax.v layer_controller.v mlp_top.v mlp_top_tb.v
vvp mlp_sim
```

Expected output:

```
done asserted after 2561 cycles
predicted_digit = 7  (expected 7)
PASS: full MLP pipeline correctly classified the digit
```

In Vivado, add the six design files as design sources, add `mlp_top_tb.v` and the `.mem` files as simulation sources, and set `mlp_top_tb` (not `mlp_top`) as the simulation top. Run `run -all`; the default 1000 ns run ends before the design finishes.

## Limitations

- Verified on one image in RTL.
- `ACC_SHIFT` and `OUT_SHIFT` are set by hand in `mlp_top.v` from `qformat.txt`. A wrong value gives plausible but wrong predictions with no error.
- The input image is a fixed ROM. There is no interface for loading new images at runtime.
- No timing constraints, synthesis, utilization numbers, or timing results yet.
- Layer sizes are parameters, but the two-layer structure is fixed in `mlp_top.v`.
