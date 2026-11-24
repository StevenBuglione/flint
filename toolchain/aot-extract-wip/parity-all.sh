#!/bin/bash
# Every parity set: petclinic's platform modules, the three apps, the tests/aot fixtures.
S=/tmp/claude-1000/-home-olfa-flint-work/e41cacc0-9489-45d7-9965-e0c635c9d948/scratchpad
cd ~/flint-work/dmd-arm64/flint
P=benchmarks/spring/flint/petclinic-rest; G=$PWD/$P/.flint/generated/aot-extract
M=$(grep -v "^-" $P/.flint/generated/platform/dmd-server-prelude.txt | grep -vx "flint.arena.sys.gc.counting" | tr '\n' ',' | sed 's/,$//')
summary() { grep -E "^[a-z].*rc=|identical" | sed 's/^  //' | paste - - | cut -c1-260; }
python3 $S/parity.py $P --modules "$M" 2>&1 | summary
python3 $S/parity.py $P 2>&1 | summary
for a in gs-rest-service gs-relational-data-access; do python3 $S/parity.py benchmarks/spring/flint/$a --args $S/args-$a.json 2>&1 | summary; done
for d in annotations autoconfig date diagnostics exporter gs-rest-service hierarchy imports petclinic-rest sample; do
  T=tests/aot/$d; src=$T/src; [ -d $T/source ] && src=$T/source; [ $d = annotations ] && src=$T
  python3 $S/parity.py $T --src $PWD/$src --gen $G 2>&1 | summary
done
