# Background worker consuming a spool-directory queue

Build a long-running program, `worker`, that processes jobs from a queue kept in a directory.

## Running

`worker --spool <dir> [--concurrency <n>]`

- `--concurrency` defaults to 4 and must be from 1 to 64; anything else is exit code 2.
- The worker creates `<dir>/incoming`, `<dir>/done` and `<dir>/failed` if they are missing.
- It keeps running until it receives SIGTERM or SIGINT. Then it stops taking jobs, finishes the jobs it has started, and exits with code 0 within 5 seconds.

## Jobs

- A producer submits a job by writing `<dir>/incoming/<name>.json` atomically, through a temporary name that starts with `.`. Files whose names start with `.` are never read.
- A job looks like `{"id": "<id>", "op": "sha256" | "wordcount" | "sleep", "input": "..."}`, where `<id>` is 1 to 64 characters from `A-Z a-z 0-9 - _`.
  - **`sha256`:** the result is the lowercase hex SHA-256 of the UTF-8 bytes of `input`.
  - **`wordcount`:** the result is the number of whitespace-separated words in `input`, as a JSON number.
  - **`sleep`:** `input` is a number of milliseconds from 0 to 10000. The job waits that long, and its result is `null`.
- On success the worker writes `<dir>/done/<id>.json` with `{"id": "<id>", "result": <result>}`, then deletes the incoming file.
- A job file that is not valid JSON, lacks a field, has an invalid id, has an unknown op or has an invalid input fails.
  - The worker writes `<dir>/failed/<name>.json` with `{"file": "<name>.json", "error": "..."}` and deletes the incoming file. `<name>` is the incoming file's name without `.json`.
- Results are written atomically: a reader never sees a partial file in `done` or `failed`.
- Restarting the worker processes the jobs left in `incoming` and never processes a job twice.
- Up to `--concurrency` jobs run at the same time.

## Output

The worker logs one line per finished job to standard output, for example `done <id> 3ms` or `failed <name>: <error>`.
