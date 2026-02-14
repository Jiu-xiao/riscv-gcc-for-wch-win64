set -euxo pipefail

mkdir -p /opt/wine-wrappers
cat > /opt/wine-wrappers/riscv32-unknown-elf-wrapper <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Skip GCC selftests that use /dev/null; they fail under Wine with Windows paths.
for arg in "$@"; do
  case "$arg" in
    -fself-test=*) exit 0 ;;
  esac
done

WINE_BIN=${WINE_BIN:-/usr/lib/wine/wine64}
if [ ! -x "$WINE_BIN" ]; then
  if command -v wine64 >/dev/null 2>&1; then
    WINE_BIN=$(command -v wine64)
  elif command -v wine >/dev/null 2>&1; then
    WINE_BIN=$(command -v wine)
  else
    echo "wrapper: wine binary not found at $WINE_BIN" >&2
    exit 127
  fi
fi

to_win_path() {
  local p="$1"
  echo "Z:${p//\//\\}"
}

tool=$(basename "$0")
prefix=/opt/riscv
build_root=/src
gcc_dirs=(
  "$build_root/build-gcc-newlib-stage1/gcc"
  "$build_root/build-gcc-newlib/gcc"
  "$build_root/build-gcc-newlib-stage2/gcc"
)
binutils_root="$build_root/build-binutils-newlib"

run_gcc_tool() {
  local exe="$1"
  shift
  local dir win_dir win_gas win_ld
  for dir in "${gcc_dirs[@]}"; do
    if [ -f "${dir}/${exe}" ]; then
      win_dir=$(to_win_path "$dir")
      win_gas=$(to_win_path "$binutils_root/gas")
      win_ld=$(to_win_path "$binutils_root/ld")
      local tmp_root win_tmp
      tmp_root=${WINE_TMP_ROOT:-/tmp/wine-tmp}
      mkdir -p "$tmp_root"
      win_tmp=$(to_win_path "$tmp_root")
      export TMP="$win_tmp"
      export TEMP="$win_tmp"
      export TMPDIR="$tmp_root"
      export GCC_EXEC_PREFIX="${win_dir}\\"
      # Prefer binutils build dirs for as/ld/nm so xgcc doesn't pick broken stage1 helpers.
      export COMPILER_PATH="${win_gas};${win_ld};${win_dir}"
      export PATH="${binutils_root}/gas:${binutils_root}/ld:${dir}:${PATH}"
      exec "$WINE_BIN" "${dir}/${exe}" "$@"
    fi
  done
  return 1
}

run_binutils_tool() {
  local -a candidates=("$@")
  local exe
  unset GCC_EXEC_PREFIX COMPILER_PATH
  for exe in "${candidates[@]}"; do
    if [ -f "$exe" ]; then
      local tmp_root win_tmp
      tmp_root=${WINE_TMP_ROOT:-/tmp/wine-tmp}
      mkdir -p "$tmp_root"
      win_tmp=$(to_win_path "$tmp_root")
      export TMP="$win_tmp"
      export TEMP="$win_tmp"
      export TMPDIR="$tmp_root"
      exec "$WINE_BIN" "$exe" "${tool_args[@]}"
    fi
  done
  return 1
}

tool_args=()
for arg in "$@"; do
  tool_args+=("${arg//$'\r'/}")
done
case "$tool" in
  riscv32-unknown-elf-gcc) run_gcc_tool xgcc.exe "${tool_args[@]}" ;;
  riscv32-unknown-elf-g++) run_gcc_tool xg++.exe "${tool_args[@]}" ;;
  riscv32-unknown-elf-cpp) run_gcc_tool cpp.exe "${tool_args[@]}" ;;
  riscv32-unknown-elf-gcc-ar) run_gcc_tool gcc-ar.exe "${tool_args[@]}" ;;
  riscv32-unknown-elf-gcc-nm) run_gcc_tool gcc-nm.exe "${tool_args[@]}" ;;
  riscv32-unknown-elf-gcc-ranlib) run_gcc_tool gcc-ranlib.exe "${tool_args[@]}" ;;
  riscv32-unknown-elf-as)
    run_binutils_tool \
      "$binutils_root/gas/as-new.exe" \
      "$binutils_root/gas/.libs/as-new.exe" \
      "$prefix/bin/riscv32-unknown-elf-as.exe"
    ;;
  riscv32-unknown-elf-ld)
    run_binutils_tool \
      "$binutils_root/ld/ld-new.exe" \
      "$binutils_root/ld/.libs/ld-new.exe" \
      "$prefix/bin/riscv32-unknown-elf-ld.exe"
    ;;
  riscv32-unknown-elf-ar)
    run_binutils_tool \
      "$binutils_root/binutils/ar.exe" \
      "$prefix/bin/riscv32-unknown-elf-ar.exe"
    ;;
  riscv32-unknown-elf-ranlib)
    run_binutils_tool \
      "$binutils_root/binutils/ranlib.exe" \
      "$prefix/bin/riscv32-unknown-elf-ranlib.exe"
    ;;
  riscv32-unknown-elf-nm)
    run_binutils_tool \
      "$binutils_root/binutils/nm-new.exe" \
      "$binutils_root/binutils/nm.exe" \
      "$prefix/bin/riscv32-unknown-elf-nm.exe"
    ;;
  riscv32-unknown-elf-objcopy)
    run_binutils_tool \
      "$binutils_root/binutils/objcopy.exe" \
      "$prefix/bin/riscv32-unknown-elf-objcopy.exe"
    ;;
  riscv32-unknown-elf-objdump)
    run_binutils_tool \
      "$binutils_root/binutils/objdump.exe" \
      "$prefix/bin/riscv32-unknown-elf-objdump.exe"
    ;;
  riscv32-unknown-elf-strip)
    run_binutils_tool \
      "$binutils_root/binutils/strip-new.exe" \
      "$binutils_root/binutils/strip.exe" \
      "$prefix/bin/riscv32-unknown-elf-strip.exe"
    ;;
  riscv32-unknown-elf-size)
    run_binutils_tool \
      "$binutils_root/binutils/size.exe" \
      "$prefix/bin/riscv32-unknown-elf-size.exe"
    ;;
  riscv32-unknown-elf-readelf)
    run_binutils_tool \
      "$binutils_root/binutils/readelf.exe" \
      "$prefix/bin/riscv32-unknown-elf-readelf.exe"
    ;;
  *)
    unset GCC_EXEC_PREFIX COMPILER_PATH
    if [ -f "${prefix}/bin/${tool}.exe" ]; then
      exec "$WINE_BIN" "${prefix}/bin/${tool}.exe" "${tool_args[@]}"
    fi
    ;;
esac

if [ -x "${prefix}/bin/${tool}" ]; then
  exec "${prefix}/bin/${tool}" "${tool_args[@]}"
fi

echo "wrapper: missing tool for ${tool}" >&2
exit 127
EOF
chmod +x /opt/wine-wrappers/riscv32-unknown-elf-wrapper

for t in gcc g++ cpp gcc-ar gcc-nm gcc-ranlib ar ranlib nm as ld strip objcopy objdump size readelf; do
  ln -sf /opt/wine-wrappers/riscv32-unknown-elf-wrapper "/opt/wine-wrappers/riscv32-unknown-elf-${t}"
done

export PATH=/opt/wine-wrappers:$PATH
export WINE_BIN=/usr/lib/wine/wine64
