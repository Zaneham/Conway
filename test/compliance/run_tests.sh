#!/bin/bash
# Run Conway compliance tests
# Temporarily replaces fib.elf with each test

cd /c/dev/conway

# Backup original fib.elf
cp test/riscv/fib.elf test/riscv/fib.elf.backup

echo "=== Conway Compliance Tests ==="
echo ""

PASS=0
FAIL=0

for test in add_test arith_test shift_test imm_test branch_test memory_test mext_test cext_test; do
    # Copy test to fib.elf location
    cp test/compliance/bin/${test}.elf test/riscv/fib.elf

    # Run test
    ./test/test_real_elf_run.exe > /dev/null 2>&1
    code=$?

    printf "%-15s: " "$test"
    if [ $code -eq 0 ]; then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL (exit code: $code)"
        ((FAIL++))
    fi
done

# Restore original
mv test/riscv/fib.elf.backup test/riscv/fib.elf

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"
