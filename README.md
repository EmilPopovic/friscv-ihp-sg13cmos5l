# FRISC-V Tapeout

The first tapeout of the FRISC-V core, targeting IHP's open-source **SG13CMOS5L**
130nm process.

The SoC lives in [vernii](https://github.com/EmilPopovic/vernii) and is pulled in as a Bender dependency. This repository holds everything that is specific to the chip: `chip_soc` wraps `vernii_soc` with the HyperBus controller on its AXI4 manager port and brings every peripheral out to its pins, and `RVSoC9108` (target/ihp-sg13cmos5l/src/RVSoC9108.sv) adds the pad ring.

## Setup

The toolchain is provided by **Nix**.

This should work on all Linux distros, including WSL2, but was only tested on Ubuntu 26.04 LTS and Arch using zsh.

**Prerequisites:**

- `curl` (to bootstrap the Nix installer)
- `direnv` (for automatic activation, usually `<pkg-manager> install direnv`)

Clone and run the setup script:

```bash
git clone https://github.com/EmilPopovic/friscv-ihp-sg13cmos5l.git
cd friscv-ihp-sg13cmos5l
./setup.sh
```

`setup.sh` will:

1. Install **Nix** if it isn't present (one-time step).
2. Generate `flake.lock`.
3. Install **nix-direnv** so the environment auto-activates.

### Activating the environment

Make sure your shell has the direnv hook (add to your shell rc):

```bash
eval "$(direnv hook zsh)"   # zsh  -> ~/.zshrc
eval "$(direnv hook bash)"  # bash -> ~/.bashrc
```

Then, in the repo root:

```bash
direnv allow
```

The first activation downloads the prebuilt tools (a few minutes). After that, `cd`-ing into the repo puts every tool on your `PATH` automatically.

## Repository layout

- `hw/` - `chip_soc` and the vendored PULP HyperBus.
- `target/ihp-sg13cmos5l/` - synthesis, LibreLane flow, pad ring, PDK cells.
- `target/sim/` - Verilator and Icarus simulation harness, directed tests.
- `target/xilinx/pynq-z2/` - FPGA counterpart of the chip.
- `docs/` - design notes.
- `flake.nix` - Nix toolchain definition.
