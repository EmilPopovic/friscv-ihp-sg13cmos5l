# FRISC-V Tapeout

The first tapeout of the FRISC-V core, targeting IHP's open-source **SG13CMOS5L**
130nm process.

The SoC itself lives in [friscv-soc](https://github.com/EmilPopovic/friscv-soc)
and is pulled in as a Bender dependency. This repository holds everything that
is specific to the chip: `friscv_chip_soc` wraps `vernii_soc` with the HyperBus
controller on its AXI4 master port and brings every peripheral out on its own
dedicated pins, and `chip_top` adds the 64-pad ring.

To develop both together, point Bender at a local checkout in `Bender.local`:

```yaml
overrides:
  friscv-soc: { path: "../friscv-soc" }
```

## Setup

The toolchain is provided by **Nix**. This flow is inspired by
[LibreLane](https://librelane.readthedocs.io) which uses the same mechanism.

This should work on all Linux distros, including WSL, but was only tested on
Ubuntu 26.04 LTS and Arch using zsh.

**Prerequisites:**

- `curl` (to bootstrap the Nix installer)
- `direnv` (for automatic activation, usually `<pkg-manager> install direnv`)

Clone and run the setup script:

```bash
git clone https://github.com/EmilPopovic/friscv-tapeout.git
cd friscv-tapeout
./setup.sh
```

`setup.sh` will:

1. Install **Nix** if it isn't present - a one-time step that asks for `sudo`.
   Everything after this needs no sudo. It enables flakes and adds the FOSSi binary cache.
2. Generate `flake.lock`
3. Install and hook up **nix-direnv** so the environment auto-activates.

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

The first activation downloads the prebuilt tools (a few minutes). After that,
`cd`-ing into the repo puts every tool on your `PATH` automatically.

### Tools provided

Synthesis and simulation: **Yosys**, **Icarus Verilog**, **Verilator**, **ngspice**,
**GTKWave**. Physical design and sign-off: **OpenROAD**, **KLayout**, **Magic**,
**Netgen** (LVS).

To change the tool set, edit the `packages` list in `flake.nix`, then
`direnv reload`. Commit the updated `flake.lock`.

## Simulation

`make sim` builds a chip-level Verilator model of `friscv_chip_soc` with C++
models for the HyperRAM, the QSPI flash and the UART.

```bash
make sim
./target/sim/obj_dir_soc/friscv_soc test <program.elf>
./target/sim/obj_dir_soc/friscv_soc qspiboot <image.bin>
```

## Repository layout

- `hw/` - `friscv_chip_soc` and the vendored PULP HyperBus.
- `target/ihp-sg13cmos5l/` - synthesis, LibreLane flow, pad ring, PDK cells.
- `target/sim/` - chip-level C++/Verilator simulation harness.
- `target/xilinx/pynq-z2/` - FPGA counterpart of the chip.
- `docs/` - design notes.
- `flake.nix` - Nix toolchain definition.
