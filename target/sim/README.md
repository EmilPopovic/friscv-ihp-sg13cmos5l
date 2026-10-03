# Simulation

One C++ harness is used for three builds.

| Target | Simulator | DUT | Description |
| ------ | --------- | --- | ----------- |
| `make chip` | Verilator `--timing` | `RVSoC9108` behind `rtl/tb_chip.sv` with the PDK pad, SRAM, and cell models | Regression (`make test`) |
| `make soc` | Verilator | `chip_soc` without pad ring | For ACTs, HyperRAM sweeps, debugging (`make test-soc`) |
| `make gls` | Icarus, 4-state | Final netlist behind `rtl/tb_gls.sv` | Regression on what is being taped out (`make test-gls`) |

## Commands

```bash
obj_dir_chip/chip_sim test <program.elf>        # run to the end store, PASS/FAIL
obj_dir_chip/chip_sim qspiboot <image.bin>      # boot select 1, image in flash
obj_dir_chip/chip_sim uartboot <stage.bin>      # boot select 2, stage over UART
obj_dir_chip/chip_sim load <program.elf>        # load over JTAG, run 2000 cycles
obj_dir_chip/chip_sim read <address> <size>
obj_dir_chip/chip_sim write <address> <byte> [byte ...]
obj_dir_chip/chip_sim server [port]             # remote bitbang for OpenOCD
```

## Environment

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `VERNII_TEST_CYCLES` | 10000000 | Cycle limit for `test`, `qspiboot`, `uartboot` |
| `VERNII_FLOAT_SEED` | 1 | Seed for what floating pads read |
| `VERNII_PROGRESS` | | Seconds between progress lines |
| `VERNII_LLCSEL` | | LLC ways used as cache |
| `VERNII_UART_DIV` | | UART divisor |
| `VERNII_FLASH` | | Flash image for programs that drive flash themselves |
| `VERNII_SD_IMAGE` | | SD card image |
| `VERNII_BOOT_SEL` | 2 | Boot select for `uartboot` |
| `VERNII_HB_CFG` | | `reg:value[,...]` HyperBus controller registers |
| `VERNII_HRAM_LATENCY` | 6 | HyperRAM initial latency in clocks |
| `VERNII_HRAM_FIXED` | 0 | Twice the latency on every access |
| `VERNII_HRAM_REFRESH_EVERY` | 0 | Refresh collision every Nth access |
| `VERNII_HRAM_TCSM` | 0 | Maximum CS# low clocks, 0 disables the check |
| `VERNII_HRAM_STRICT` | 1 | 0 warns on HyperRAM timing violations instead of failing |

## Tests

```bash
make test      # chip build, with seeds 1 2 3
make test-soc  # same on the SoC build
make -C tests run SIM=<binary> SEEDS=1
make -C tests run -j8 PROGRESS=60  # in parallel, progress every minute
```

Test sources come from Vernii's `verif/directed`, and `hb_mem.S` and `gpio_loop.S` come from here. Logs go to `tests/build/<test>.<seed>.log`.

## HyperRAM model

`cpp/hyperram.cpp` models one device per HyperBus chip select and enforces its timing.

```bash
for lat in 3 4 5 6 7; do
    VERNII_HRAM_LATENCY=$lat VERNII_HB_CFG=0:$lat obj_dir_soc/friscv_soc test program.elf
done
```

## Gate-level simulation

```bash
make test-gls  # newest librelane run, seed 1
make gls NETLIST=<path>/RVSoC9108.nl.v
vvp -n -M obj_dir_gls -m vernii obj_dir_gls/gls.vvp test <program.elf>
```

## Debugging

Start a simulator and the debug server from the repository root:

```bash
make -C target/sim debug  # SIM=soc for chip_soc alone
```

GDB can then connect from another terminal:

```bash
riscv64-unknown-elf-gdb program.elf
(gdb) target extended-remote 127.0.0.1:3333
(gdb) load
```
