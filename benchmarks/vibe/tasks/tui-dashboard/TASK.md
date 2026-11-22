# Terminal dashboard of live metrics

Build a full-screen terminal program, `dash`, that shows metrics from a file and follows the file as it grows.

## Running

`dash --source <file>`

- The file holds JSON lines of the form `{"name": "<metric>", "value": <number>}`. A later line for the same name replaces its value.
- A line that is not such an object is counted as skipped and otherwise ignored.
- The program reads the whole file at start. It then checks for new lines at least twice a second and redraws when something changed.
- A missing source file is an error: exit code 2, and a message on standard error, before the screen is touched.

## Screen

- The first line is the title, `Dashboard — <file name>`.
- Below it comes one row per metric with its name and value. Values print with up to two decimals, so `3`, `2.5` and `0.33`. Rows are in first-seen order, or sorted by value with the largest first after `s` toggles sorting.
- The selected row is highlighted, and `↑`/`↓` or `k`/`j` move the selection.
- The last line reads `<n> metrics, <m> skipped — q quits, s sorts`.
- The program uses the terminal's alternate screen and hides the cursor while it runs.

## Keys and exit

- `q`, `Esc` and Ctrl+C quit.
- On exit, by key or by SIGTERM, the terminal is restored: the main screen comes back, the cursor is visible and the terminal is not left in raw mode. The exit code is 0.
- The layout adapts to the terminal size, which is at least 40×10, and to resizing.
