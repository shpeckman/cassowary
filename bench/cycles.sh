#!/bin/sh
# bench/cycles.sh
#
# Prints the user-space CPU cycles (millions, best of RUNS) of each scenario in
# bench/cycles.cr, minus the setup-only "none" run. Needs `perf` and runs pinned to
# CPU (default 2). Usage: bench/cycles.sh [scenario...]
set -eu

binary=${BINARY:-./bench-cycles}
runs=${RUNS:-5}
cpu=${CPU:-2}
scenarios=${*:-layout strong required reject suggest suggest2 suggest20}

cycles() {
  best=0
  i=0
  while [ "$i" -lt "$runs" ]; do
    n=$(taskset -c "$cpu" perf stat -x, -e cycles:u "$binary" "$1" 2>&1 >/dev/null | awk -F, '{ s += $1 } END { print s }')
    if [ "$best" -eq 0 ] || [ "$n" -lt "$best" ]; then best=$n; fi
    i=$((i + 1))
  done
  echo "$best"
}

base=$(cycles none)
for scenario in $scenarios; do
  printf '%-10s %8d\n' "$scenario" $(( ($(cycles "$scenario") - base) / 1000000 ))
done
