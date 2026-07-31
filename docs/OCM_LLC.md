# Switchable OCM / LLC — review and implementation roadmap

Target: a way-switchable memory block where each way of the on-chip SRAM is either
directly addressable on-chip memory (OCM) or a way of a **write-through,
no-write-allocate** last-level cache in front of the HyperRAM. Configuration comes
from the SCB: `LLCSEL` picks the per-way mode, `CRPSEL` picks the replacement
policy (round-robin vs random).

Files in scope: [friscv_ocm_llc.sv](../rtl/soc/friscv_ocm_llc.sv),
[friscv_mem_hub.sv](../rtl/soc/friscv_mem_hub.sv),
[friscv_scb.sv](../rtl/soc/friscv_scb.sv),
[friscv_soc.sv](../rtl/soc/friscv_soc.sv),
[friscv_axi4_full_adapter_intf.sv](../rtl/soc/friscv_axi4_full_adapter_intf.sv).

---

## 1. Geometry for the default SoC configuration

From `friscv_soc.sv` (`SramSize=0x4000`, `MemBase=0x8000_0000`,
`MemSize=0x0100_0000`, `LineBytes=64`, `Ways=4`):

| Quantity | Value |
| --- | --- |
| `SIZE_BYTES` | 16 KiB total SRAM |
| `WAYS` | 4 → 4 KiB per way, 1 `tc_sram` of 1024×32 each |
| `LINE_BYTES` | 64 → 16 words per line, `OFFSET_W = 6` |
| `SETS` | 64 → `IDX_W = 6` |
| `REGION_LOG2` | `$clog2(0x0100_0000)` = 24 |
| `TAG_W` | 24 − 6 − 6 = 12 |
| OCM way granularity | 4 KiB (way select = `addr[13:12]`) |
| SCB registers | `LLCSEL` @ `0x4000_000C`, `CRPSEL` @ `0x4000_0010` |

Cache capacity when all four ways are cache: 16 KiB, 4-way, 64 sets, 64 B lines.
Each way switched to cache removes 4 KiB of contiguous OCM.

---

## 2. Review of the current code

The OCM datapath is functional in the common case; everything cache-related is a
stub. Findings ordered by severity.

### B1 — The cache lookup can never fire (dead code)

