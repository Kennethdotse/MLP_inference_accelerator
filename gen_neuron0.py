def read_hex(path):
    vals = []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        v = int(line, 16)
        vals.append(v - 256 if v >= 128 else v)   # two's complement int8
    return vals

w1 = read_hex("w1.mem")             # 2048 values, address = i * 32 + j
x  = read_hex("known_input_0.mem")  # 64 pixels

N_IN, N_OUT = 64, 32
neuron0 = [w1[i * N_OUT + 0] for i in range(N_IN)]   # weights into hidden neuron 0

with open("w1_neuron0.mem", "w") as f:
    for v in neuron0:
        f.write(f"{v & 0xff:02x}\n")

print("expected accumulator:", sum(a * b for a, b in zip(x, neuron0)))
