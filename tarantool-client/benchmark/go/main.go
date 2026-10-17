// The latency.rb cases through go-tarantool/v2, as the reference: select by primary key and insert on one
// connection, select from 8 goroutines on the same connection. Creates and drops bench_items.
//
//	cd benchmark/go && go run .
//
// TARANTOOL_URI overrides the shared container on 3301, ITERATIONS the number of requests per case.
package main

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tarantool/go-tarantool/v2"
)

const (
	rows    = 10000
	threads = 8
	create  = `local space = box.schema.space.create('bench_items', {if_not_exists = true, format = {
    {name = 'id', type = 'unsigned'}, {name = 'name', type = 'string'},
    {name = 'value', type = 'double'}, {name = 'tags', type = 'array'}}})
  space:create_index('primary', {parts = {'id'}, if_not_exists = true})`
	drop = `if box.space.bench_items then box.space.bench_items:drop() end`
)

func tuple(id uint64) []interface{} {
	return []interface{}{id, fmt.Sprintf("item %d", id), float64(id) * 0.5, []interface{}{"a", "b", "c"}}
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func must(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func durations(iterations int, run func(index int)) []time.Duration {
	taken := make([]time.Duration, iterations)
	for index := range taken {
		started := time.Now()
		run(index)
		taken[index] = time.Since(started)
	}
	return taken
}

func threadedDurations(iterations int, run func(index int)) []time.Duration {
	perThread := iterations / threads
	results := make([][]time.Duration, threads)
	var wg sync.WaitGroup
	for thread := 0; thread < threads; thread++ {
		wg.Add(1)
		go func(thread int) {
			defer wg.Done()
			results[thread] = durations(perThread, func(index int) { run(thread*perThread + index) })
		}(thread)
	}
	wg.Wait()
	var all []time.Duration
	for _, part := range results {
		all = append(all, part...)
	}
	return all
}

func percentile(sorted []time.Duration, fraction float64) time.Duration {
	return sorted[int(float64(len(sorted)-1)*fraction+0.5)]
}

func report(name string, iterations int, concurrent bool, run func(index int)) {
	for pass := 0; pass < 2; pass++ {
		started := time.Now()
		var taken []time.Duration
		if concurrent {
			taken = threadedDurations(iterations, run)
		} else {
			taken = durations(iterations, run)
		}
		elapsed := time.Since(started)
		if pass == 0 {
			continue
		}
		sort.Slice(taken, func(i, j int) bool { return taken[i] < taken[j] })
		ms := func(d time.Duration) float64 { return float64(d) / float64(time.Millisecond) }
		fmt.Printf("%-24s %9.0f req/s  p50 %6.3f ms  p95 %6.3f ms  p99 %6.3f ms\n", name,
			float64(len(taken))/elapsed.Seconds(), ms(percentile(taken, 0.5)), ms(percentile(taken, 0.95)),
			ms(percentile(taken, 0.99)))
	}
}

func main() {
	address := env("TARANTOOL_URI", "tcp://app:secret@localhost:3301")
	iterations, err := strconv.Atoi(env("ITERATIONS", "20000"))
	must(err)
	parsed, err := url.Parse(address)
	must(err)
	password, _ := parsed.User.Password()
	dialer := tarantool.NetDialer{Address: parsed.Host, User: parsed.User.Username(), Password: password}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := tarantool.Connect(ctx, dialer, tarantool.Opts{Timeout: 10 * time.Second})
	must(err)
	defer conn.Close()
	defer conn.Do(tarantool.NewEvalRequest(drop)).Get()

	_, err = conn.Do(tarantool.NewEvalRequest(create)).Get()
	must(err)
	schema, err := tarantool.GetSchema(conn)
	must(err)
	conn.SetSchema(schema)
	for id := uint64(1); id <= rows; id++ {
		_, err = conn.Do(tarantool.NewReplaceRequest("bench_items").Tuple(tuple(id))).Get()
		must(err)
	}
	fmt.Printf("go-tarantool/v2 | %s at %s | %s | %s/%s\n", strings.Fields(conn.Greeting.Version)[1], address,
		runtime.Version(), runtime.GOOS, runtime.GOARCH)

	selectByPk := func(index int) {
		_, err := conn.Do(tarantool.NewSelectRequest("bench_items").Index("primary").Limit(1).
			Key([]interface{}{uint64(index%rows + 1)})).Get()
		must(err)
	}
	report("select by pk", iterations, false, selectByPk)
	nextID := uint64(100000)
	report("insert", iterations, false, func(int) {
		nextID++
		_, err := conn.Do(tarantool.NewInsertRequest("bench_items").Tuple(tuple(nextID))).Get()
		must(err)
	})
	_, err = conn.Do(tarantool.NewEvalRequest(fmt.Sprintf(
		"for id = 100000, %d do box.space.bench_items:delete(id) end", nextID))).Get()
	must(err)
	report("select by pk, x8 goroutines", iterations, true, selectByPk)
}
