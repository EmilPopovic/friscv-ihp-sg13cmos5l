# HyperBus timing

HyperBus simulation with the chip's real delays, fast/typ/slow, every TX/RX
tap pair. Run inside `nix develop`.

```bash
./hbt sweep configs/vernii.toml    # all tap pairs -> work/vernii/sweep/sweep.txt
./hbt check configs/vernii.toml    # stress the reset taps -> work/vernii/check/check.txt
./hbt run configs/vernii.toml --fast +corner=slow +tx_code=9 +rx_code=12 +verbose
make tables                        # regenerate configs/vernii/*.json
make signoff                       # tables, sweep, check
```

`configs/vernii/*.json` come from the LibreLane run in `[flow]`:

- `delay_line.json`, `pads.json`: `./hbt char`
- `chip_delays.json`: `./hbt extract`

sweep: `--corners` `--tx` `--rx` (`all`, `0-7`, `3,5`, `all:2`) `--n-txn`
`--jobs` `--extra` `--tag` `--require-reset`

check: `--tx` `--rx` `--jobs`

run: `+corner` `+tx_code` `+rx_code` `+mem_tckds` `+rwds_mode` `+skew_pattern`
`+n_txn` `+seed` `+verbose` `+trace_bus=N` `+trace_from_ns` `+trace_to_ns`
`+max_msgs` `+tck_ns` `+load_pf` `+flight_ns` `+flight_skew_ns` `+jitter_ns`
`+duty` `+ocv` `+ocv_pattern` `+long_bursts` `+t_burst_max` `+mem_fixed`
`+refresh_pct`