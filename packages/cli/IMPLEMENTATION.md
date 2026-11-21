# flint:cli

Define a command with a struct and annotate its fields with Option, Arg, or
Subcommand. Call parse with the arguments after the program name. Check the
error and action before using the returned options. The selected command name
contains the root name and any selected subcommands, separated by spaces.

An explicit command-line value takes precedence over an opted-in environment
variable and the typed default. A required value must come from the command line or an enabled
environment binding. An explicit array input starts a new array and preserves its order.
Strings and arrays in the result are owned by the result. Argument indices in
diagnostics are zero-based and refer to the original array passed to parse.
A missing input or environment value has no argument index. Conversion and
validation diagnostics do not print the supplied value.

Help follows the declaration order and wraps at 80 columns. It uses plain text.
The completion writer accepts bash, zsh, or PowerShell. Each script contains
literal schema metadata and tracks the selected subcommand.

## Acceptance fixtures

Run the unit suite and package checks from the repository root.

```sh
dub test :cli --compiler=dmd
dub test :cli --compiler=ldc2
python3 tools/gates.py --package cli --gate structural
```

The declarations under fixtures/negative must fail compilation with a
field-qualified duplicate-binding error. The completion fixture emits
each script and the checked help snapshot. Run its Bash and zsh driver
with the directory containing complete.bash, complete.zsh, and complete.ps1.
The PowerShell driver dot-sources the generated script and checks the
insertion using PowerShell's own syntax parser.

The fuzz fixture accepts the run duration in seconds. It exercises every
short length through 256 and the 1 KiB and 1 MiB boundaries before entering
the timed deterministic corpus. Use the LDC AddressSanitizer profile for
a 60-second smoke run or a 1,800-second extended run.

The default bench fixture and its baseline each execute the 64-option
workload. Build the scale configuration to exercise the 10- and 256-option
workloads too, and pass --measure for the extended timing samples.
Performance certification uses the central measurement producer.
