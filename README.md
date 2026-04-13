# Highly scalable and Parametrised Feed-Forward Neural Network using HDL (Verilog)

*Overview:* This project implements a highly parametrized feed-forward neural network inference engine on an FPGA using Verilog HDL, targeting the MNIST handwritten digit classification task. The network architecture consists of four fully-connected hidden layers followed by a 10-class output layer, where each neuron performs a fixed-point dot product using Q1.15 quantized weights and Q2.30 quantized biases loaded from pre-initialized ROM memories. Hardware computation is orchestrated through a hierarchical Finite State Machine (FSM) handshake protocol, where a top-level FSM sequences layers serially while each layer runs its neurons in parallel using synthesizable generate loops. Inside every neuron, a chunk-based Algorithmic State Machine (ASM) pipelines the Weight Fetch, Parallel Multiplication, Accumulation, and ReLU Activation stages using dedicated sub-modules with valid/done handshake signals. The software-hardware integration is achieved through a Python-based training and quantization pipeline that converts TensorFlow floating-point weights into two's complement binary files, which Verilog consumes directly via `$readmemb()` at simulation initialization. The final classification is produced by a combinational argmax block in the output layer that compares raw signed logits across all 10 output neurons and outputs the predicted digit as a 4-bit index.

---

## Table of Contents

