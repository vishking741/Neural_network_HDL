import tensorflow as tf
import numpy as np
import os


# MODEL ARCHITECTURE
def build_model():
    inputs = tf.keras.Input(shape=(28, 28))
    x = tf.keras.layers.Flatten()(inputs)
    x = tf.keras.layers.Dense(256, activation='relu')(x)
    x = tf.keras.layers.Dense(128, activation='relu')(x)
    x = tf.keras.layers.Dense(64,  activation='relu')(x)
    x = tf.keras.layers.Dense(32,  activation='relu')(x)
    outputs = tf.keras.layers.Dense(10)(x)  # raw logits, no activation
    return tf.keras.Model(inputs=inputs, outputs=outputs)

# TRAINING
def train():
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_train = x_train.astype(np.float32) / 255.0
    x_test  = x_test.astype(np.float32)  / 255.0

    model = build_model()
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=['accuracy']
    )

    model.fit(
        x_train, y_train,
        epochs=15,
        batch_size=64,
        validation_data=(x_test, y_test)
    )

    loss, accuracy = model.evaluate(x_test, y_test, verbose=0)
    print("-" * 40)
    print(f"Final Test Loss:     {loss:.4f}")
    print(f"Final Test Accuracy: {accuracy * 100:.2f}%")
    print("-" * 40)

    model.save("mnist_model.keras")
    print("Model saved as 'mnist_model.keras'")


if __name__ == "__main__":
    train()