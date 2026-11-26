# Initial JDK link-closure baseline

Measured on venus at `17d2aacb` with LDC 1.43.0 (LLVM 22.1.8), the pinned Flint DUB and GNU ld 2.42.
The probes use the release and size profiles in `policy/profiles.toml`, both with ThinLTO.

The control links the D runtime and returns its runtime argument count. Its file-backed allocated ELF
sections total 328,749 bytes in each profile. Deltas sum those same sections in the probe and subtract
the control. The audit counts names per probe and profile after section GC.

| Probe | O3 delta (B) | Oz delta (B) | O3 violations | Oz violations |
| --- | ---: | ---: | ---: | ---: |
| [character-ascii-lower](character-ascii-lower.d) | 1,852 | 676 | 10 | 10 |
| [character-category](character-category.d) | 7,292 | 6,108 | 10 | 10 |
| [character-lower](character-lower.d) | 12,676 | 11,468 | 10 | 10 |
| [classref](classref.d) | 0 | 0 | 0 | 0 |
| [bytearray-input](bytearray-input.d) | 3,652 | 2,468 | 10 | 10 |
| [boolean](boolean.d) | 1,812 | 636 | 10 | 10 |
| [double](double.d) | 8,620 | 6,316 | 10 | 10 |
| [integer](integer.d) | 6,484 | 5,028 | 10 | 10 |
| [long](long.d) | 6,484 | 5,028 | 10 | 10 |
| [string-format](string-format.d) | 35,596 | 30,228 | 10 | 10 |
| [string-hash](string-hash.d) | 2,332 | 1,140 | 10 | 10 |
| [valueof-array](valueof-array.d) | 473,683 | 472,291 | 13 | 13 |
| [uri](uri.d) | 6,060 | 4,556 | 10 | 10 |
| [charset](charset.d) | 8,148 | 6,652 | 10 | 10 |
| [sql-exception](sql-exception.d) | 3,156 | 1,980 | 9 | 9 |
| [message-format](message-format.d) | 12,460 | 8,084 | 10 | 10 |
| [date-format](date-format.d) | 44,400 | 39,776 | 7 | 7 |
| [localdate](localdate.d) | 38,604 | 32,676 | 8 | 8 |
| [time-format](time-format.d) | 17,908 | 15,284 | 8 | 8 |
| [arraylist](arraylist.d) | 2,852 | 39,104 | 9 | 10 |
| [hashmap](hashmap.d) | 103,276 | 97,780 | 10 | 10 |
| [optional](optional.d) | 5,700 | 4,316 | 9 | 9 |
| [calendar](calendar.d) | 20,636 | 17,004 | 6 | 6 |
| [time-unit](time-unit.d) | 1,836 | 660 | 11 | 11 |
| [atomic](atomic.d) | 1,460 | 1,460 | 0 | 0 |
| [date](date.d) | 8,188 | 5,972 | 8 | 8 |
| [descriptors](descriptors.d) | 7,796 | 6,308 | 11 | 11 |
| [formatter](formatter.d) | 35,452 | 30,084 | 10 | 10 |
| [function](function.d) | 16 | 816 | 0 | 0 |
| [stream](stream.d) | 53,136 | 48,984 | 8 | 8 |
| [timezone](timezone.d) | 9,252 | 7,764 | 8 | 8 |
| [datasource](datasource.d) | 2,540 | 1,364 | 10 | 10 |

The 32 probes cover 22 source-backed modules. The ratchet starts with 551 link violations and the
`std.conv` source import in `flint.java.lang`. The executable for the ASCII-constrained Character
probe retains no Unicode table. The Unicode case and category probes retain their declared tables.
The D array fallback in `valueOf` retains symbols from all 13 forbidden Phobos families.

The initial ratchet also records the module records observed in sibling packages before the audit
was enabled. The Period probe at `de670e9e` added 12,764/10,524 loadable bytes and retained eight
undeclared module records in each profile. The BigInteger arithmetic probe at `5d7da8c5` added
13,948/12,308 bytes and retained ten such records in each profile. UUID at `b391003d` retained the
same ten records in each profile. The TimeoutException throw/catch probe at `8660e70f` retained
one record for Callable in each profile through the shared D runtime type-info template. Decision
`36c5384c` approved recording those two rows.

The following command retains the maps, symbols and section listings when rerun on venus with
the shared measurement lock exported.

```sh
python3 tools/measure_queue.py hold -- python3 tools/jdk_link_closure.py --package java --evidence <directory>
```
