# MLP Inference Accelerator in Verilog

A parameterized Verilog implementation of a small multilayer perceptron (MLP) for handwritten digit classification, targeting a Zynq UltraScale+ FPGA. A NumPy-trained model is quantized to 8-bit fixed point and run through a time-multiplexed hardware datapath: one multiply-accumulate (MAC) unit per layer, sequenced by a finite-state machine.

**Status:** simulation-verified. Synthesis, timing closure, and board bring-up have not been done yet.

## Model and dataset

| | |
|---|---|
| Dataset | scikit-learn `load_digits` (1,797 grayscale 8x8 images, 10 classes) |
| Split | 80% train / 20% test (1,437 / 360), stratified, fixed seed |
| Architecture | 64 -> 32 (ReLU) -> 10 |
| Training | NumPy, mini-batch SGD, manual backprop, 200 epochs |
| Weights | 8-bit signed fixed point, one power-of-2 scale per tensor |

The dataset is not MNIST. It is an 8x8 digits set chosen because it ships with scikit-learn and trains in seconds. The flow is the same for 784-input MNIST; only layer sizes and ROM depths change.

## Results, and what they cover

| Check | Result | Scope |
|---|---|---|
| Float model, test accuracy | 96.94% (349/360) | Full test set, Python |
| Int8 fixed-point model, test accuracy | 96.94% (349/360) | Full test set, Python integer model that mirrors the RTL arithmetic |
| MAC unit (`pe`) | Matches Python reference (-472) | One 64-element dot product, one neuron |
| Full RTL pipeline | Correct class (7), 2,561 cycles | **One image** (`known_input_0`) |

The RTL has not yet been run across the full test set. The int8 accuracy figure comes from the Python model, which is written to match the hardware arithmetic. Closing that gap (running many images through the RTL and comparing against the Python model bit for bit) is the next verification step.

Quantization note: a single global scale for all tensors dropped accuracy to 73.89% because about 15% of the second-layer weights clipped. Per-tensor scales recovered the full 96.94%.

## Architecture

```
mlp_top
├── weight_rom       x5   w1, b1, w2, b2, input image (loaded with $readmemh)
├── layer_controller x2   one per layer; each owns one pe
│     └── pe                  signed multiply-accumulate
├── activation_ram   x2   hidden activations, output logits
└── argmax                picks the predicted digit
```

**Time-multiplexed MAC.** Instead of one multiplier per weight (64x32 + 32x10 = 2,368 for this network), each layer reuses a single `pe`. The `layer_controller` FSM clears the accumulator, streams one (input, weight) pair per clock for all inputs of a neuron, then adds the bias, rescales, applies ReLU, saturates, and writes the result. The cost is latency: 2,561 cycles for one inference.

**Weight addressing.** Weights are flattened row-major, so the weight from input `i` to neuron `j` is at address `i * N_OUT + j`. ROM reads have one cycle of latency, so the controller issues addresses one cycle ahead of the MAC.

**Fixed-point alignment.** Each tensor has its own Q-format (fractional bits), listed in `qformat.txt`. `ACC_SHIFT` and `OUT_SHIFT` in each `layer_controller` instance realign scales between the accumulator, bias, and next layer's input. For this model: X=6, W1=6, b1=7, A1=4, W2=5, b2=8.

**Output width.** The hidden layer outputs stay 8-bit. The final layer outputs 16-bit, because its raw logits (for example 3011, -2349) exceed the int8 range, and clipping them to 8 bits made several classes tie and broke `argmax`.

## Repository layout

```
train_mlp.py          trains the float model, saves mlp_weights_float.npz
quantize.py           per-tensor int8 quantization, writes .mem files and qformat.txt
qformat.txt           fractional bits and shift amounts for the RTL parameters

w1.mem  b1.mem        layer 1 weights (2048) and biases (32)
w2.mem  b2.mem        layer 2 weights (320) and biases (10)
known_input_0.mem     one quantized test image (label 7)
w1_neuron0.mem        weights for hidden neuron 0 (used by pe_mnist_tb only)

pe.v                  MAC unit
weight_rom.v          parameterized ROM
activation_ram.v      parameterized RAM
argmax.v              index of the largest of N values
layer_controller.v    FSM that sequences a full layer through one pe
mlp_top.v             top-level wiring

pe_tb.v               MAC unit, hand-picked values
pe_mnist_tb.v         MAC unit, real 64-element dot product
mlp_top_tb.v          full pipeline on one image
```

## Running it

Train and quantize:

```bash
python train_mlp.py
python quantize.py
```

Simulate with Icarus Verilog:

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

In Vivado, add the six design files as design sources, add `mlp_top_tb.v` and the `.mem` files as simulation sources, and set `mlp_top_tb` (not `mlp_top`) as the simulation top. Run `run -all`; the default run length of 1000 ns ends well before the design finishes.

## Limitations

- Verified on one image in RTL (see above).
- `ACC_SHIFT` and `OUT_SHIFT` are typed into `mlp_top.v` by hand from `qformat.txt`. Retraining changes them, and a wrong value gives plausible but wrong predictions without any error.
- The input image is a fixed ROM. There is no interface for loading new images at runtime.
- No `.xdc` constraints, synthesis, utilization numbers, or timing results yet.
- Layer sizes are parameters, but the two-layer structure is fixed in `mlp_top.v`.
