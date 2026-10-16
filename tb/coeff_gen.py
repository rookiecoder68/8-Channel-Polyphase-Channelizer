import numpy as np
from scipy import signal

# Re-generate the exact same filter used for the reference model
h_float = signal.firwin(32, cutoff=1/8, window='hamming')
h = np.round(h_float * 32767).astype(np.int64)

# Export to coeffs.hex
with open("coeffs.hex", "w") as f:
    for val in h:
        # Convert signed 16-bit to hex (2's complement)
        hex_val = f"{(val & 0xFFFF):04x}"
        f.write(f"{hex_val}\n")

print("Successfully generated coeffs.hex with 32 filter taps.")