1. [Project Goal](#1-project-goal)
2. [How a Neural Network Works](#2-how-a-neural-network-works)
3. [Software–Hardware Integration Overview](#3-softwarehardware-integration-overview)
4. [Fixed-Point Number Formats](#4-fixed-point-number-formats)
5. [Parameter Reference Table](#5-parameter-reference-table)
6. [File Naming Convention](#6-file-naming-convention)
7. [Software Code](#7-software-code)
8. [Hardware Code](#8-hardware-code)
9. [How to Run](#9-how-to-run)
10. [Major Strengths](#10-Strengths-of-This-Implementation)
11. [Future Improvements](#11-Future-Improvements)

---

## 1. Project Goal

- **Primary Objective:** Implement a complete feed-forward neural network inference engine on an FPGA using Verilog HDL that classifies handwritten digits from the MNIST dataset.
- **Training in Software:** The network is trained using TensorFlow/Keras in Python, producing a floating-point model with learned weights and biases.
- **Deployment in Hardware:** Trained weights are quantized to fixed-point binary and stored as `.txt` files. Verilog loads them into on-chip ROM and performs the full forward pass — weighted sum, bias addition, ReLU activation, and argmax — with no CPU involvement during inference.
- **Key Achievement:** A complete end-to-end pipeline from floating-point model training in Python to synthesizable RTL inference in Verilog.

---

## 2. How a Neural Network Works

![Neural Network Architecture](https://github.com/vishking741/Neural_network_HDL/blob/main/Neural_network_image.png)

### 2.1 Basic Structure

- **Input Layer:** Receives raw data. For MNIST, a flattened 28×28 image = **784 input values**.
- **Hidden Layers:** Fully-connected intermediate layers where the network learns features. Each neuron connects to every neuron in the previous layer.
- **Output Layer:** One neuron per class. For MNIST, **10 neurons** (digits 0–9).

### 2.2 What Each Neuron Does

1. **Weighted Sum:** `sum = (input_0 × weight_0) + (input_1 × weight_1) + ... + (input_N × weight_N)`
2. **Bias Addition:** `z = sum + bias`
3. **Activation:** Hidden neurons use **ReLU** (clips negatives to zero). Output neurons use **no activation** — they output raw logits for argmax comparison.

### 2.3 Concept-to-Hardware Mapping

| Neural Network Concept | Hardware Implementation |
|---|---|
| Input Layer (784 pixels) | Wide input bus: `784 × 16 = 12544 bits` into `Neural_Network.v` |
| N neurons in parallel per layer | `Neuron_Layer.v` uses `generate` to instantiate N `Neuron_ASM` modules |
| Weighted sum inside a neuron | `Weight_ROM_mod` → `multiplier_block` → `accumilator` pipeline |
| Bias addition | Inside `accumilator.v`, loaded from `.txt` file |
| ReLU activation | `activation.v` with saturation and fixed-point truncation |
| Output Layer (10 classes) | `Output_Layer.v` with 10 `Out_neuron` modules, no ReLU |
| Classification | Combinational argmax block in `Output_Layer.v` |
| Layer sequencing | 7-state FSM in `Neural_Network.v` using `layer_done` handshake |

### 2.4 Network Architecture

```
Input: 784 → Hidden Layer 1: 256 neurons → Hidden Layer 2: 128 neurons
       → Hidden Layer 3: 64 neurons → Hidden Layer 4: 32 neurons
       → Output Layer: 10 neurons → argmax → Predicted Digit (0–9)
```

---

## 3. Software–Hardware Integration Overview

The integration rests on a **file-based contract** between Python and Verilog.

```
Train Model (Python)  →  Export Weights (Python)  →  .txt Files  →  $readmemb() (Verilog)
```

- Python writes **binary-encoded fixed-point values** into `.txt` files with names the Verilog `generate` loops produce at elaboration time.
- Verilog uses `$readmemb()` to load files into ROM at simulation start — no intermediate tool needed.
- All negative values use **two's complement**, which Verilog's `$signed()` cast handles natively.

### Quantization Bridge

| Data | Software Format | Hardware Format | Scale Factor |
|---|---|---|---|
| Weights | `float32` | Q1.15 — 16-bit signed | 2^15 = 32768 |
| Biases | `float32` | Q2.30 — 32-bit signed | 2^30 = 1,073,741,824 |
| Products (internal) | — | 32-bit full precision (2×D_W) | — |
| Accumulator output | — | `2*D_W + $clog2(N+1)` bits | — |

---

## 4. Fixed-Point Number Formats

### Q1.15 — Weights

```
Bit 15       Bits 14 ... 0
[Sign]       [Fractional — 15 bits]
```

| Property | Value |
|---|---|
| Total bits | 16 |
| Fractional bits | 15 |
| Scale factor | 2^15 = 32768 |
| Value range | [-1.0, +0.99997] |
| Max (hex) | 0x7FFF |
| Min (hex) | 0x8000 |
| Example: +0.5 | 0x4000 = `0100000000000000` |
| Example: −0.25 | 0xE000 = `1110000000000000` |

### Q2.30 — Biases

```
Bit 31   Bit 30       Bits 29 ... 0
[Sign]   [Integer]    [Fractional — 30 bits]
```

| Property | Value |
|---|---|
| Total bits | 32 |
| Integer bits | 1 |
| Fractional bits | 30 |
| Scale factor | 2^30 = 1,073,741,824 |
| Value range | [-2.0, +1.99999] |
| Example: +0.1 | integer 107,374,182 |

### Internal Precision Flow

| Stage | Width | Format | Note |
|---|---|---|---|
| Weight × Input | 32 bits | Q2.30 | Full precision, no overflow |
| Accumulator running sum | `2*D_W + $clog2(N+1)` | Extended | Guard bits prevent overflow over N additions |
| Activation output | 16 bits | Q1.15 | After saturation + truncation |
| Output neuron output | `2*D_W + $clog2(N+1)` | Extended | Raw logit, passed directly to argmax |

---

## 5. Parameter Reference Table

| Parameter | Where Used | Default | Meaning |
|---|---|---|---|
| `D_W` | All modules | 16 | Data width per value in bits |
| `P` | Neuron_ASM, multiplier, ROM | 2 | Parallel multiplications per cycle — main speed/area knob |
| `INT_W` | Neural_Network, activation | 1 | Integer bits in Q fixed-point |
| `inputNum` | Neural_Network | 784 | Number of network inputs |
| `outNum` | Neural_Network | 10 | Number of output classes |
| `NUM_NEURONS` | Neuron_Layer, Output_Layer | varies | Neurons in the layer |
| `LayerNum` | Neuron_Layer | 1–4 | Layer index — used for `.txt` file name generation |
| `N` | Neuron_ASM, accumilator, ROM | varies | Number of inputs to each neuron |
| `A_W` | Neuron_ASM, ROM | `$clog2(N)` | ROM address width |
| `weightFile` | ROM | auto-generated | Path to weight `.txt` file |
| `biasFile` | accumilator | auto-generated | Path to bias `.txt` file |

---

## 6. File Naming Convention

The naming contract between Python and Verilog is exact — do not change it.

### Hidden Layers (1–4)

| File | Contains | Example |
|---|---|---|
| `w_[L]_[NNN].txt` | All weights for neuron N in layer L | `w1_000.txt` = Layer 1, Neuron 0 |
| `b_[L]_[NNN].txt` | Bias for neuron N in layer L | `b3_005.txt` = Layer 3, Neuron 5 |

**Note:**
- Neuron indices are **zero-padded to 3 digits (000–255)**.
- This supports up to 256 neurons per layer.
- Example sequence:
  - `w1_000.txt`, `w1_001.txt`, ..., `w1_255.txt`
  - `b1_000.txt`, `b1_001.txt`, ..., `b1_255.txt`

---

### Output Layer

| File | Contains | Example |
|---|---|---|
| `o_w_[N].txt` | Weights for output neuron N | `o_w_7.txt` |
| `o_b_[N].txt` | Bias for output neuron N | `o_b_0.txt` |

**Note:**
- Output layer indices are **not zero-padded** (since there are only 10 classes).

---

### File Format

- **Weight files:** N lines, each a 16-bit binary string (Q1.15 two's complement), one weight per line.
- **Bias files:** 1 line, a 32-bit binary string (Q2.30 two's complement). No headers, no spaces.
## 7. Software Code

### 7.1 Training Script

**Purpose:** Trains the neural network on MNIST and saves the model.

- Loads MNIST, normalizes pixels to [0.0, 1.0].
- Architecture: `Flatten → Dense(256, ReLU) → Dense(128, ReLU) → Dense(64, ReLU) → Dense(32, ReLU) → Dense(10, no activation)`.
- Optimizer: **Adam** (lr=0.001), Loss: **Sparse Categorical Cross-Entropy**.
- Trains for **15 epochs**, batch size **64**. Saves as `mnist_model.keras`.


```python
def build_model():
    inputs = tf.keras.Input(shape=(28, 28))
    x = tf.keras.layers.Flatten()(inputs)
    x = tf.keras.layers.Dense(256, activation='relu')(x)
    x = tf.keras.layers.Dense(128, activation='relu')(x)
    x = tf.keras.layers.Dense(64,  activation='relu')(x)
    x = tf.keras.layers.Dense(32,  activation='relu')(x)
    outputs = tf.keras.layers.Dense(10)(x)   # Raw logits, no activation
    return tf.keras.Model(inputs=inputs, outputs=outputs)
```

---

### 7.2 Weight Export Script

**Purpose:** Quantizes trained weights to fixed-point binary and writes the `.txt` files for Verilog.

- Loads `mnist_model.keras`, filters Dense layers only.
- Per neuron: writes one weight file (N × 16-bit lines) and one bias file (1 × 32-bit line).
- Output goes into `weight_files/` directory.

**Core conversion functions:**

```python
def float_to_q1_15(value):
    scaled = int(round(value * 32768.0))
    return max(-32768, min(32767, scaled))

def float_to_q2_30(value):
    scaled = int(round(value * 1073741824.0))
    return max(-2147483648, min(2147483647, scaled))

def to_binary_16bit(value):
    if value < 0:
        value = value + (1 << 16)   # Two's complement
    return format(value, '016b')
```

**Output directory structure:**
```
weight_files/
├── w1_0.txt, b1_0.txt     ← Layer 1, Neuron 0
├── w1_1.txt, b1_1.txt     ← Layer 1, Neuron 1
├── ...
├── o_w_0.txt, o_b_0.txt   ← Output Layer, Neuron 0
└── o_w_9.txt, o_b_9.txt   ← Output Layer, Neuron 9
```

---

### 7.3 Input Data Generation

Input images are stored in the `test_mnist_images` folder and are converted into fixed-point format compatible with the hardware.

- **Input format:** `.png` grayscale mnist images  
- **Resolution:** Resized to 28 × 28  
- **Normalization:** Pixel values scaled from [0, 255] → [0, 1]  
- **Fixed-point format:** Q1.15 (16-bit unsigned for inputs)  
- **Output:** 784 values per image, each written as a 16-bit binary string  
- **Output naming:** `<image_name>_q15.txt`  
  - Example: `digit3.png` → `digit3_q15.txt`

Each output file contains exactly 784 lines (one per pixel), with no headers or spaces.

---

## 8. Hardware Code

### 8.1 Module Hierarchy

```
Neural_Network.v                         ← TOP MODULE
│
├── Neuron_Layer.v  (×4 hidden layers)
│   └── Neuron_ASM.v  (×NUM_NEURONS, all parallel via generate)
│       ├── Weight_ROM_mod.v
│       ├── multiplier_block.v
│       ├── accumilator.v
│       └── activation.v
│
└── Output_Layer.v
    └── Out_neuron.v  (×10, parallel via generate)
        ├── Weight_ROM_mod.v
        ├── multiplier_block.v
        └── accumilator.v            ← No activation — raw logits to argmax
```

---

### 8.2 Top Module — Neural_Network.v

**Role:** Orchestrates the entire inference — sequences layers and connects inter-layer data buses.

#### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | In | 1 | System clock |
| `network_rst` | In | 1 | Synchronous reset |
| `network_start` | In | 1 | Pulse high to begin inference |
| `network_in` | In | 12544 | Full image as packed Q1.15 bus |
| `network_out` | Out | 4 | Predicted digit (0–9) |
| `network_done` | Out | 1 | Pulses high 1 cycle on completion |

#### FSM

```
IDLE → LAYER_1 → LAYER_2 → LAYER_3 → LAYER_4 → OUT_RUN → FINISH → IDLE
```

Each state asserts `layer_start_sigs[n]`, waits for `layer_done_sigs[n]`, then moves on. `FINISH` pulses `network_done` for one cycle and returns to IDLE.

#### Inter-Layer Buses

| Bus | Width | Carries |
|---|---|---|
| `L1_to_L2` | 4096 bits | Hidden Layer 1 outputs (256 × 16) |
| `L2_to_L3` | 2048 bits | Hidden Layer 2 outputs (128 × 16) |
| `L3_to_L4` | 1024 bits | Hidden Layer 3 outputs (64 × 16) |
| `L4_to_OUT` | 512 bits | Hidden Layer 4 outputs (32 × 16) |

---

### 8.3 Neuron_Layer.v

**Role:** Parallel container — instantiates all neurons in a layer simultaneously via `generate`, broadcasts `layer_start`, and uses a reduction AND (`&done_each`) to assert `layer_done` only when every neuron finishes.

- File names auto-generated at elaboration using ASCII math: `LayerNum[7:0] + 8'h30` → produces `w1_0.txt`, `w2_3.txt`, etc.
- **Limitation:** Single-digit indices only (0–9). Neuron counts beyond 9 need a different naming scheme.

---

### 8.4 Neuron_ASM.v

**Role:** Core hidden-layer neuron. Sequences through a 6-state ASM, processing inputs in chunks of P.

| State | Action |
|---|---|
| `IDLE` | Wait for `neuron_start`, clear all state |
| `W_F` | Enable ROM read at address `i`, slice P inputs into `mul_in1` |
| `MUL` | Capture weights, run multiplier, store P products, advance `i += P`. Loops back to W_F until all N inputs processed |
| `ACC` | Trigger accumulator — sums all products then adds bias |
| `ACT` | Apply ReLU activation, capture result into `neuron_out` |
| `DONE` | Pulse `neuron_done` for 1 cycle |

- For N=784, P=2 → **392 W_F→MUL iterations** before reaching ACC.
- Boundary: if `i + j >= N`, input slice is zero-padded.

---

### 8.5 Out_neuron.v

**Role:** Output layer neuron — identical to `Neuron_ASM` with the ACT state removed.

| Feature | Neuron_ASM | Out_neuron |
|---|---|---|
| Activation | ReLU | None — raw logit |
| Output width | 16 bits (Q1.15) | `2*D_W + $clog2(N+1)` bits |
| FSM | ...→ACT→DONE | ...→ACC→DONE |

Skipping ReLU is architecturally necessary — negative logits carry real class information that argmax needs.

---

### 8.6 Output_Layer.v

**Role:** Runs 10 `Out_neuron` instances in parallel, then selects the winning class via argmax.

- **Argmax:** Purely combinational loop using `$signed()` comparison across all 10 outputs.
- **Registered output:** `out_num` is latched only when `layer_done` is asserted — prevents glitch propagation.
- Output is a 4-bit index (0–9) representing the predicted digit.

---

### 8.7 Weight_ROM_mod.v

**Role:** Per-neuron ROM. Delivers P weights per read using a 3-state FSM (IDLE→READ→DONE). Initialized from `.txt` via `$readmemb()`. Packs weights MSB-first into `weight_string`. Boundary-pads with zeros beyond address N.

---

### 8.8 multiplier_block.v

**Role:** P signed 16×16 multiplications in one clock cycle. 3-state FSM (IDLE→MUL→DONE). Each product is 32 bits — full precision. `P` directly controls the DSP resource vs. speed trade-off.

---

### 8.9 accumilator.v

**Role:** Sums all N products sequentially (one per cycle), then adds bias. 4-state FSM (IDLE→ACCUM→ADD_BIAS→DONE). Output uses `$clog2(N+1)` guard bits to prevent overflow during the running sum.

---

### 8.10 activation.v

**Role:** ReLU with saturation and fixed-point truncation. 3-state FSM (IDLE→PROCESS→FINISH). Three decisions applied in order in PROCESS:

1. **Negative** → output zero (ReLU).
2. **Overflow** → clamp to `0x7FFF` (saturation).
3. **Normal** → extract the correct D_W-bit window using `INT_W` alignment (truncation).

---

## 9. How to Run

**Step 1 — Software**
- Train the model: `python mnist_training.py` → produces `mnist_model.keras`
- Export weights: `python export_weights.py` → produces `weight_files_3d/` directory
- Inputs for Hardware: Run the input conversion script to generate Q1.15 test files: `python image_to_bin.py` from test_mnist_images

**Step 2 — Hardware Setup**
- Copy all `.txt` files from `weight_files_3d/` into your Verilog simulation working directory
- Copy the `.txt` input file generated from the `python image_to_bin.py` into the simulation working directory
- Compile `.v` files bottom-up: `Weight_ROM_mod` → `multiplier_block` → `accumilator` → `activation` → `Neuron_ASM` → `Out_neuron` → `Neuron_Layer` → `Output_Layer` → `Neural_Network`

**Step 3 — Simulate**
- Assert `network_start` high for one cycle
- Wait for `network_done` to pulse high
- Read `network_out` — the 4-bit value is the predicted digit (0–9)

---

## 10. Strengths of This Implementation

- **Fully parametrized design:** Every critical dimension — `D_W`, `P`, `NUM_NEURONS`, `N` — is a Verilog parameter. The entire network can be resized or retargeted by changing only top-level values.
- **Clean FSM handshake:** The hierarchical `layer_start` / `layer_done` protocol ensures no data race conditions , each layer only begins when the previous one has fully settled which is easy to debug and more ordered.
- **Intra-layer parallelism:** All neurons within a layer compute simultaneously via `generate` loops, directly utilizing parallel DSP blocks on the FPGA fabric.
- **Numerically safe accumulation:** Guard bits (`$clog2(N+1)`) prevent overflow during dot product summation, and the activation module handles saturation and fixed-point truncation cleanly.
- **Zero-overhead SW-HW integration:** Weight loading via `$readmemb()` needs no extra tools or runtime loaders — the Python quantization output maps directly onto what the hardware expects.
- **Dataflow-aligned architecture:** The design follows a clear streaming/dataflow/ASM approach where data moves layer-by-layer without unnecessary storage or control overhead. This makes the implementation efficient, easier to debug, and well-suited for FPGA execution.

---

## 11. Future Improvements

- **Quantization-aware training:** The current pipeline trains in full float32 first and quantizes afterward , this two-step process introduces rounding errors at every layer that accumulate through the network. Future work will explore training the model with fixed-point constraints applied during training itself, so the network learns to compensate for quantization noise directly, reducing accuracy loss in hardware.
- **Improvement of Activation Function:**  The current design uses a clamped ReLU because it is simple and easy to implement in hardware. This can be improved by using better activation functions like Sigmoid or Tanh. A simple way to do this is by using a lookup table (for example, `Sigmoid_ROM.v`), where values of the function are already stored in memory. This avoids complex calculations and can improve accuracy while still keeping the hardware design efficient.
- **Extension to FPGA:** The current implementation is validated only at the simulation level. Future work involves synthesizing the design onto a physical FPGA board (such as Xilinx Artix-7 or Basys-3), mapping the ROM initialization files to on-chip BRAM, and verifying real-time inference with actual timing constraints and resource utilization reports. 
- **Higher bit-width for better accuracy:** Moving from Q1.15 (16-bit) weights to Q1.31 (32-bit) or IEEE 754 single-precision would close the accuracy gap between software and hardware, at the cost of more DSP resources per neuron.
- **Increased parallelism factor P:** Raising `P` directly reduces inference latency , with sufficient DSP blocks, P can be set to N, completing each neuron's multiply stage in a single cycle.
- **Tree-reduction accumulator:** Replacing the sequential adder with a `$clog2(N)`-depth adder tree would dramatically cut accumulation latency for large layers like Layer 1 (N=784).
  
