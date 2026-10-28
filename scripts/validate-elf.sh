#!/usr/bin/env bash
# Author: nullij @ https://github.com/nullij
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: validate-elf.sh BINARY TARGET [--bundle-root DIRECTORY] [--allowed-needed LIBRARY]...
EOF
}

die() {
  echo "ELF validation error: $*" >&2
  exit 1
}

(($# >= 2)) || { usage; exit 2; }
BINARY="$1"
TARGET="$2"
shift 2

BUNDLE_ROOT=""
ALLOWED_NEEDED=()
while (($#)); do
  case "$1" in
    --bundle-root)
      (($# >= 2)) || { usage; exit 2; }
      BUNDLE_ROOT="$2"
      shift 2
      ;;
    --allowed-needed)
      (($# >= 2)) || { usage; exit 2; }
      ALLOWED_NEEDED+=("$2")
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ -f "$BINARY" ]] || die "file does not exist: $BINARY"
[[ -x "$BINARY" ]] || die "file is not executable: $BINARY"
[[ -z "$BUNDLE_ROOT" || -d "$BUNDLE_ROOT" ]] || die "bundle root does not exist: $BUNDLE_ROOT"
command -v file >/dev/null || die "file is required"
command -v readelf >/dev/null || die "readelf is required"

EXPECTED_ARCH=""
EXPECTED_INTERPRETER=""
case "$TARGET" in
  aarch64-linux-android)
    EXPECTED_ARCH="aarch64"
    EXPECTED_INTERPRETER="/system/bin/linker64"
    ;;
  armv7-linux-androideabi)
    EXPECTED_ARCH="arm"
    EXPECTED_INTERPRETER="/system/bin/linker"
    ;;
  x86_64-linux-android)
    EXPECTED_ARCH="x86-64"
    EXPECTED_INTERPRETER="/system/bin/linker64"
    ;;
  *) die "unsupported Android target: $TARGET" ;;
esac

FILE_OUTPUT="$(file -b "$BINARY")"
HEADER_OUTPUT="$(readelf -h "$BINARY")"
PROGRAM_OUTPUT="$(readelf -lW "$BINARY")"
DYNAMIC_OUTPUT="$(readelf -dW "$BINARY" 2>/dev/null || true)"

grep -Eiq '^ELF ' <<<"$FILE_OUTPUT" || die "file(1) did not identify an ELF: $FILE_OUTPUT"
grep -Eiq 'dynamically linked' <<<"$FILE_OUTPUT" || die "ELF is not dynamically linked: $FILE_OUTPUT"
grep -Eiq 'pie executable' <<<"$FILE_OUTPUT" || die "ELF is not reported as a PIE executable: $FILE_OUTPUT"
grep -Fqi "$EXPECTED_ARCH" <<<"$FILE_OUTPUT" || die "wrong architecture; expected $EXPECTED_ARCH: $FILE_OUTPUT"
grep -Eq 'Type:.*DYN' <(sed -n '/Type:/p' <<<"$HEADER_OUTPUT") || die "ELF type is not DYN (PIE)"
grep -Fq "Requesting program interpreter: $EXPECTED_INTERPRETER" <<<"$PROGRAM_OUTPUT" || \
  die "wrong Android ELF interpreter; expected $EXPECTED_INTERPRETER"

[[ -n "$DYNAMIC_OUTPUT" ]] || die "ELF has no dynamic section"
if grep -Eiq 'ld-linux|libc\.so\.[0-9]|libpthread\.so\.[0-9]|libm\.so\.[0-9]|libdl\.so\.[0-9]|termux|/data/data' <<<"$PROGRAM_OUTPUT$DYNAMIC_OUTPUT"; then
  die "ELF contains a GNU/Linux or Termux runtime reference"
fi

mapfile -t NEEDED_LIBRARIES < <(
  sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' <<<"$DYNAMIC_OUTPUT"
)
for library in "${NEEDED_LIBRARIES[@]}"; do
  allowed=false
  for candidate in "${ALLOWED_NEEDED[@]}"; do
    if [[ "$library" == "$candidate" ]]; then
      allowed=true
      break
    fi
  done
  if [[ "$allowed" == false && -n "$BUNDLE_ROOT" && -f "$BUNDLE_ROOT/lib/$library" ]]; then
    allowed=true
    grep -Fq '$ORIGIN/../lib' <<<"$DYNAMIC_OUTPUT" || \
      die "binary needs bundled $library but has no \$ORIGIN/../lib runtime path"
  fi
  [[ "$allowed" == true ]] || die "$BINARY: unapproved DT_NEEDED library: $library"
done

echo "file: $FILE_OUTPUT"
echo "target: $TARGET"
echo "interpreter: $EXPECTED_INTERPRETER"
if ((${#NEEDED_LIBRARIES[@]})); then
  printf 'needed: %s\n' "${NEEDED_LIBRARIES[*]}"
else
  echo "needed: (none)"
fi
echo "ELF validation: OK"
