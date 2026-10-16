import numpy as np
from scipy import signal
import matplotlib.pyplot as plt
 
# 1. Quantization & Arithmetic Helpers
 
def round_half_to_even(val):
    return np.round(val)

def saturate_16bit(val):
    return np.clip(val, -32768, 32767).astype(np.int64)

# 2. Stimulus Generation (V1, V2, V3)
 
def generate_stimuli(num_frames=20):
    N = num_frames * 8 
    n = np.arange(N)
    
    # V1: Single-tone at center of Channel 2 (k=2 -> f = 2/8 = 0.25)
    v1 = 16000 * np.cos(2 * np.pi * (2/8) * n)
    
    # V2: Multi-tone (Channel 1 + Channel 4)
    v2 = 8000 * np.cos(2 * np.pi * (1/8) * n) + 8000 * np.cos(2 * np.pi * (4/8) * n)
    
    # V3: Multi-tone with uniform noise [-1000, 1000]
    noise = np.random.uniform(-1000, 1000, N)
    v3 = v2 + noise
    
    stimulus_float = np.concatenate([v1, v2, v3])
    return saturate_16bit(round_half_to_even(stimulus_float))

# 3. Channelizer Reference Model
 
def process_channelizer(x, h):
    frames = len(x) // 8
    x_int = x.astype(np.int64)
    h_int = h.astype(np.int64)
    
    output_bins = np.zeros((frames, 8), dtype=complex)
    buffer = np.zeros(32, dtype=np.int64)
    
    for m in range(frames):
        frame_samples = x_int[m*8 : m*8 + 8]
        buffer = np.concatenate([frame_samples[::-1], buffer[:24]])
        
        v_r = np.zeros(8, dtype=np.int64)
        
        for r in range(8):
            acc = 0
            for j in range(4):
                tap_idx = 8*j + r
                acc += h_int[tap_idx] * buffer[tap_idx]
            
            scaled_acc = acc / (2**15)
            v_r[r] = saturate_16bit(round_half_to_even(scaled_acc))
            
        fft_out = np.fft.fft(v_r)
        scaled_fft = fft_out / 8.0 
        
        real_sat = saturate_16bit(round_half_to_even(scaled_fft.real))
        imag_sat = saturate_16bit(round_half_to_even(scaled_fft.imag))
        
        output_bins[m] = real_sat + 1j * imag_sat
        
    return output_bins
 
# 4. Execution & RTL File Export

if __name__ == "__main__":
    h_float = signal.firwin(32, cutoff=1/8, window='hamming')
    h = np.round(h_float * 32767).astype(np.int64)
    
    print("Generating Stimuli (V1, V2, V3)...")
    stimulus = generate_stimuli(num_frames=20)
    
    print("Processing through Channelizer Reference Model...")
    expected_outputs = process_channelizer(stimulus, h)
    
    print("\nExporting stimulus.hex...")
    with open("stimulus.hex", "w") as f:
        for val in stimulus:
            hex_val = f"{(val & 0xFFFF):04x}"
            f.write(f"{hex_val}\n")
            
    print("Exporting expected_output.hex...")
    with open("expected_output.hex", "w") as f:
        for frame in expected_outputs:
            for bin_val in frame:
                real_hex = f"{(int(bin_val.real) & 0xFFFF):04x}"
                imag_hex = f"{(int(bin_val.imag) & 0xFFFF):04x}"
                f.write(f"{real_hex}_{imag_hex}\n")
                
    # 5. Plotting Verification (V1, V2, V3) Time and Frequency Domains
    # 20 frames per test * 8 samples = 160 samples per test
    t_v1 = stimulus[0:160]
    t_v2 = stimulus[160:320]
    t_v3 = stimulus[320:480]

    fig, axs = plt.subplots(3, 2, figsize=(14, 10))
    
    # V1 Plots
    axs[0, 0].plot(t_v1[:64], marker='.')
    axs[0, 0].set_title("V1 Time Domain (Single-Tone)")
    axs[0, 0].set_xlabel("Sample Index")
    axs[0, 0].set_ylabel("Amplitude")
    
    axs[0, 1].bar(range(8), np.abs(expected_outputs[3]))
    axs[0, 1].set_title("V1 Frequency Domain (Peaks at Bins 2 and 6)")
    axs[0, 1].set_xlabel("Channel Bin")
    axs[0, 1].set_ylabel("Magnitude")
    
    # V2 Plots
    axs[1, 0].plot(t_v2[:64], marker='.')
    axs[1, 0].set_title("V2 Time Domain (Multi-Tone)")
    axs[1, 0].set_xlabel("Sample Index")
    axs[1, 0].set_ylabel("Amplitude")
    
    axs[1, 1].bar(range(8), np.abs(expected_outputs[23]))
    axs[1, 1].set_title("V2 Frequency Domain (Peaks at Bins 1, 4, 7)")
    axs[1, 1].set_xlabel("Channel Bin")
    axs[1, 1].set_ylabel("Magnitude")
    
    # V3 Plots
    axs[2, 0].plot(t_v3[:64], marker='.')
    axs[2, 0].set_title("V3 Time Domain (Multi-Tone with Noise)")
    axs[2, 0].set_xlabel("Sample Index")
    axs[2, 0].set_ylabel("Amplitude")
    
    axs[2, 1].bar(range(8), np.abs(expected_outputs[43]))
    axs[2, 1].set_title("V3 Frequency Domain (Multi-Tone with Noise)")
    axs[2, 1].set_xlabel("Channel Bin")
    axs[2, 1].set_ylabel("Magnitude")
    
    plt.tight_layout()
    plt.savefig("verification_plots.png", dpi=300)
    print("\nSaved time and frequency domain graphs to verification_plots.png")
    plt.show()