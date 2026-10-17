# Benchmarks

Scripts behind the numbers in the main README. Each one prints its environment first; `ITERATIONS` sets the
number of requests (or tuples) per case, `TARANTOOL_URI` the server (default `tcp://app:secret@localhost:3301`,
the 2.11 container from `docker-compose.yml`; `3302` is 3.x). Every case runs once to warm up and once for
the record; percentiles come from the sorted per-request durations. The request scripts create the space
`bench_items` (10k rows) and drop it at the end.

Run from `tarantool-client/`:

```sh
bundle exec ruby -Ilib benchmark/codec.rb             # msgpack encode/decode of the client's codec vs plain MessagePack
bundle exec ruby -Ilib benchmark/latency.rb           # select by pk, insert, select over a Pool from 8 threads
bundle exec ruby -Ilib benchmark/request_overhead.rb  # request path cost with and without instrumentation
gem install tarantool16 && ruby -Ilib benchmark/tarantool16.rb   # the other Ruby connector, same select/insert cases
cd benchmark/go && go run .                           # go-tarantool/v2, same cases, 8 goroutines on one connection
```

`tarantool16` is not a dependency of anything here; the script reports and exits 0 when the gem is missing
or fails. The Go module lives in `benchmark/go` with its own `go.mod`.

The numbers in the main README were taken on an Apple M-series laptop with Tarantool running in a podman VM
(`applehv`), so every request crosses the VM boundary: the ~0.15 ms floor is that round trip, not the
connector. Run on the same host as the server to compare connectors by their own overhead.
