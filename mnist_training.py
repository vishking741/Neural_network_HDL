import tensorflow as tf
import numpy as np
import os
import time

# FOR FAIR COMPARISION , DISABLING GPU
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

# INFERENCE TIMING FUNCTION
def measure_inference_time(model, x_test, num_runs=100):
    sample = x_test[0:1]   # batch size = 1 
    # Warm-up , ignore these runs
    for _ in range(10):
        _ = model(sample, training=False)
    # Timing start
    start = time.perf_counter()
    for _ in range(num_runs):
        _ = model(sample, training=False)

    # Timing end
    end = time.perf_counter()
    avg_time = (end - start) / num_runs
    print(f"Average inference time: {avg_time * 1e6:.2f} microseconds")

# MODEL ARCHITECTURE
def build_model():
    inputs = tf.keras.Input(shape=(28, 28))
    x = tf.keras.layers.Flatten()(inputs)
    x = tf.keras.layers.Dense(256, activation='relu')(x)
    x = tf.keras.layers.Dense(128, activation='relu')(x)
    x = tf.keras.layers.Dense(64,  activation='relu')(x)
    x = tf.keras.layers.Dense(32,  activation='relu')(x)
    outputs = tf.keras.layers.Dense(10)(x)  # logits
    return tf.keras.Model(inputs=inputs, outputs=outputs)

# TRAIN + TEST + TIMING
def train():
    # Load dataset
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()

    # Normalize
    x_train = x_train.astype(np.float32) / 255.0
    x_test  = x_test.astype(np.float32)  / 255.0

    # Build model
    model = build_model()
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=['accuracy']
    )

    # Train
    model.fit(
        x_train, y_train,
        epochs=15,
        batch_size=64,
        validation_data=(x_test, y_test)
    )
    # Evaluate
    loss, accuracy = model.evaluate(x_test, y_test, verbose=0)

    print("-" * 40)
    print(f"Final Test Loss:     {loss:.4f}")
    print(f"Final Test Accuracy: {accuracy * 100:.2f}%")

    #Measure inference time 
    measure_inference_time(model, x_test, num_runs=100)
    print("-" * 40)

    # Save model
    model.save("mnist_model.keras")
    print("Model saved as 'mnist_model.keras'")

if __name__ == "__main__":
    train()
