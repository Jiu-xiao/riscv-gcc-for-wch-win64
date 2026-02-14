set -euxo pipefail

show_context() {
  local f="$1"
  echo "==== $f"
  if [ ! -f "$f" ]; then
    echo "missing"
    return 0
  fi
  local ln
  ln=$(grep -n "cannot compute suffix of object files" "$f" | head -n1 | cut -d: -f1 || true)
  if [ -z "${ln:-}" ]; then
    echo "marker not found; showing tail"
    tail -n 140 "$f"
    return 0
  fi
  local start end
  start=$((ln - 80))
  end=$((ln + 40))
  if [ "$start" -lt 1 ]; then
    start=1
  fi
  sed -n "${start},${end}p" "$f"
}

show_context /src/build-newlib/riscv32-unknown-elf/rv32imac_zaamo_zalrsc/ilp32/newlib/config.log
show_context /src/build-newlib/riscv32-unknown-elf/rv32imac_zaamo_zalrsc/ilp32/libgloss/config.log
show_context /src/build-newlib-nano/riscv32-unknown-elf/rv32imac_zaamo_zalrsc/ilp32/newlib/config.log
show_context /src/build-newlib-nano/riscv32-unknown-elf/rv32imac_zaamo_zalrsc/ilp32/libgloss/config.log
