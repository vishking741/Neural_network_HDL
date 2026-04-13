import tensorflow as tf
import numpy as np
import os

# CONFIGURATION
MODEL_PATH  = "mnist_model.keras"
OUTPUT_DIR  = "weight_files_3d"

# Q1.15 scale for weights
W_SCALE = 32768.0       # 2^15
W_MAX   =  32767
W_MIN   = -32768

# Q2.30 scale for biases
B_SCALE = 1073741824.0  # 2^30
B_MAX   =  2147483647
B_MIN   = -2147483648

os.makedirs(OUTPUT_DIR, exist_ok=True)

# CONVERSION HELPERS
def float_to_q1_15(value):
    """
    Convert float to Q1.15 16-bit signed integer.
    Clamps to [-32768, 32767] then rounds.
    """
    scaled  = int(round(value * W_SCALE))
    clamped = max(W_MIN, min(W_MAX, scaled))
    return clamped


def float_to_q2_30(value):
    """
    Convert float to Q2.30 32-bit signed integer.
    Clamps to [-2147483648, 2147483647] then rounds.
    """
    scaled  = int(round(value * B_SCALE))
    clamped = max(B_MIN, min(B_MAX, scaled))
    return clamped


def to_binary_16bit(value):
    """
    Convert signed integer to 16-bit two's complement binary string.
    Used for Q1.15 weights.
    """
    if value < 0:
        value = value + (1 << 16)   # two's complement
    return format(value, '016b')


def to_binary_32bit(value):
    """
    Convert signed integer to 32-bit two's complement binary string.
    Used for Q2.30 biases.
    """
    if value < 0:
        value = value + (1 << 32)   # two's complement
    return format(value, '032b')


# EXPORT
def export_weights():
    model = tf.keras.models.load_model(MODEL_PATH)

    # Collect only Dense layers — skip Flatten and Input
    dense_layers = [l for l in model.layers if isinstance(l, tf.keras.layers.Dense)]

    # Layer index mapping to match Verilog naming:
    #   hidden layer 1 → w1_<neuron>.txt / b1_<neuron>.txt
    #   hidden layer 2 → w2_<neuron>.txt / b2_<neuron>.txt
    #   hidden layer 3 → w3_<neuron>.txt / b3_<neuron>.txt
    #   hidden layer 4 → w4_<neuron>.txt / b4_<neuron>.txt
    #   output  layer  → o_w_<neuron>.txt / o_b_<neuron>.txt

    for layer_idx, layer in enumerate(dense_layers):
        weights, biases = layer.get_weights()
        # weights shape: (n_inputs, n_neurons)
        # biases  shape: (n_neurons,)

        n_inputs  = weights.shape[0]
        n_neurons = weights.shape[1]

        is_output = (layer_idx == len(dense_layers) - 1)

        print(f"\nLayer {layer_idx + 1} — "
              f"{'Output' if is_output else 'Hidden'} — "
              f"{n_inputs} inputs, {n_neurons} neurons")

        for neuron_idx in range(n_neurons):

            # --- Weight file ---
            if is_output:
                w_filename = os.path.join(OUTPUT_DIR, f"o_w_{neuron_idx}.txt")
            else:
                w_filename = os.path.join(OUTPUT_DIR, f"w{layer_idx + 1}_{neuron_idx:03d}.txt")

            with open(w_filename, 'w') as f:
                for input_idx in range(n_inputs):
                    q_val  = float_to_q1_15(weights[input_idx, neuron_idx])
                    binary = to_binary_16bit(q_val)
                    f.write(binary + '\n')

            # --- Bias file ---
            if is_output:
                b_filename = os.path.join(OUTPUT_DIR, f"o_b_{neuron_idx}.txt")
            else:
                b_filename = os.path.join(OUTPUT_DIR, f"b{layer_idx + 1}_{neuron_idx:03d}.txt")

            with open(b_filename, 'w') as f:
                q_val  = float_to_q2_30(biases[neuron_idx])
                binary = to_binary_32bit(q_val)
                f.write(binary + '\n')

        print(f"  Written: {n_neurons} weight files + {n_neurons} bias files")

    print(f"\nAll files written to '{OUTPUT_DIR}/'")


if __name__ == "__main__":
    export_weights()
