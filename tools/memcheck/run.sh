#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

OUT=build/memcheck
ITERATIONS=${ITERATIONS:-20000}
VALGRIND_ITERATIONS=${VALGRIND_ITERATIONS:-1500}
SEED=${SEED:-1}
THREADS=${THREADS:-8}

rm -rf "$OUT/shapes"
mkdir -p "$OUT/shapes"
while IFS= read -r gui; do
    dump="$OUT/shapes/$(echo "$gui" | tr / _).txt"
    python3 tools/geometry/extract_shapes.py "$gui" "$dump"
    [ "$(wc -l < "$dump")" -gt 1 ] || rm "$dump"
done < <(find tests -name '*.gui' | sort)
DUMPS=("$OUT"/shapes/*.txt)

SOURCES=(tools/memcheck/memcheck.cpp defigma/commonsrc/shape_geometry.cpp defigma/pluginsrc/plugin.cpp)
FLAGS=(-std=c++17 -g -O1 -pthread -Idefigma/include -Itools/memcheck/stub)

g++ "${FLAGS[@]}" -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer "${SOURCES[@]}" -o "$OUT/memcheck_asan"
g++ "${FLAGS[@]}" -fsanitize=thread "${SOURCES[@]}" -o "$OUT/memcheck_tsan"
g++ "${FLAGS[@]}" "${SOURCES[@]}" -o "$OUT/memcheck"

echo "== address + undefined sanitizers"
"$OUT/memcheck_asan" real "${DUMPS[@]}" | tail -n 1
"$OUT/memcheck_asan" fuzz "$ITERATIONS" "$SEED" "${DUMPS[@]}"
"$OUT/memcheck_asan" threads "$THREADS" 10 "${DUMPS[@]}"

echo "== thread sanitizer"
setarch "$(uname -m)" -R "$OUT/memcheck_tsan" threads "$THREADS" 3 "${DUMPS[@]}"

echo "== valgrind"
VALGRIND=(valgrind --leak-check=full --show-leak-kinds=definite,indirect,possible --errors-for-leak-kinds=definite,indirect,possible --error-exitcode=1)
"${VALGRIND[@]}" "$OUT/memcheck" real "${DUMPS[@]}" | tail -n 1
"${VALGRIND[@]}" "$OUT/memcheck" fuzz "$VALGRIND_ITERATIONS" "$SEED" "${DUMPS[@]}"
"${VALGRIND[@]}" "$OUT/memcheck" threads 4 1 "${DUMPS[@]}"

echo "memcheck: all passed"
