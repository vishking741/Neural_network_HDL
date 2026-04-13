import numpy as np
from PIL import Image

# Input image name check proper Path
INPUT_IMAGE = "digit3.jpg"
# Output text file
OUTPUT_FILE = "digit3_q15.txt"

img = Image.open(INPUT_IMAGE).convert("L")
img = img.resize((28, 28))

data = np.array(img, dtype=np.float32)

# Normalize (0 to 1)
data = data / 255.0

scaled = np.round(data * 32767.0)
q15_data = np.clip(scaled, 0, 32767).astype(np.int16)

flat_data = q15_data.flatten()

# Save as 16-bit binary 
with open(OUTPUT_FILE, "w") as f:
    for val in flat_data:
        binary = format(np.uint16(val), '016b')
        f.write(binary + "\n")

print("Done ", OUTPUT_FILE)
