#!/bin/bash
# Build RISC-V compliance tests for Conway
# Uses Docker with dockcross/linux-riscv64 toolchain

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH_TEST_DIR="/c/dev/riscv-arch-test"
OUTPUT_DIR="$SCRIPT_DIR/bin"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Test suites to build (I = base, M = multiply, C = compressed)
SUITES="I M C"

# Compiler flags for Conway compatibility
# - static: no dynamic linking
# - nostdlib: no standard library
# - march=rv64imc: base + M + C extensions
# - mabi=lp64: 64-bit ABI without floating point
CFLAGS="-static -nostdlib -march=rv64imc -mabi=lp64"
LDFLAGS="-Ttext=0x1000 --build-id=none"

# Include paths
INCLUDES="-I$SCRIPT_DIR/env -I$ARCH_TEST_DIR/riscv-test-suite/env"

# Define TEST_CASE_1 to enable the test code
DEFINES="-DTEST_CASE_1"

build_test() {
    local suite=$1
    local test_file=$2
    local test_name=$(basename "$test_file" .S)
    local output="$OUTPUT_DIR/${suite}_${test_name}.elf"

    echo "Building: $suite/$test_name"

    docker run --rm \
        -v "$(cygpath -w "$SCRIPT_DIR"):/conway" \
        -v "$(cygpath -w "$ARCH_TEST_DIR"):/arch-test" \
        dockcross/linux-riscv64 bash -c \
        "riscv64-unknown-linux-gnu-gcc $CFLAGS $DEFINES \
            -I/conway/env -I/arch-test/riscv-test-suite/env \
            -Wl,$LDFLAGS \
            -o /conway/bin/${suite}_${test_name}.elf \
            /arch-test/riscv-test-suite/rv64i_m/$suite/src/$test_name.S" \
        2>&1 || echo "FAILED: $suite/$test_name"
}

# Build tests for each suite
for suite in $SUITES; do
    echo "=== Building $suite extension tests ==="
    test_dir="$ARCH_TEST_DIR/riscv-test-suite/rv64i_m/$suite/src"

    if [ -d "$test_dir" ]; then
        for test_file in "$test_dir"/*.S; do
            if [ -f "$test_file" ]; then
                build_test "$suite" "$test_file"
            fi
        done
    else
        echo "Warning: Test directory not found: $test_dir"
    fi
done

echo ""
echo "=== Build complete ==="
echo "Tests built in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/*.elf 2>/dev/null | wc -l
echo "ELF files created"
