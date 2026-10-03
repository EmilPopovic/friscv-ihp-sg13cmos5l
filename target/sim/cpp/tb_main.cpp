// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

#include "elf_loader.hpp"
#include "jtag.hpp"
#include "remote_bitbang.hpp"
#include "soc_testbench.hpp"

#ifndef FRISCV_DUT_CHIP
#include "soc_memory.hpp"
#endif

namespace {

#ifndef FRISCV_SOC_SRAM_BASE
#define FRISCV_SOC_SRAM_BASE 0
#endif

#ifndef FRISCV_SOC_SRAM_SIZE_BYTES
#define FRISCV_SOC_SRAM_SIZE_BYTES 0x2000
#endif

constexpr uint32_t MEM_BASE = 0x80000000;
constexpr uint32_t UART0_BASE = 0x03010000;
constexpr uint32_t SCB_LLCSEL = 0x0300000C;
constexpr uint32_t HYPER_CFG_BASE = 0x50010000;
constexpr uint32_t SCRATCH_ADDRESS = 0x03000000;
constexpr uint32_t PARKED = 1;
constexpr uint32_t PASS_VALUE = 0xaabbccdd;
constexpr uint32_t SRAM_BASE = FRISCV_SOC_SRAM_BASE;
constexpr uint32_t SRAM_SIZE = FRISCV_SOC_SRAM_SIZE_BYTES;
constexpr uint16_t RISCV_MACHINE = 243;
constexpr uint64_t RUN_CYCLES = 2000;
constexpr uint64_t TEST_CYCLES = 10000000;

// STAGE_BYTES and UART_DIV in zsbl.S
constexpr size_t   ZSBL_STAGE_BYTES = 0x1000;
constexpr uint32_t ZSBL_UART_DIV = 27;
// The stage checks its tail bytes
constexpr size_t   STAGE_PATTERN_START = 1024;

// Parse a u32 from text
uint32_t parse_u32(const char* text) {
    char* end = nullptr;
    unsigned long value = std::strtoul(text, &end, 0);

    if (!text[0] || *end || value > std::numeric_limits<uint32_t>::max()) {
        throw std::runtime_error("invalid number");
    }

    return uint32_t(value);
}

// Parse a u8 from text
uint8_t parse_byte(const char* text) {
    char* end = nullptr;
    unsigned long value = std::strtoul(text, &end, 16);

    if (!text[0] || *end || value > std::numeric_limits<uint8_t>::max()) {
        throw std::runtime_error("invalid byte");
    }

    return uint8_t(value);
}

// Parse a u16 port from text
uint16_t parse_port(const char* text) {
    uint32_t port = parse_u32(text);

    if (port == 0 || port > std::numeric_limits<uint16_t>::max()) {
        throw std::runtime_error("invalid port");
    }

    return uint16_t(port);
}

// Check that a memory range does not wrap
void check_range(uint32_t address, size_t size) {
    uint64_t end = uint64_t(address) + size;
    uint64_t limit = uint64_t(std::numeric_limits<uint32_t>::max()) + 1;

    if (end > limit) {
        throw std::runtime_error("memory range wraps around");
    }
}

// Load a u64 from env, default to fallback
uint64_t env_u64(const char* name, uint64_t fallback) {
    const char* text = std::getenv(name);

    if (text == nullptr) {
        return fallback;
    }

    char* end = nullptr;
    unsigned long long value = std::strtoull(text, &end, 0);

    if (!text[0] || *end) {
        throw std::runtime_error(std::string(name) + " is not a number");
    }

    return value;
}

// Load a u32 from env, default to fallback
uint32_t env_u32(const char* name, uint32_t fallback) {
    uint64_t value = env_u64(name, fallback);

    if (value > std::numeric_limits<uint32_t>::max()) {
        throw std::runtime_error(std::string(name) + " does not fit in 32 bits");
    }

    return uint32_t(value);
}

// Turn a u32 into a vector of u8, little-endian
std::vector<uint8_t> word_bytes(uint32_t value) {
    return {
        uint8_t(value),
        uint8_t(value >> 8),
        uint8_t(value >> 16),
        uint8_t(value >> 24),
    };
}

// Read a u32 from memory over JTAG, little-endian
uint32_t read_word(Jtag& jtag, uint32_t address) {
    std::vector<uint8_t> data = jtag.read_memory(address, 4);

    return uint32_t(data[0]) |
           (uint32_t(data[1]) << 8) |
           (uint32_t(data[2]) << 16) |
           (uint32_t(data[3]) << 24);
}

// Reset the SoC and park the core, throw if not parked after a while
void park(SocTestbench& testbench, Jtag& jtag) {
    jtag.reset_soc();

    for (unsigned i = 0; i < 1000; ++i) {
        if (read_word(jtag, SCRATCH_ADDRESS) == PARKED) {
            return;
        }

        testbench.run_cycles(8);
    }

    throw std::runtime_error("boot ROM did not park");
}

// Start the program at the given entry address on a running-but-parked SoC
void start_image(Jtag& jtag, uint32_t entry) {
    jtag.write_memory(SCRATCH_ADDRESS, word_bytes(entry));
}

// External here means outside the SRAM
bool is_external(uint32_t address) {
    return address < SRAM_BASE || address >= uint64_t(SRAM_BASE) + SRAM_SIZE;
}

void validate(const ElfImage& image) {
    // Check the ELF was built for RISC-V
    if (image.machine != RISCV_MACHINE) {
        throw std::runtime_error("ELF is not for RISC-V");
    }

    // Check whether to load into SRAM or HyperRAM
    bool entry_ok = false;
    bool external = is_external(image.entry);

    for (const ElfSegment& segment : image.segments) {
        uint64_t start = segment.address;
        uint64_t end = uint64_t(segment.address) + segment.data.size();

        if (external) {
            // This model does not allow mixing SRAM and HyperRAM segments in one ELF
            if (start < MEM_BASE) {
                throw std::runtime_error("ELF mixes external and SRAM segments");
            }
        } else if (start < SRAM_BASE || end > uint64_t(SRAM_BASE) + SRAM_SIZE) {
            // If loading into SRAM, segment must fit in SRAM
            throw std::runtime_error("ELF segment is outside SRAM");
        }

        // Entry must be in an executable segment
        if (segment.executable && image.entry >= segment.address && image.entry < end) {
            entry_ok = true;
        }
    }

    if ((image.entry & 3) != 0 || image.entry == PARKED || !entry_ok) {
        throw std::runtime_error("invalid ELF entry point");
    }
}

// Read a file at path into a vector of u8
std::vector<uint8_t> read_file(const char* path) {
    std::FILE* file = std::fopen(path, "rb");

    if (file == nullptr) {
        throw std::runtime_error(std::string("cannot open ") + path);
    }

    std::vector<uint8_t> data;
    uint8_t chunk[4096];
    size_t read = 0;

    while ((read = std::fread(chunk, 1, sizeof(chunk), file)) > 0) {
        data.insert(data.end(), chunk, chunk + read);
    }

    std::fclose(file);
    return data;
}

// Load a flash image (file at path) into the flash model
void preload_flash(SocTestbench& testbench, const char* path) {
    std::vector<uint8_t> data = read_file(path);

    testbench.flash().preload(0, data);
    std::fprintf(stderr, "flash image %s: %zu bytes\n", path, data.size());
}

// Load an SD image (file at path) into the SD model
void preload_sd(SocTestbench& testbench, const char* path) {
    std::vector<uint8_t> data = read_file(path);

    testbench.sd().preload(0, data);
    std::fprintf(stderr, "sd image %s: %zu bytes\n", path, data.size());
}

// Apply the HyperBus config from env over JTAG
void apply_hyperbus_config(Jtag& jtag) {
    const char* spec = std::getenv("VERNII_HB_CFG");

    if (spec == nullptr) {
        return;
    }

    while (*spec != '\0') {
        char* end = nullptr;
        // Read key
        unsigned long index = std::strtoul(spec, &end, 0);

        // Fail if no key or ends with a colon
        if (end == spec || *end != ':') {
            throw std::runtime_error("VERNII_HB_CFG needs reg:value pairs");
        }

        // Go to next
        spec = end + 1;
        unsigned long value =
        // Read value
        std::strtoul(spec, &end, 0);

        // Fail if no value
        if (end == spec) {
            throw std::runtime_error("VERNII_HB_CFG needs reg:value pairs");
        }

        // Write value to address key over JTAG
        jtag.write_memory(HYPER_CFG_BASE + uint32_t(index) * 4, word_bytes(uint32_t(value)));
        std::fprintf(stderr, "hyperbus cfg[%lu] = %lu\n", index, value);

        spec = (*end == ',') ? end + 1 : end;
    }
}

// Write SCB.LLCSEL over JTAG if VERNII_LLCSEL is set
void apply_cache_config(Jtag& jtag) {
    if (std::getenv("VERNII_LLCSEL") == nullptr) {
        return;
    }

    jtag.write_memory(SCB_LLCSEL, word_bytes(env_u32("VERNII_LLCSEL", 0)));
}

// Load UART config at 8N1 and the divisor from env over JTAG
void apply_uart_config(SocTestbench& testbench, Jtag& jtag) {
    if (std::getenv("VERNII_UART_DIV") == nullptr) {
        return;
    }

    uint32_t divisor = env_u32("VERNII_UART_DIV", 0);

    jtag.write_memory(UART0_BASE + 0x0c, word_bytes(0x80));
    jtag.write_memory(UART0_BASE + 0x00, word_bytes(divisor & 0xFF));
    jtag.write_memory(UART0_BASE + 0x04, word_bytes(divisor >> 8));
    jtag.write_memory(UART0_BASE + 0x0c, word_bytes(0x03));

    testbench.uart().set_divisor(divisor);
}

// Load flash and SD images if VERNII_FLASH or VERNII_SD_IMAGE are set
void apply_media(SocTestbench& testbench) {
    // Load flash image at VERNII_FLASH into the flash model
    if (const char* path = std::getenv("VERNII_FLASH")) {
        preload_flash(testbench, path);
    }

    // Load SD image at VERNII_SD_IMAGE into the SD model
    if (const char* path = std::getenv("VERNII_SD_IMAGE")) {
        preload_sd(testbench, path);
    }
}

// Park core and apply all configs and media over JTAG
ElfImage prepare_image(SocTestbench& testbench, Jtag& jtag, const char* path) {
    ElfImage image = read_elf(path);

    validate(image);
    park(testbench, jtag);
    apply_hyperbus_config(jtag);
    apply_cache_config(jtag);
    apply_uart_config(testbench, jtag);
    apply_media(testbench);

    return image;
}

// Boot the SoC with the given boot select
void boot(SocTestbench& testbench, Jtag& jtag, unsigned boot_sel) {
    dut::set_boot_sel(testbench.top(), boot_sel);
    testbench.reset();
    jtag.initialize();  // The DM was reset too
}

// Run until the DUT asserts end or cycle limit is reached
int run_to_end(SocTestbench& testbench, Jtag& jtag) {
    Dut& top = testbench.top();
    uint64_t limit = env_u64("VERNII_TEST_CYCLES", TEST_CYCLES);

    // Run the testbench
    for (uint64_t cycle = 0; cycle < limit && !top.end_o; ++cycle) {
        testbench.run_cycles(1);
    }

    // Go to next line if the UART is mid-line
    if (!testbench.uart().at_line_start()) {
        std::fputc('\n', stderr);
    }

    // Read the result from the DUT, or SCB.SCRATCH0 if the DUT did not assert end
    bool ended = top.end_o;
    uint32_t result = dut::HAS_RESULT && ended ? dut::result(top)
                                               : read_word(jtag, SCRATCH_ADDRESS);
    uint32_t contention = testbench.contention();
    unsigned long long cycles = testbench.cycles();

    // Print pass if the DUT ended, the result is PASS_VALUE, and there was no pad contention
    if (ended && result == PASS_VALUE && contention == 0) {
        std::fprintf(stderr, "PASS (%llu cycles, %.0f Hz)\n", cycles, testbench.rate());
        return 0;
    }

    std::string why = ended ? "" : ", no end";

    if (contention != 0) {
        char text[32];
        std::snprintf(text, sizeof(text), ", contention 0x%08x", contention);
        why += text;
    }

    // Print fail and the why string
    std::fprintf(stderr, "FAIL (scratch=0x%08x, %llu cycles, %.0f Hz%s)\n", result, cycles,
                 testbench.rate(), why.c_str());
    return 1;
}

// Load an ELF into the SoC over JTAG and run for a while
int cmd_load(SocTestbench& testbench, Jtag& jtag, int, char** argv) {
    ElfImage image = prepare_image(testbench, jtag, argv[2]);

    for (const ElfSegment& segment : image.segments) {
        jtag.write_memory(segment.address, segment.data);
    }

    start_image(jtag, image.entry);
    testbench.run_cycles(RUN_CYCLES);
    return 0;
}

// External images go into HyperRAM, SRAM images over JTAG, then run to end and return the result
int cmd_test(SocTestbench& testbench, Jtag& jtag, int, char** argv) {
    ElfImage image = prepare_image(testbench, jtag, argv[2]);

    if (is_external(image.entry)) {
        for (const ElfSegment& segment : image.segments) {
            testbench.preload_ext(segment.address - MEM_BASE, segment.data);
        }
    } else {
#ifdef FRISCV_DUT_CHIP
        // Cannot preload into SRAM on the chip, load over JTAG instead
        for (const ElfSegment& segment : image.segments) {
            jtag.write_memory(segment.address, segment.data);
        }
#else
        preload_sram(testbench.top(), image, SRAM_BASE);
#endif
    }

    start_image(jtag, image.entry);
    return run_to_end(testbench, jtag);
}

// Stage from flash, then run to end and return the result (boot select 1)
int cmd_qspiboot(SocTestbench& testbench, Jtag& jtag, int, char** argv) {
    preload_flash(testbench, argv[2]);

    // Also preload SD if this run needs it (e.g. boot OS from SD with FSBL in flash)
    if (const char* path = std::getenv("VERNII_SD_IMAGE")) {
        preload_sd(testbench, path);
    }

    testbench.uart().set_divisor(env_u32("VERNII_UART_DIV", 0));

    boot(testbench, jtag, 1);
    return run_to_end(testbench, jtag);
}

// Stage from UART, then run to end and return the result (boot select 2)
int cmd_uartboot(SocTestbench& testbench, Jtag& jtag, int, char** argv) {
    std::vector<uint8_t> stage = read_file(argv[2]);

    // The ROM loads a fixed number of bytes
    if (stage.size() > ZSBL_STAGE_BYTES) {
        std::fprintf(stderr, "stage %s is %zu bytes, the rom takes %zu\n",
                     argv[2], stage.size(), ZSBL_STAGE_BYTES);
        return 1;
    }

    // If smaller, pad with zeroes to the size the ROM expects
    stage.resize(ZSBL_STAGE_BYTES, 0);

    // Fill the tail bytes with a pattern to check
    for (size_t i = STAGE_PATTERN_START; i < ZSBL_STAGE_BYTES; ++i) {
        stage[i] = uint8_t(i * 7 + 0x5a);
    }

    uint32_t divisor = env_u32("VERNII_UART_DIV", ZSBL_UART_DIV);

    // Set testbench to the used baud
    testbench.uart().set_divisor(divisor);
    testbench.uart_rx().set_divisor(divisor);

    testbench.uart_rx().set_bit_cycles(env_u32("VERNII_UART_BIT_CYCLES", 16 * divisor));

    // Then boot using UART mode
    boot(testbench, jtag, env_u32("VERNII_BOOT_SEL", 2));

    // And send the bytes
    testbench.uart_rx().send(stage);
    std::fprintf(stderr, "uart stage %s: %zu bytes\n", argv[2], stage.size());

    // Run to result or timeout
    return run_to_end(testbench, jtag);
}

// Print a memory range in hex, 16 bytes per line
void print_memory(uint32_t address, const std::vector<uint8_t>& data) {
    for (size_t offset = 0; offset < data.size(); ++offset) {
        if ((offset & 15) == 0) {
            std::printf("%08x:", address + uint32_t(offset));
        }

        std::printf(" %02x", data[offset]);

        if ((offset & 15) == 15 || offset + 1 == data.size()) {
            std::printf("\n");
        }
    }
}

// Park the core, read a memory range over JTAG, and print it in hex
int cmd_read(SocTestbench& testbench, Jtag& jtag, int, char** argv) {
    uint32_t address = parse_u32(argv[2]);
    uint32_t size = parse_u32(argv[3]);

    check_range(address, size);
    park(testbench, jtag);
    print_memory(address, jtag.read_memory(address, size));
    return 0;
}

// Park the core and write a memory range over JTAG
int cmd_write(SocTestbench& testbench, Jtag& jtag, int argc, char** argv) {
    uint32_t address = parse_u32(argv[2]);
    std::vector<uint8_t> data;

    data.reserve(size_t(argc - 3));

    for (int i = 3; i < argc; ++i) {
        data.push_back(parse_byte(argv[i]));
    }

    check_range(address, data.size());
    park(testbench, jtag);
    jtag.write_memory(address, data);

    std::printf("wrote %zu bytes at %08x\n", data.size(), address);
    return 0;
}

// Start a remote bitbang server on the given port
int cmd_server(SocTestbench& testbench, Jtag&, int argc, char** argv) {
    uint16_t port = argc == 3 ? parse_port(argv[2]) : RemoteBitbang::DEFAULT_PORT;

    RemoteBitbang(testbench).serve(port);
    return 0;
}


struct Command {
    const char* name;
    int         argc;   // negative means a minimum of -argc
    bool        jtag;
    int       (*run)(SocTestbench&, Jtag&, int, char**);
    const char* usage;
};

constexpr Command COMMANDS[] = {
    { "load",     3,  true,  cmd_load,     "load <program.elf>"                },
    { "test",     3,  true,  cmd_test,     "test <program.elf>"                },
    { "qspiboot", 3,  true,  cmd_qspiboot, "qspiboot <image.bin>"              },
    { "uartboot", 3,  true,  cmd_uartboot, "uartboot <stage.bin>"              },
    { "read",     4,  true,  cmd_read,     "read <address> <size>"             },
    { "write",   -4,  true,  cmd_write,    "write <address> <byte> [byte ...]" },
    { "server",  -2,  false, cmd_server,   "server [port]"                     },
};

const Command* find_command(int argc, char** argv) {
    if (argc < 2) {
        return nullptr;
    }

    for (const Command& command : COMMANDS) {
        if (std::strcmp(argv[1], command.name) != 0) {
            continue;
        }

        bool ok = command.argc < 0 ? argc >= -command.argc
                                   : argc == command.argc;
        return ok ? &command : nullptr;
    }

    return nullptr;
}

void print_usage(const char* program) {
    std::fprintf(stderr, "usage:\n");

    for (const Command& command : COMMANDS) {
        std::fprintf(stderr, "  %s %s\n", program, command.usage);
    }
}

// Verilator's plusargs come after the command's own arguments
int command_argc(int argc, char** argv) {
    int count = argc;

    while (count > 1 && argv[count - 1][0] == '+') {
        --count;
    }

    return count;
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    argc = command_argc(argc, argv);

    const Command* command = find_command(argc, argv);

    if (command == nullptr) {
        print_usage(argv[0]);
        return 1;
    }

    try {
        SocTestbench testbench;
        Jtag jtag(testbench);

        testbench.set_float_seed(env_u32("VERNII_FLOAT_SEED", 1));
        testbench.sd().set_miso_delay(env_u32("VERNII_SD_MISO_DELAY", 0));

        testbench.reset();

        if (command->jtag) {
            jtag.initialize();
        }

        return command->run(testbench, jtag, argc, argv);
    } catch (const std::exception& error) {
        std::fprintf(stderr, "simulation failed: %s\n", error.what());
        return 1;
    }
}
