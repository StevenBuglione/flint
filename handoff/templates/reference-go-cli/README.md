# Go CLI reference

Pin Go 1.27.4. This reference parses a name flag, loads the same JSON greeting configuration, writes the same greeting and emits one structured JSON log. It is the supported subset used by bench-cli; shell completion and TOML are not benchmark workloads. Run `go build -buildvcs=false -trimpath -ldflags="-s -w" .` and `./reference-go-cli --name world` from this folder. Cold/incremental cache rules must match the compile protocol; no artificial rebuild of Go's standard library is charged only to Go.
