#!/usr/bin/env bash
# LGPL source offer for one build (lean-iptv, docs/licences.md section 4.4):
# writes sources.txt, the exact revision of every component in src_packages,
# and source.tar.xz, every component exactly as built (patches applied) plus
# this repository. Toolchain trees are left out except the LLVM runtimes
# (libc++, libc++abi, libunwind, compiler-rt) that the DLL links statically.
# Usage: scripts/lgpl-sources.sh <src_packages> <out_dir>
set -euo pipefail
src=$(cd "$1" && pwd)
out=$(mkdir -p "$2" && cd "$2" && pwd)
repo=$(cd "$(dirname "$0")/.." && pwd)

{
  echo "build-repo $(git -C "$repo" remote get-url origin) $(git -C "$repo" rev-parse HEAD)"
  for d in "$src"/*/; do
    name=$(basename "$d")
    # An empty folder is a component this build never fetched, so not in the DLL.
    [ -n "$(ls -A "$d")" ] || continue
    if [ -e "$d/.git" ]; then
      echo "$name $(git -C "$d" remote get-url origin) $(git -C "$d" rev-parse HEAD)"
    else
      f="$repo/packages/$name.cmake"
      [ -f "$f" ] || f="$repo/toolchain/$name.cmake"
      url=$(grep -m1 -oE 'URL[[:space:]]+[^[:space:]]+' "$f" 2>/dev/null | awk '{print $2}' || true)
      hash=$(grep -m1 -oE 'URL_HASH[[:space:]]+[^[:space:]]+' "$f" 2>/dev/null | awk '{print $2}' || true)
      echo "$name ${url:-unknown} ${hash:-no-hash}"
    fi
  done
} > "$out/sources.txt"
# The DLL links libc++ and the mingw-w64 runtime statically: no release
# without their source.
for need in llvm mingw-w64; do
  grep -q "^$need " "$out/sources.txt" || { echo "lgpl-sources: $need source missing" >&2; exit 1; }
done

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/components" "$stage/build-repo"
git -C "$repo" archive HEAD | tar -C "$stage/build-repo" -xf -
for d in "$src"/*/; do
  name=$(basename "$d")
  [ -n "$(ls -A "$d")" ] || continue
  case "$name" in
    gcc|rustup) continue ;;
    llvm)
      for r in libcxx libcxxabi libunwind compiler-rt LICENSE.TXT; do
        [ -e "$d/$r" ] && tar -C "$src" --exclude=.git -cf - "llvm/$r" | tar -C "$stage/components" -xf -
      done
      ;;
    *) tar -C "$src" --exclude=.git -cf - "$name" | tar -C "$stage/components" -xf - ;;
  esac
done
cp "$out/sources.txt" "$stage/"
tar -C "$stage" -cJf "$out/source.tar.xz" .
