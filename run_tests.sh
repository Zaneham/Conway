#!/bin/bash
cd /c/dev/conway
pass=0
fail=0

for elf in arch-test/bin/*.elf; do
  name=$(basename "$elf" .elf)
  # Run test - cmd expects backslash paths
  if cmd //c "test\compliance\conway_test.exe $elf" >/dev/null 2>&1; then
    ((pass++))
  else
    ((fail++))
    echo "FAIL: $name"
  fi
done

echo "---"
echo "Passed: $pass / $((pass+fail))"