`w_hit_arr` is `w_hit_arr_d` delayed one cycle
([friscv_ocm_llc.sv:159-162](../rtl/soc/friscv_ocm_llc.sv#L159-L162)), but the
way-enable term requires `w_do_lookup && w_hit_arr[i]`
([friscv_ocm_llc.sv:188](../rtl/soc/friscv_ocm_llc.sv#L188)) and `w_do_lookup`
requires `w_req`.

With `REGISTER_REQ=1`, `to_mem` latches the address at the end of `S_IDLE`, drives
`w_req` for exactly the `S_REQ` cycle, and samples `rvalid` in `S_RSP`. So
`w_hit_arr_d` is valid in `S_REQ` and `w_hit_arr` is valid in `S_RSP` — the two
terms are never true in the same cycle. The tag compare must feed the SRAM enable
in the same cycle it is computed (`w_hit_arr_d`), and only the *output* mux may use
the registered `w_hit_arr`.

### B2 — Data-SRAM requests are not gated by `w_req`

The OCM branch asserts `w_way_req[i] = 1'b1` whenever the (registered, therefore
sticky) address decodes into the OCM region
([friscv_ocm_llc.sv:195-200](../rtl/soc/friscv_ocm_llc.sv#L195-L200)). Between
transactions `to_mem` keeps driving the last `addr_o`/`we_o`/`wdata_o`, so the SRAM
sees a request — and after a store, a *write* — every idle cycle. It is idempotent
today (same address, same data) so it does not corrupt state, but it is continuous
SRAM dynamic power, and it becomes a real hazard once the refill engine wants the
same port. Gate every way request with `w_req`.

### B3 — A stale hit vector can hijack the OCM read mux

The read mux tests the cache condition first
([friscv_ocm_llc.sv:214](../rtl/soc/friscv_ocm_llc.sv#L214)). `w_hit_arr` is not
qualified by "this transaction was a lookup", so a hit left over from a previous
cached access can steal the mux from a subsequent OCM access. Register
`w_do_lookup` alongside `w_hit_arr`, or better: restructure the mux to select on
the way's *mode* rather than on the transaction (see §4, Phase 2).

### B4 — `w_illegal_ocm_access` never reaches the CPU

`w_err` is registered ([friscv_ocm_llc.sv:71](../rtl/soc/friscv_ocm_llc.sv#L71))
but `to_mem.err_i` is tied to `1'b0`
([friscv_ocm_llc.sv:57](../rtl/soc/friscv_ocm_llc.sv#L57)), so an access to an OCM
way that is currently configured as cache silently returns garbage instead of a
bus error. Wire `.err_i(w_err)`.

### B5 — No stall mechanism

`w_gnt` is hardwired to 1 and `w_rvalid <= w_req` unconditionally
([friscv_ocm_llc.sv:64-73](../rtl/soc/friscv_ocm_llc.sv#L64-L73)). A miss has no
way to hold the requester off. The mechanism is already available for free:
`to_mem` stays in `S_REQ` with `req_o` held while `gnt_i` is low, so
`w_gnt = !stall` plus `w_rvalid <= w_req && w_gnt` gives a correct blocking stall
with no extra state.

### B6 — `m_mem_if` is undriven

Only `rw` is tied off ([friscv_ocm_llc.sv:171](../rtl/soc/friscv_ocm_llc.sv#L171));
`addr`, `size`, `wdata` and `burst_en` are never assigned, and `wait_req`,
`beat_valid`, `err`, `rdata` are never consumed. There is no downstream path at all.

### B7 — The cacheable region never reaches the module

`friscv_mem_hub` demuxes `MemBase..+MemSize` straight to `m_ext_if` and only the
SRAM region to `sram_if`
([friscv_mem_hub.sv:196-226](../rtl/soc/friscv_mem_hub.sv#L196-L226)), and
`refill_if` is instantiated but left dangling
([friscv_mem_hub.sv:232](../rtl/soc/friscv_mem_hub.sv#L232)). Consequently
`w_match_cached`, `w_sel_cached` and `w_do_lookup` are unreachable. This is the
single largest structural gap: the LLC is not in the path it is supposed to cache.

### B8 — Tag/valid state is never written, and hits are not way-masked

The `always_ff` over `r_tag_arr`/`r_valid_arr` has an empty else branch
([friscv_ocm_llc.sv:134-141](../rtl/soc/friscv_ocm_llc.sv#L134-L141)), and
`w_hit_arr_d[i]` does not include `i_way_is_cache[i]`
([friscv_ocm_llc.sv:152](../rtl/soc/friscv_ocm_llc.sv#L152)). A way that was used
as OCM and is later switched to cache will have arbitrary valid bits, so unmasked
hit terms can produce a false hit. `llc_state_e` is declared and unused
([friscv_ocm_llc.sv:122-126](../rtl/soc/friscv_ocm_llc.sv#L122-L126)).

### B9 — `LLCSEL`/`CRPSEL` are not reset

The SCB reset branch initialises `r_scratch0`, `r_hb_en`, `r_strapped`, `r_strapa`
but not `r_llcsel`/`r_crpsel`
([friscv_scb.sv:61-67](../rtl/soc/friscv_scb.sv#L61-L67)). Out of reset
`i_way_is_cache` is X, which poisons the OCM decode, `w_illegal_ocm_access` and the
read mux. The ZSBL boots by polling SCB `SCRATCH0` and then jumping into OCM
([sw/boot/zsbl.S](../sw/boot/zsbl.S)), so **all-OCM (`LLCSEL = 0`) must be the
reset default**.

### B10 — Refill burst length does not match the line size

`friscv_axi4_full_adapter_intf` does not expose `BURST_LEN`
([friscv_axi4_full_adapter_intf.sv:11-24](../rtl/soc/friscv_axi4_full_adapter_intf.sv#L11-L24)),
so the adapter uses its default of 8 beats × 32 bit = 32 B, while `LINE_BYTES` is
64. One of: plumb `BURST_LEN = LineBytes/4` through the wrapper (preferred), issue
two bursts per refill, or reduce `LINE_BYTES` to 32.

### B11 — Misleading comment on the OCM layout

[friscv_ocm_llc.sv:180](../rtl/soc/friscv_ocm_llc.sv#L180) says
`[X, WAY_ADDR, WAY_SEL, BYTE_SEL]`, but the code puts the way select *above* the
word address (`addr[13:12]` vs `addr[11:2]`), i.e. `[X, WAY_SEL, WAY_ADDR,
BYTE_SEL]` — contiguous 4 KiB blocks per way. The C++ preload model already
documents the correct order
([soc_memory.cpp:16-19](../target/sim/cpp/soc_memory.cpp#L16-L19)); fix the RTL
comment so they agree.

### B12 — Parameterisation gaps

* `WAYS = 1` gives a zero-width `w_ocm_way_sel`; `SETS = 1` gives `IDX_W = 0`.
* `w_match_cached` uses `(1 << REGION_LOG2)` and bare 32-bit arithmetic, whereas
  the hub casts with `addr_t'()`. It also assumes `MEM_SIZE` is a power of two —
  true today, but unchecked.
* No elaboration assertions tie `SIZE_BYTES`, `LINE_BYTES`, `WAYS` and `SETS`
  together, so a bad parameter set silently produces a broken address split.

---

## 3. Design decisions

Recommendations; each is a decision point worth confirming before coding.

**D1. Where the LLC sits.** Make `friscv_ocm_llc` the slave for *both* the OCM
region and the cacheable MEM region, and let its `m_mem_if` drive the hub's
`m_ext_if`. The hub demux becomes `{ocm_llc, m_sys_if}`; the LLC forwards
MEM-region traffic downstream on misses, on writes, and unconditionally when
`LLCSEL == 0`.

**D2. Blocking, one outstanding transaction.** The hub already serialises CPU and
DM into a single request. Keep the LLC strictly blocking: stall via `w_gnt`, no
hit-under-miss, no write buffer. Everything else is a later optimisation.

**D3. Write hit → update in place.** No-write-allocate fixes the *miss* behaviour
(forward, do not allocate). On a write *hit* the line must not go stale: either
write the word into the hitting way (byte enables already exist on `tc_sram`) or
invalidate the line. Recommend update-in-place — it is one extra way-enable term
and preserves the line.

**D4. Refill then replay.** On a read miss, fill the whole line into the victim
way, write tag+valid, then re-drive the normal lookup read and grant. Costs one
extra cycle versus critical-word-first but keeps a single read datapath and no
bypass mux. Critical-word-first can be added later behind the same interface.

**D5. Line size ties to burst length.** Pick `LINE_BYTES = 64` and plumb
`BURST_LEN = LINE_BYTES/4 = 16` (see B10). `r_count` in the adapter is 5 bits, so
16 beats fits. A refill address is line-aligned, so a 16-beat INCR burst cannot
cross a 4 KiB boundary.

**D6. Read all cache ways in parallel; select on the registered hit.** The
alternative — gating each way's SRAM enable with the combinational hit — puts a
64:1 tag mux plus a 12-bit compare on the SRAM enable/address setup path. At 130 nm
that is the wrong risk to take. Enabling all cache ways costs read energy in up to
4 macros per lookup and can be revisited if power, not timing, turns out to be the
constraint.

**D7. Replacement.** Per-set round-robin pointer (`SETS × $clog2(WAYS)` = 128
flops) plus a shared LFSR (16 bits) for random. `CRPSEL` selects which index feeds
victim selection. Both must be masked to eligible ways.

**D8. Victim selection.** Prefer an *invalid* eligible way first, then fall back to
the policy index. Because the policy index may land on a way that is currently OCM,
the selection is a rotate-and-priority-select over `i_way_is_cache`, not a bare
index — do not skip this or a cache/OCM mix will corrupt OCM data.

**D9. `LLCSEL` change semantics.** Switching a way OCM→cache inherits garbage valid
bits (B8); switching cache→OCM exposes cache data as OCM. Implement hardware
auto-invalidate: detect a change in `i_way_is_cache`, clear the valid bits of the
affected ways, and stall new requests for that cycle (valid bits are flops, so a
single-cycle bulk clear is possible). Also document that a way's OCM contents are
destroyed by a round trip through cache mode. No dirty-data flush is ever needed —
write-through means the cache is never the only copy.

**D10. `LLCSEL` mask shape.** Because the way select is the *top* OCM address bits,
only a top-aligned mask keeps OCM contiguous: `0b1000` leaves 12 KiB at the base,
`0b0101` leaves two 4 KiB blocks with a hole at `0x1000`. Decide whether hardware
constrains the mask (e.g. accept only `{1…1,0…0}` patterns) or software owns the
convention. Recommend leaving hardware permissive and documenting it, since the
illegal-access error (B4) already makes holes safe to probe.

**D11. `HBCTL.HB_EN` interaction.** `friscv_hb_guard` returns an error when the
HyperBus is disabled ([friscv_hb_guard.sv:33-38](../rtl/soc/friscv_hb_guard.sv#L33-L38)).
A refill with `HB_EN = 0` must propagate the error to the CPU and **not** validate
the line. Add that to the refill error path rather than assuming software ordering.

---

## 4. Roadmap

### Phase 0 — Fix the OCM path (no cache behaviour yet)

Independent of everything else, and it makes the current tests meaningful.

* Gate all `w_way_req` with `w_req` (B2).
* `.err_i(w_err)` on the `to_mem` instance (B4).
* Reset `r_llcsel`/`r_crpsel` to 0 in the SCB (B9).
* Fix the layout comment (B11); add `addr_t` casts and elaboration assertions for
  the parameter relationships (B12).

*Exit:* existing SoC sim and `make act-run-soc` still pass; an access to an OCM way
marked as cache in `LLCSEL` raises a bus error; the way SRAMs see enables only on
real requests.

### Phase 1 — Put the LLC in the cacheable path (bypass only)

Restructure `friscv_mem_hub` per D1: the LLC takes both regions on `s_mem_if`, its
`m_mem_if` drives `m_ext_if`, and `refill_if` disappears. In the LLC, drive the
full `m_mem_if` request (`addr`, `size`, `wdata`, `rw`, `burst_en=0`) and the
response path (`rdata`, `wait_req`, `beat_valid`, `err`) for a pure pass-through of
MEM-region traffic. Introduce `w_gnt = !stall` and `w_rvalid <= w_req && w_gnt`
(B5); pass-through completions are driven by downstream `wait_req`.

*Exit:* with `LLCSEL = 0` the SoC behaves exactly as before — HyperRAM tests pass
through the LLC with no functional change. This is the checkpoint that de-risks the
integration before any cache state exists.

### Phase 2 — Lookup timing and read hits

* Restructure the per-way mux to branch on the way's *mode*, not on the transaction
  (kills B3 structurally):
  ```
  if (i_way_is_cache[i]) → cache port (lookup / refill write / write-hit update)
  else                   → OCM port
  ```
* Mask `w_hit_arr_d[i]` with `i_way_is_cache[i]` (B8).
* Read all cache ways on a lookup (D6); select `w_rdata` with the registered
  `w_hit_arr`.
* Treat every lookup as a miss for now and forward it downstream as a single beat.

*Exit:* `w_hit`/`w_hit_arr` are observably correct in waveforms against a
software-computed expectation; no functional change yet because tags are still never
written.

### Phase 3 — Refill engine and allocation

* Plumb `BURST_LEN` through `friscv_axi4_full_adapter_intf` and set it from
  `LineBytes` in `friscv_soc.sv` (B10, D5).
* Implement the `LLC_IDLE / LLC_LOOKUP / LLC_REFILL` FSM: on a read miss, issue a
  line-aligned burst read with `burst_en=1`, count `beat_valid` pulses, write each
  beat into the victim way at `{idx, beat}`, then write `r_tag_arr`/`r_valid_arr`,
  replay the lookup, and grant (D4).
* Error handling: `m_mem_if.err` during refill → return the error to the CPU and
  leave the line invalid (D11).
* Hold `rw` and `burst_en` stable for the whole burst — the adapter latches at
  `S_IDLE` and holds `wait_req` until the last beat.

*Exit:* a read miss produces exactly one 16-beat burst in the HyperRAM model; a
second read of the same line produces no bus traffic and returns the same data;
16 consecutive words of a refilled line all hit.

### Phase 4 — Write path

* Write to the cached region: forward downstream, complete when downstream
  completes (write-through, blocking).
* Write miss: no allocation, no tag update.
* Write hit: additionally write the word into the hitting way with the incoming
  byte enables (D3).

*Exit:* a store to the cached region is visible in the HyperRAM model without any
flush; a store to an uncached line does not create a valid line; a store to a
cached line followed by a load returns the new data with no bus read.

### Phase 5 — Replacement policy and `CRPSEL`

* Per-set round-robin pointer, advanced on allocation into that set (D7).
* Shared LFSR, e.g. 16-bit maximal Fibonacci, advanced every cycle so the value is
  decorrelated from the access pattern.
* Victim = first invalid eligible way, else rotate-and-priority-select over
  `i_way_is_cache` starting at the policy index (D8).

*Exit:* with `CRPSEL = 0` a directed thrash pattern over `WAYS+1` lines evicts in a
deterministic, reproducible order; with `CRPSEL = 1` the same pattern shows a
different, non-repeating victim sequence and no way outside `LLCSEL` is ever
allocated.

### Phase 6 — `LLCSEL` change and invalidate

* Detect a change on `i_way_is_cache`, bulk-clear the valid bits of the changed
  ways, stall for the clear (D9).
* Optional but cheap: an SCB `LLCINV` write-1-to-invalidate-all bit, and a status
  bit indicating the LLC is idle. Worth adding — it makes cache experiments
  scriptable without a reset.

*Exit:* switching a way cache→OCM→cache never returns stale cached data; switching
OCM→cache→OCM never returns stale OCM data; a mid-stream `LLCSEL` write does not
hang the bus.

### Phase 7 — Verification

* Directed C++ tests on the existing SoC testbench (`hyperram.cpp` gives a
  reference memory to check against): per-way OCM read/write; illegal-OCM-access
  error; hit/miss; write-through visibility; no-write-allocate; set conflict and
  eviction order per policy; `LLCSEL` transitions; mixed OCM + cache traffic in the
  same test.
* `soc_memory.cpp` preloads the OCM assuming all four ways are OCM. That stays
  valid once `LLCSEL` resets to 0 (B9), but tests that enable cache ways must
  either preload first or keep code and stack in OCM ways.
* Concurrent assertions: hit vector is one-hot; a way is never enabled as both OCM
  and cache in the same cycle; no way outside `LLCSEL` is ever allocated; refill
  beat count equals `LINE_BYTES/4`; at most one outstanding downstream request.
* `make act-run-soc` for regression, plus an LLC-enabled variant of the arch-test
  run with the text section left in OCM.

### Phase 8 — PPA

* State cost at the default geometry: 3072 tag flops + 256 valid + 128 RR + 16 LFSR
  ≈ 3.5 k flops, plus a 64:1 × 12-bit read mux per way and four 12-bit comparators.
  Measure with `make report-area` and compare against the ≈1.57 mm² baseline before
  committing to flop-based tags; a tag SRAM is the fallback, at the cost of one
  pipeline stage and losing the same-cycle compare that D6 relies on.
* Check the paths `addr_q → decode → tag mux → compare → w_hit_arr` and
  `addr_q → way-enable/address → tc_sram` in synthesis; the hub arbiter mux sits
  ahead of both.
* Confirm the extra `tc_sram` enable terms did not break the banked
  `RM_IHPSG13_1024x32` mapping.

---

## 5. Open questions

1. `MemSize` is 16 MiB but the HyperBus is instantiated with
   `RstChipSpace = 0x0080_0000` (8 MiB) in
   [friscv_soc.sv:412](../rtl/soc/friscv_soc.sv#L412). The upper 8 MiB of the
   cacheable region has no backing chip space — should `REGION_LOG2` follow the
   chip space instead, to keep tags from covering unreachable addresses?
2. Should `LLCSEL` be constrained in hardware to top-aligned masks (D10)?
3. Is critical-word-first refill worth the extra bypass mux for the expected
   HyperRAM latency, or is refill-then-replay (D4) good enough for this tapeout?
4. AMOs are resolved in `friscv_amo_unit` above this interface, so they arrive as
   independent read/write pairs. A blocking LLC keeps them correct on a single core
   — confirm no future dual-issue or DMA path breaks that assumption.
