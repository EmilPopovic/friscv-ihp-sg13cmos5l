// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Matej Jurasic <matej.jurasic@cappig.dev>

// Runs the harness on its own thread inside vvp, vvp keeps the time

#include <vpi_user.h>

#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "Vtb_chip.h"

int harness_main(int argc, char** argv);

namespace {

struct Signal {
    const char* name;
    unsigned width;
    uint32_t Vtb_chip::*field;
    vpiHandle handle = nullptr;
    uint64_t delay = 0;
    uint32_t last = ~0u;
    uint32_t x = 0;
    uint64_t x_count = 0;
    uint64_t data_x_count = 0;
    uint64_t first_x = 0;
};

// Asynchronous inputs come after the clock edge, TMS and TDI before TCK
const struct {
    const char* name;
    uint64_t ps;
} input_delays[] = {
    {"jtag_tms_i", 1000},   {"jtag_tdi_i", 1000}, {"rst_ni", 2000},
    {"jtag_trst_ni", 2000}, {"boot_sel_i", 2000}, {"uart0_rx_i", 2000},
    {"jtag_tck_i", 3000},
};

// The models sample these between clock edges
const char* const watched[] = {
    "hyper_ck_o",    "hyper_cs_no",     "hyper_reset_no", "hyper_dq_o", "hyper_dq_oe_o",
    "hyper_rwds_o",  "hyper_rwds_oe_o", "qspi0_sck_o",    "qspi0_cs_o", "qspi0_sd_o",
    "qspi0_sd_oe_o", "gpio_a_o",        "gpio_a_oe_o",
};

enum class Request { EVAL, RUN, FINISH };

std::vector<Signal> inputs;
std::vector<Signal> outputs;
Signal* tdo = nullptr;
Signal* dq = nullptr;

std::mutex mutex;
std::condition_variable turn;
bool vvp_turn = false;
Request request = Request::EVAL;
int exit_code = 0;

Vtb_chip* top = nullptr;
uint64_t target = 0;
uint64_t horizon = 0;

uintptr_t run_id = 0;
bool running = false;
bool stopping = false;
uint64_t run_start = 0;
uint64_t run_end = 0;

uint64_t ps_units = 1;
int reset_edges = 0;

std::vector<std::string> args;
std::vector<char*> argv;

uint32_t mask(unsigned width) {
    return width >= 32 ? ~0u : (1u << width) - 1;
}

s_vpi_time vpi_time(uint64_t ps) {
    uint64_t units = ps * ps_units;
    return {vpiSimTime, PLI_UINT32(units >> 32), PLI_UINT32(units), 0};
}

uint64_t now() {
    s_vpi_time time = {vpiSimTime, 0, 0, 0};
    vpi_get_time(nullptr, &time);
    return ((uint64_t(time.high) << 32) | time.low) / ps_units;
}

void schedule(PLI_INT32 reason, uint64_t delay, PLI_INT32 (*routine)(p_cb_data),
              uintptr_t id = 0) {
    s_vpi_time time = vpi_time(delay);

    s_cb_data cb = {};
    cb.reason = reason;
    cb.cb_rtn = routine;
    cb.time = &time;
    cb.user_data = reinterpret_cast<PLI_BYTE8*>(id);
    vpi_register_cb(&cb);
}

void put_inputs() {
    for (Signal& signal : inputs) {
        uint32_t bits = top->*signal.field & mask(signal.width);

        if (bits == signal.last) {
            continue;
        }
        signal.last = bits;

        s_vpi_vecval vector = {PLI_INT32(bits), 0};
        s_vpi_value value = {};
        value.format = vpiVectorVal;
        value.value.vector = &vector;

        if (signal.delay == 0) {
            vpi_put_value(signal.handle, &value, nullptr, vpiNoDelay);
        } else {
            s_vpi_time time = vpi_time(signal.delay);
            vpi_put_value(signal.handle, &value, &time, vpiTransportDelay);
        }
    }

    // Check for X once the harness has pulsed reset high, low, high
    const bool levels[] = {true, false, true};

    if (reset_edges < 3 && bool(top->rst_ni) == levels[reset_edges]) {
        reset_edges++;
    }
}

void get_outputs() {
    for (Signal& signal : outputs) {
        s_vpi_value value = {};
        value.format = vpiVectorVal;
        vpi_get_value(signal.handle, &value);

        signal.x = value.value.vector[0].bval & mask(signal.width);
        top->*signal.field = value.value.vector[0].aval & ~signal.x & mask(signal.width);
    }

    if (reset_edges < 3) {
        return;
    }

    for (Signal& signal : outputs) {
        // TDO floats until the TAP is reset
        if (!signal.x || &signal == tdo) {
            continue;
        }

        // Software may store a register nothing has written
        if (&signal == dq && top->hyper_rwds_oe_o) {
            signal.data_x_count++;
            continue;
        }

        if (signal.x_count++ == 0) {
            signal.first_x = now();
        }
    }
}

int finish(int code) {
    bool x = false;

    for (const Signal& signal : outputs) {
        if (signal.data_x_count) {
            std::fprintf(stderr, "X on %s in write data, %llu evals\n", signal.name,
                         (unsigned long long)signal.data_x_count);
        }

        if (signal.x_count) {
            std::fprintf(stderr, "X on %s from %.3f us, %llu evals\n", signal.name,
                         signal.first_x / 1e6, (unsigned long long)signal.x_count);
            x = true;
        }
    }

    if (x && code == 0) {
        std::fprintf(stderr, "FAIL (X on pads)\n");
        code = 1;
    }

    std::fflush(stderr);
    return code;
}

PLI_INT32 on_eval(p_cb_data);
PLI_INT32 on_horizon(p_cb_data);

// Start the harness request, false if it is already answered
bool start() {
    uint64_t t = now();

    switch (request) {
    case Request::FINISH:
        std::exit(finish(exit_code));

    case Request::EVAL:
        schedule(cbAfterDelay, target > t ? target - t : 1, on_eval);
        return true;

    case Request::RUN:
        if (horizon <= t) {
            run_end = t;
            return false;
        }

        running = true;
        stopping = false;
        run_start = t;
        schedule(cbAfterDelay, horizon - t, on_horizon, ++run_id);
        return true;
    }

    return true;
}

void serve(std::unique_lock<std::mutex>& lock) {
    do {
        vvp_turn = false;
        turn.notify_all();
        turn.wait(lock, [] { return vvp_turn; });
    } while (!start());
}

void serve() {
    std::unique_lock<std::mutex> lock(mutex);
    serve(lock);
}

PLI_INT32 on_settled(p_cb_data) {
    get_outputs();
    serve();
    return 0;
}

PLI_INT32 on_eval(p_cb_data) {
    put_inputs();
    schedule(cbReadOnlySynch, 0, on_settled);
    return 0;
}

PLI_INT32 on_run_end(p_cb_data cb) {
    if (!running || reinterpret_cast<uintptr_t>(cb->user_data) != run_id) {
        return 0;
    }

    running = false;
    run_end = now();
    serve();
    return 0;
}

PLI_INT32 on_horizon(p_cb_data cb) {
    schedule(cbReadOnlySynch, 0, on_run_end, reinterpret_cast<uintptr_t>(cb->user_data));
    return 0;
}

PLI_INT32 on_change(p_cb_data) {
    uint64_t t = now();

    if (running && !stopping && t > run_start && t < horizon) {
        stopping = true;
        schedule(cbReadOnlySynch, 0, on_run_end, run_id);
    }

    return 0;
}

void watch(vpiHandle handle) {
    static s_vpi_time time = {vpiSuppressTime, 0, 0, 0};
    static s_vpi_value value = {vpiSuppressVal, {}};

    s_cb_data cb = {};
    cb.reason = cbValueChange;
    cb.cb_rtn = on_change;
    cb.obj = handle;
    cb.time = &time;
    cb.value = &value;
    vpi_register_cb(&cb);
}

void handoff(Request what) {
    std::unique_lock<std::mutex> lock(mutex);

    request = what;
    vvp_turn = true;
    turn.notify_all();
    turn.wait(lock, [] { return !vvp_turn; });
}

void run_harness() {
    int code = harness_main(int(argv.size()) - 1, argv.data());

    std::lock_guard<std::mutex> lock(mutex);
    exit_code = code;
    request = Request::FINISH;
    vvp_turn = true;
    turn.notify_all();
}

// Harness arguments follow the .vvp file, plusargs are vvp's
void collect_args() {
    s_vpi_vlog_info info = {};
    vpi_get_vlog_info(&info);

    args.push_back("chip_sim");
    bool after = false;

    for (int i = 0; i < info.argc; ++i) {
        std::string arg = info.argv[i];

        if (after && arg[0] != '+') {
            args.push_back(arg);
        }

        after |= arg.size() > 4 && arg.compare(arg.size() - 4, 4, ".vvp") == 0;
    }

    for (std::string& arg : args) {
        argv.push_back(arg.data());
    }
    argv.push_back(nullptr);
}

vpiHandle find(const char* name) {
    std::string path = std::string("tb_gls.") + name;
    vpiHandle handle = vpi_handle_by_name(const_cast<char*>(path.c_str()), nullptr);

    if (handle == nullptr) {
        std::fprintf(stderr, "vpi: no signal %s\n", path.c_str());
        std::exit(1);
    }

    return handle;
}

void add_signals() {
#define TB_INPUT(name, width) inputs.push_back({#name, width, &Vtb_chip::name});
#define TB_OUTPUT(name, width) outputs.push_back({#name, width, &Vtb_chip::name});
    TB_INPUTS(TB_INPUT)
    TB_OUTPUTS(TB_OUTPUT)
#undef TB_INPUT
#undef TB_OUTPUT

    for (Signal& signal : inputs) {
        signal.handle = find(signal.name);

        for (const auto& delay : input_delays) {
            if (std::strcmp(delay.name, signal.name) == 0) {
                signal.delay = delay.ps;
            }
        }
    }

    for (Signal& signal : outputs) {
        signal.handle = find(signal.name);

        if (std::strcmp(signal.name, "jtag_tdo_o") == 0) {
            tdo = &signal;
        } else if (std::strcmp(signal.name, "hyper_dq_o") == 0) {
            dq = &signal;
        }
    }

    for (const char* name : watched) {
        watch(find(name));
    }
}

PLI_INT32 on_start(p_cb_data) {
    for (int p = vpi_get(vpiTimePrecision, nullptr); p < -12; ++p) {
        ps_units *= 10;
    }

    add_signals();
    collect_args();
    std::thread(run_harness).detach();

    std::unique_lock<std::mutex> lock(mutex);
    turn.wait(lock, [] { return vvp_turn; });

    if (!start()) {
        serve(lock);
    }

    return 0;
}

void register_start() {
    s_cb_data cb = {};
    cb.reason = cbStartOfSimulation;
    cb.cb_rtn = on_start;
    vpi_register_cb(&cb);
}

}  // namespace

void Vtb_chip::eval() {
    top = this;
    target = context_.time();
    handoff(Request::EVAL);
}

bool Vtb_chip::eventsPending() {
    top = this;
    handoff(Request::RUN);
    return run_end < horizon;
}

uint64_t Vtb_chip::nextTimeSlot() const {
    return run_end;
}

void Vtb_chip::set_horizon(uint64_t time) {
    horizon = time;
}

extern "C" {
void (*vlog_startup_routines[])() = {register_start, nullptr};
}
