# MNIST Digit Classifier — Feed-Forward Neural Network on FPGA (Verilog)

---

## Table of Contents

1. [Project Goal](#1-project-goal)
2. [How a Neural Network Works](#2-how-a-neural-network-works)
3. [Software–Hardware Integration Overview](#3-softwarehardware-integration-overview)
4. [Software Code](#4-software-code)
   - 4.1 [Training Script](#41-training-script)
   - 4.2 [Weight Export Script](#42-weight-export-script)
5. [Hardware Code](#5-hardware-code)
   - 5.1 [Module Hierarchy](#51-module-hierarchy)
   - 5.2 [Top Module — Neural_Network.v](#52-top-module--neural_networkv)
   - 5.3 [Neuron_Layer.v](#53-neuron_layerv)
   - 5.4 [Neuron_ASM.v](#54-neuron_asmv)
   - 5.5 [Out_neuron.v](#55-out_neuronv)
   - 5.6 [Output_Layer.v](#56-output_layerv)
   - 5.7 [Weight_ROM_mod.v](#57-weight_rom_modv)
   - 5.8 [multiplier_block.v](#58-multiplier_blockv)
   - 5.9 [accumilator.v](#59-accumilatorv)
   - 5.10 [activation.v](#510-activationv)
6. [Fixed-Point Number Formats](#6-fixed-point-number-formats)
7. [Parameter Reference Table](#7-parameter-reference-table)
8. [File Naming Convention](#8-file-naming-convention)
9. [How to Run](#9-how-to-run)

---

## 1. Project Goal

- **Primary Objective:** Implement a complete feed-forward neural network inference engine on an FPGA using Verilog HDL that classifies handwritten digits from the MNIST dataset.
- **Training in Software:** The network is first trained using TensorFlow/Keras in Python, producing a floating-point model with learned weights and biases.
- **Deployment in Hardware:** The trained weights are quantized to fixed-point binary format and stored as `.txt` files. The Verilog hardware loads them into on-chip ROM and performs the full forward pass — weighted sum, bias addition, ReLU activation, and argmax classification — with no CPU involvement during inference.
- **Key Achievement:** A complete end-to-end pipeline from floating-point model training in Python to synthesizable RTL inference in Verilog.

---

## 2. How a Neural Network Works

<!-- IMAGE: Insert the neural_network_diagram.png here. This diagram visually shows the Input Layer, Hidden Layers (h1..hn), and Output Layer with all inter-neuron connections, which directly maps to how the Verilog layers are wired together. -->

![Neural Network Architecture](https://github.com/vishking741/Neural_network_HDL/blob/main/Neural_network_image.png)

### 2.1 Basic Structure

- **Input Layer:** Receives the raw data. For MNIST, this is a flattened 28×28 image = **784 input values**.
- **Hidden Layers:** Intermediate layers where the network learns to extract features. Each neuron connects to all neurons in the previous layer (fully connected).
- **Output Layer:** Final layer with one neuron per class. For MNIST, there are **10 neurons** (digits 0–9).

### 2.2 What Each Neuron Does

Each neuron performs three operations in sequence:

1. **Weighted Sum:** Multiply every input by a corresponding learned weight and sum them all.
   ```
   sum = (input_0 × weight_0) + (input_1 × weight_1) + ... + (input_N × weight_N)
   ```
2. **Bias Addition:** Add a single learned bias value to shift the result.
   ```
   z = sum + bias
   ```
3. **Activation Function:** Apply a non-linear function. Hidden neurons use **ReLU** (outputs 0 if negative, else passes the value through). Output neurons use **no activation** — they output raw logits.

### 2.3 How This Project Implements It in Hardware

| Neural Network Concept | Hardware Implementation |
|---|---|
| Input Layer (784 pixels) | Wide input bus: `784 × 16 = 12544 bits` fed into `Neural_Network.v` |
| Hidden Layer (N neurons in parallel) | `Neuron_Layer.v` instantiates N `Neuron_ASM` modules via `generate` |
| Weighted sum inside a neuron | `Weight_ROM_mod` → `multiplier_block` → `accumilator` pipeline |
| Bias addition | Done inside `accumilator.v`, bias loaded from `.txt` file |
| ReLU activation | `activation.v` with saturation and truncation logic |
| Output Layer (10 classes) | `Output_Layer.v` with 10 `Out_neuron` modules, no ReLU |
| Classification / argmax | Combinational argmax block in `Output_Layer.v` |
| Layer sequencing | 7-state FSM in `Neural_Network.v` using `layer_done` handshake signals |

### 2.4 Network Architecture Used

```
Input: 784 → Hidden Layer 1: 64 neurons → Hidden Layer 2: 32 neurons
       → Hidden Layer 3: 16 neurons → Hidden Layer 4: 16 neurons
       → Output Layer: 10 neurons → argmax → Predicted Digit (0–9)
```

> **Note:** The Python training model uses layer sizes 256→128→64→32. The Verilog hardware uses 64→32→16→16. These must be aligned before exporting weights for hardware use.

---

## 3. Software–Hardware Integration Overview

<!-- IMAGE: A block diagram showing Python → weight_files/ → Verilog $readmemb() would fit perfectly here if you create one in the future. For now this section is text-only. -->

The integration rests on a **file-based contract** between the Python scripts and Verilog hardware. The process flow is:

```
Train Model (Python)  →  Export Weights (Python)  →  .txt Files  →  $readmemb() (Verilog)
```

### 3.1 The Contract

- Python writes **binary-encoded fixed-point values** into `.txt` files.
- File names follow an exact convention that the Verilog `generate` loops generate at elaboration time.
- Verilog uses `$readmemb()` to load files into ROM memories at simulation start.
- No intermediate tool or converter is needed — the two sides agree directly on binary format and file names.

### 3.2 Quantization Bridge

| Parameter | Software Format | Hardware Format | Scale Factor |
|---|---|---|---|
| Weights | `float32` | Q1.15 (16-bit signed) | 2^15 = 32768 |
| Biases | `float32` | Q2.30 (32-bit signed) | 2^30 = 1073741824 |
| Products (internal) | — | 32-bit full precision (2×D_W) | — |
| Accumulator output | — | 37-bit (2×D_W + guard bits) | — |

- **Q1.15 for weights:** 15 fractional bits, value range [-1.0, +0.99997]. Weights in trained neural networks are almost always within [-1, 1], so this format is a perfect fit.
- **Q2.30 for biases:** More integer range needed because biases are added after a large dot product accumulation where the dynamic range is already expanded.
- **Two's complement:** All negative values are stored in two's complement. Verilog's `$signed()` cast handles this natively.

---

## 4. Software Code

### 4.1 Training Script

**Purpose:** Builds and trains the neural network on the MNIST dataset, then saves the model.

#### What It Does

- Loads MNIST from TensorFlow datasets and normalizes pixel values to [0.0, 1.0].
- Builds a model: `Flatten → Dense(256, ReLU) → Dense(128, ReLU) → Dense(64, ReLU) → Dense(32, ReLU) → Dense(10, no activation)`.
- Compiles with **Adam optimizer** (lr=0.001) and **Sparse Categorical Cross-Entropy** loss.
- Trains for **15 epochs**, batch size **64**, with validation on the test set.
- Saves the final model as `mnist_model.keras`.

#### How to Use

```bash
# Requirements
pip install tensorflow numpy

# Run training
python train.py
```

Expected output after training:
```
Final Test Loss:     ~0.08
Final Test Accuracy: ~97.5%
Model saved as 'mnist_model.keras'
```

#### Key Code Sections

```python
# Model Architecture
def build_model():
    inputs = tf.keras.Input(shape=(28, 28))
    x = tf.keras.layers.Flatten()(inputs)
    x = tf.keras.layers.Dense(256, activation='relu')(x)
    x = tf.keras.layers.Dense(128, activation='relu')(x)
    x = tf.keras.layers.Dense(64,  activation='relu')(x)
    x = tf.keras.layers.Dense(32,  activation='relu')(x)
    outputs = tf.keras.layers.Dense(10)(x)  # Raw logits, no activation
    return tf.keras.Model(inputs=inputs, outputs=outputs)
```

> **Why no activation on the output layer?** Raw logits are needed for the hardware argmax to work correctly. If ReLU were applied, negative scores would become zero and argmax would produce wrong results for many classes.

---

### 4.2 Weight Export Script

**Purpose:** Extracts the trained weights and biases, quantizes them to fixed-point binary, and writes the `.txt` files the Verilog hardware needs.

#### What It Does

- Loads `mnist_model.keras`.
- Filters only Dense layers (skips Flatten and Input layers).
- For each Dense layer and each neuron:
  - Writes one **weight file**: N lines, each a 16-bit binary string in Q1.15 format.
  - Writes one **bias file**: 1 line, a 32-bit binary string in Q2.30 format.
- Output goes into the `weight_files/` directory.

#### Conversion Functions

```python
def float_to_q1_15(value):
    # Multiply by 2^15, round, clamp to [-32768, 32767]
    scaled  = int(round(value * 32768.0))
    return max(-32768, min(32767, scaled))

def float_to_q2_30(value):
    # Multiply by 2^30, round, clamp to 32-bit signed range
    scaled  = int(round(value * 1073741824.0))
    return max(-2147483648, min(2147483647, scaled))

def to_binary_16bit(value):
    # Two's complement 16-bit binary string
    if value < 0:
        value = value + (1 << 16)
    return format(value, '016b')
```

#### How to Use

```bash
# Run after training is complete
python export_weights.py

# Output structure
weight_files/
├── w1_0.txt    # Layer 1, Neuron 0 weights (N lines of 16-bit binary)
├── b1_0.txt    # Layer 1, Neuron 0 bias   (1 line of 32-bit binary)
├── w1_1.txt
├── b1_1.txt
├── ...
├── o_w_0.txt   # Output Layer, Neuron 0 weights
├── o_b_0.txt   # Output Layer, Neuron 0 bias
└── ...
```

After export, **copy all files from `weight_files/` into your Verilog simulation working directory** so `$readmemb()` can find them.

---

## 5. Hardware Code

### 5.1 Module Hierarchy

```
Neural_Network.v                    ← TOP MODULE
│
├── Neuron_Layer.v  (×4 hidden)
│   └── Neuron_ASM.v  (×NUM_NEURONS, parallel via generate)
│       ├── Weight_ROM_mod.v
│       ├── multiplier_block.v
│       ├── accumilator.v
│       └── activation.v
│
└── Output_Layer.v  (×1)
    └── Out_neuron.v  (×10, parallel via generate)
        ├── Weight_ROM_mod.v
        ├── multiplier_block.v
        └── accumilator.v            ← No activation here (raw logits)
```

<!-- IMAGE: A box-and-arrow hardware block diagram showing this hierarchy would be ideal here. Each box should show module name and key parameters (num neurons, data width). Draw one in a tool like draw.io or Vivado's block design view and insert it here. -->

### 5.2 Top Module — Neural_Network.v

**Role:** Orchestrates the entire inference. Controls layer sequencing and connects inter-layer data buses.

#### Ports

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 | System clock |
| `network_rst` | Input | 1 | Synchronous reset |
| `network_start` | Input | 1 | Pulse high to start inference |
| `network_in` | Input | 784×16 = 12544 | Flattened image pixels (Q1.15 each) |
| `network_out` | Output | 4 (`$clog2(10)`) | Predicted digit class (0–9) |
| `network_done` | Output | 1 | Pulses high for 1 cycle when done |

#### Parameters

| Parameter | Default | Description |
|---|---|---|
| `D_W` | 16 | Data width per value (bits) |
| `P` | 2 | Parallelism factor (multiplications per cycle) |
| `INT_W` | 1 | Integer bits in Q1.15 fixed-point |
| `inputNum` | 784 | Number of input pixels |
| `outNum` | 10 | Number of output classes |

#### FSM States

```
IDLE → LAYER_1 → LAYER_2 → LAYER_3 → LAYER_4 → OUT_RUN → FINISH → IDLE
```

- **IDLE:** Waits for `network_start`. Keeps `network_done = 0`.
- **LAYER_1–LAYER_4:** Asserts the corresponding `layer_start_sigs[n]`, waits for `layer_done_sigs[n]`, then deasserts and moves to the next state.
- **OUT_RUN:** Same handshake for the output layer.
- **FINISH:** Pulses `network_done = 1` for one cycle, returns to IDLE.

#### Inter-Layer Buses

| Bus | Width | Carries |
|---|---|---|
| `L1_to_L2` | 64 × 16 = 1024 bits | Outputs of Hidden Layer 1 |
| `L2_to_L3` | 32 × 16 = 512 bits | Outputs of Hidden Layer 2 |
| `L3_to_L4` | 16 × 16 = 256 bits | Outputs of Hidden Layer 3 |
| `L4_to_OUT` | 16 × 16 = 256 bits | Outputs of Hidden Layer 4 |

---

### 5.3 Neuron_Layer.v

**Role:** Parallel container for multiple `Neuron_ASM` instances. Broadcasts start, collects done signals.

#### Key Design Points

- Uses a `generate` loop to instantiate exactly `NUM_NEURONS` neurons simultaneously.
- **All neurons start and compute in parallel** — layer latency is determined by the slowest neuron (all are equal in practice since they process the same number of inputs).
- `layer_done` uses a **reduction AND** operator: `assign layer_done = &done_each;` — the layer is done only when every neuron is done.
- **File name generation** uses ASCII math in localparam: `LayerNum[7:0] + 8'h30` converts a binary number to its ASCII character, forming `w1_0.txt`, `w1_1.txt`, etc. at elaboration time.
  > **Limitation:** Supports single-digit layer numbers and neuron indices only (0–9). Neuron counts beyond 9 will need a different naming scheme.

#### Ports

| Port | Description |
|---|---|
| `layer_in` | Wide bus of all inputs (N × D_W bits) |
| `layer_start` | Trigger from Neural_Network FSM |
| `layer_out` | Wide bus of all neuron outputs (NUM_NEURONS × D_W bits) |
| `layer_done` | High when all neurons complete |

---

### 5.4 Neuron_ASM.v

**Role:** The core computation engine for hidden layer neurons. Implements the full weighted sum + bias + ReLU pipeline using an ASM (Algorithmic State Machine).

#### FSM States

```
IDLE → W_F → MUL → (loop back to W_F until all chunks done) → ACC → ACT → DONE
```

| State | Action |
|---|---|
| `IDLE` | Clear state, wait for `neuron_start` |
| `W_F` | Assert `ren` to ROM, set address to `i`, slice P inputs from `neuron_in` into `mul_in1` |
| `MUL` | Capture ROM output into `mul_in2`, trigger multiplier, store P products into `accum_in`, advance `i += P`. Loop back to W_F if more chunks remain |
| `ACC` | Trigger accumulator, wait for `accum_done` |
| `ACT` | Trigger activation function, capture `act_out` into `neuron_out` |
| `DONE` | Pulse `neuron_done` high for 1 cycle |

#### Chunk-Based Processing

- The neuron processes inputs in groups of `P` per iteration.
- For N=784 and P=2: **392 W_F→MUL cycles** to process all inputs.
- The chunk pointer `i` increments by `P` each MUL completion.
- Boundary protection: if `i + j >= N`, the input slice is padded with zeros.

#### Internal Sub-modules

| Sub-module | Role |
|---|---|
| `Weight_ROM_mod` | Provides P weights per read cycle |
| `multiplier_block` | Multiplies P input-weight pairs in parallel |
| `accumilator` | Sums all products and adds bias |
| `activation` | Applies ReLU with saturation and truncation |

---

### 5.5 Out_neuron.v

**Role:** Output layer neuron. Identical to `Neuron_ASM` but with the ACT state removed.

#### Key Differences from Neuron_ASM

| Feature | Neuron_ASM (Hidden) | Out_neuron (Output) |
|---|---|---|
| Activation | ReLU applied | None — raw logits |
| Output width | D_W (16 bits, Q1.15) | `2*D_W + $clog2(N+1)` (37 bits, full precision) |
| FSM states | IDLE→W_F→MUL→ACC→ACT→DONE | IDLE→W_F→MUL→ACC→DONE |

- **Why no activation?** The argmax in `Output_Layer` must compare raw signed values. If ReLU were applied, all negative logits would become zero, breaking the classification.
- **Why wider output?** The full-precision accumulation result (including guard bits) is passed directly to the argmax for maximum comparison accuracy without truncation errors.

---

### 5.6 Output_Layer.v

**Role:** Final stage of the network. Runs 10 `Out_neuron` instances in parallel and determines the predicted digit via argmax.

#### Argmax Logic

- **Combinational block:** Iterates through all 10 `layer_out` values using `$signed()` comparison, tracking the maximum value and its index.
- **Registered output:** `out_num` is only latched on the clock edge when `layer_done` is asserted, preventing glitchy intermediate values from propagating.
- **Output:** `out_num` is a 4-bit (`$clog2(10)`) value holding the predicted digit class.

#### File Naming for Output Layer

- Weights: `o_w_0.txt`, `o_w_1.txt`, ..., `o_w_9.txt`
- Biases: `o_b_0.txt`, `o_b_1.txt`, ..., `o_b_9.txt`

---

### 5.7 Weight_ROM_mod.v

**Role:** Parameterized Read-Only Memory storing all weights for one neuron. Delivers P weights per read cycle.

#### FSM States

```
IDLE → READ → DONE → IDLE
```

| State | Action |
|---|---|
| `IDLE` | Wait for `ren` assert |
| `READ` | Pack P weights from `mem[start_add]` to `mem[start_add + P-1]` into `weight_string` using generate loop |
| `DONE` | Assert `weight_valid` for 1 cycle |

#### Key Design Points

- Memory initialized at simulation start: `$readmemb(weightFile, mem)` — reads binary Q1.15 values from the `.txt` file.
- **Packing order:** `mem[start_add]` is placed at the **most significant chunk** of `weight_string`, matching the bit order expected by the multiplier.
- **Boundary protection:** If `start_add + j >= N`, that weight position is padded with zeros.
- Each full ROM read (IDLE→READ→DONE) takes **3 clock cycles**.

---

### 5.8 multiplier_block.v

**Role:** Performs P signed 16×16 multiplications in a single clock cycle.

#### FSM States

```
IDLE → MUL → DONE → IDLE
```

| State | Action |
|---|---|
| `IDLE` | Wait for `mul_start`, clear `mul_done` |
| `MUL` | Compute `$signed(mul_in1[slice]) × $signed(mul_in2[slice])` for all P pairs simultaneously using generate |
| `DONE` | Assert `mul_done` for 1 cycle, result stable in `mul_out` |

#### Key Design Points

- Each multiplication produces a **32-bit full-precision result** (2×D_W) — no overflow possible.
- P multiplications happen in **one clock cycle** (in MUL state), using generate to unroll.
- Each chunk takes **3 cycles total** (IDLE→MUL→DONE).
- The `P` parameter is the main resource vs. speed knob: higher P = more DSP blocks used, fewer loop iterations needed.

---

### 5.9 accumilator.v

**Role:** Sequentially sums all N products from the multiplier stage, then adds the bias. Implements the complete `z = Σ(w×x) + b` computation.

#### FSM States

```
IDLE → ACCUM → ADD_BIAS → DONE → IDLE
```

| State | Action |
|---|---|
| `IDLE` | Clear output and counter |
| `ACCUM` | Add one 32-bit product per clock cycle, incrementing counter. Takes N cycles. |
| `ADD_BIAS` | Add the pre-loaded bias from `biasFile` (32-bit Q2.30 value) |
| `DONE` | Assert `accum_done` for 1 cycle |

#### Key Design Points

- **Output width:** `2*D_W + $clog2(N+1)` bits. The `$clog2(N+1)` guard bits prevent the running sum from overflowing when adding up to N products.
- **Bias loading:** `$readmemb(biasFile, mem)` loads a single 32-bit bias value at simulation start.
- The sequential accumulation (one addition per cycle) keeps hardware area small at the cost of N clock cycles per neuron computation.

---

### 5.10 activation.v

**Role:** Implements ReLU activation with saturation and fixed-point truncation. Converts the wide accumulator output back to the standard D_W format.

#### FSM States

```
IDLE → PROCESS → FINISH → IDLE
```

#### PROCESS State — Three-Level Decision

```
1. If act_in < 0      → act_out = 0              (ReLU: zero out negatives)
2. Else if overflow   → act_out = 0x7FFF          (Saturation: cap at max Q1.15)
3. Else               → act_out = act_in[window]  (Truncation: extract D_W bits)
```

| Condition | Check | Action |
|---|---|---|
| Negative (ReLU) | Sign bit of `act_in` is 1 | Output all zeros |
| Overflow | Upper bits above integer position contain any 1 | Clamp to `{0, {(D_W-1){1'b1}}}` = 0x7FFF |
| Normal | Neither of the above | Slice correct D_W-bit window using `INT_W` alignment |

#### Fixed-Point Alignment Constants

- `FRAC_W = D_W - INT_W` — fractional bits in the output format (15 for Q1.15).
- `ACC_FRAC_W = 2 × FRAC_W` — fractional bits in the product (30 for Q1.15 × Q1.15 = Q2.30).
- `ONE_BIT = ACC_FRAC_W` — position of the integer bit in the expanded accumulator result.
- Truncation: `act_out <= act_in[ONE_BIT + (INT_W - 1) -: D_W]` — extracts the correct 16-bit window.

---

## 6. Fixed-Point Number Formats

<!-- IMAGE: A bit-field diagram showing the Q1.15 and Q2.30 formats (sign bit | integer bits | fractional bits) would be very helpful here. Draw a simple horizontal bit-layout diagram for both formats and insert it here. -->

### Q1.15 — Used for Weights

```
Bit 15       Bit 14 ... Bit 0
[Sign]       [Fractional (15 bits)]
```

| Property | Value |
|---|---|
| Total bits | 16 |
| Integer bits | 0 (only sign) |
| Fractional bits | 15 |
| Scale factor | 2^15 = 32768 |
| Value range | [-1.0, +0.99997] |
| Max value (hex) | 0x7FFF |
| Min value (hex) | 0x8000 |
| Example: 0.5 → | 0x4000 = `0100000000000000` |
| Example: -0.25 → | 0xE000 = `1110000000000000` |

### Q2.30 — Used for Biases

```
Bit 31       Bit 30       Bit 29 ... Bit 0
[Sign]       [Integer]    [Fractional (30 bits)]
```

| Property | Value |
|---|---|
| Total bits | 32 |
| Integer bits | 1 |
| Fractional bits | 30 |
| Scale factor | 2^30 = 1073741824 |
| Value range | [-2.0, +1.99999] |
| Example: 0.1 → | integer 107374182 |

### Internal Precision

| Stage | Width | Format | Notes |
|---|---|---|---|
| Weight × Input product | 32 bits | Q2.30 | Full precision, no overflow |
| Accumulator running sum | 37 bits | Q2.30 + guard bits | For N=64: 32 + 6 = 38 bits |
| Accumulator final output | `2*D_W + $clog2(N+1)` | Extended | Passed to activation |
| Activation output | 16 bits | Q1.15 | After truncation |
| Output neuron output | `2*D_W + $clog2(N+1)` | Extended | Raw logit, no truncation |

---

## 7. Parameter Reference Table

| Parameter | Where Used | Default | Meaning |
|---|---|---|---|
| `D_W` | All modules | 16 | Data width per value in bits |
| `P` | Neuron_ASM, multiplier, ROM | 2 | Parallel multiplications per cycle |
| `INT_W` | Neural_Network, activation | 1 | Integer bits in Q fixed-point |
| `inputNum` | Neural_Network | 784 | Number of network inputs |
| `outNum` | Neural_Network | 10 | Number of output classes |
| `NUM_NEURONS` | Neuron_Layer, Output_Layer | varies | Neurons in the layer |
| `LayerNum` | Neuron_Layer | 1–4 | Layer index, used for file name generation |
| `N` | Neuron_ASM, accumilator, ROM | varies | Number of inputs per neuron |
| `A_W` | Neuron_ASM, ROM | `$clog2(N)` | Address width for ROM |
| `weightFile` | Neuron_ASM, Out_neuron, ROM | auto-generated | Path to weight `.txt` file |
| `biasFile` | Neuron_ASM, Out_neuron, accumilator | auto-generated | Path to bias `.txt` file |

---

## 8. File Naming Convention

The file naming contract between Python and Verilog is exact and must not be changed.

### Hidden Layers (Layers 1–4)

| File | Contains | Example |
|---|---|---|
| `w[L]_[N].txt` | All weights for neuron N in layer L | `w1_0.txt` = Layer 1, Neuron 0 |
| `b[L]_[N].txt` | Bias for neuron N in layer L | `b3_5.txt` = Layer 3, Neuron 5 |

### Output Layer

| File | Contains | Example |
|---|---|---|
| `o_w_[N].txt` | All weights for output neuron N | `o_w_7.txt` = Output Neuron 7 |
| `o_b_[N].txt` | Bias for output neuron N | `o_b_0.txt` = Output Neuron 0 |

### File Content Format

- **Weight files:** N lines, each a **16-bit binary string** (Q1.15 two's complement).
- **Bias files:** 1 line, a **32-bit binary string** (Q2.30 two's complement).
- No headers, no spaces, one value per line.

### Example: w1_0.txt (first 3 lines)

```
0100000000000000    ← weight[0] = +0.5 in Q1.15
1110000000000000    ← weight[1] = -0.25 in Q1.15
0000000000000000    ← weight[2] = 0.0
...
```

---

## 9. How to Run

### Step 1 — Train the Model

```bash
pip install tensorflow numpy
python train.py
# Output: mnist_model.keras
```

### Step 2 — Export Weights

```bash
python export_weights.py
# Output: weight_files/ directory with all .txt files
```

### Step 3 — Copy Weight Files to Verilog Working Directory

```bash
cp weight_files/*.txt <your_verilog_simulation_dir>/
```

### Step 4 — Simulate

Using Vivado or ModelSim/QuestaSim:

```tcl
# Example Vivado xvlog compile
xvlog Weight_ROM_mod.v multiplier_block.v accumilator.v activation.v
xvlog Neuron_ASM.v Out_neuron.v
xvlog Neuron_Layer.v Output_Layer.v
xvlog Neural_Network.v
xelab Neural_Network -top Neural_Network_tb
xsim Neural_Network_tb --runall
```

### Step 5 — Check Output

- `network_done` will pulse high when inference is complete.
- `network_out` will hold the predicted digit (0–9) as a 4-bit binary value.

### Important Alignment Check

Before running, verify that the Python model architecture and the Verilog parameters match:

| Python Layer | Verilog Parameter |
|---|---|
| `Dense(256)` → Layer 1 outputs | `num_layer1 = 64` in Neural_Network.v |
| `Dense(128)` → Layer 2 outputs | `num_layer2 = 32` |
| `Dense(64)` → Layer 3 outputs | `num_layer3 = 16` |
| `Dense(32)` → Layer 4 outputs | `num_layer4 = 16` |

> **If these don't match, the weight files and ROM sizes will be wrong.** Either retrain with architecture matching the Verilog sizes, or change the Verilog parameters to match the Python model.

---

*End of README*
