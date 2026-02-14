set -euxo pipefail

# Reuse the wrapper setup from debug-repro.
bash /work/debug-repro.sh || true

cat >/tmp/conftest.c <<'EOF'
int main(void) { return 0; }
EOF

set +e
riscv32-unknown-elf-gcc -v -S /tmp/conftest.c -o /tmp/conftest.s
rc_s=$?
echo "gcc_S_rc=$rc_s"
ls -la /tmp/conftest.s || true

/usr/lib/wine/wine64 /src/build-gcc-newlib-stage1/gcc/as.exe -v -o /tmp/conftest-from-as.o /tmp/conftest.s
rc_as=$?
echo "as_direct_rc=$rc_as"
ls -la /tmp/conftest-from-as.o || true

if [ "$rc_s" -ne 0 ] || [ "$rc_as" -ne 0 ]; then
  exit 1
fi
