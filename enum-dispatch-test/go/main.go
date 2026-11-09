package main

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/csv"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"time"
)

const usage = "usage: enum-dispatch [--size N] [--seed U64] [--repeats N] [--value I32] [--warmup-samples N] [--samples N] --output DIR --run-id ID [--trial N] --target go [--config-id ID]"

var header = []string{"schema_version", "run_id", "benchmark", "case_id", "language", "target", "config_id", "toolchain", "flags", "environment", "trial", "phase", "sample", "elapsed_ms", "metric", "value", "unit"}
var ident = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

type Operation uint8

const (
	Add Operation = iota
	Mul
)

type Instruction struct {
	operation Operation
	operand   int32
}

type Direct struct {
	add     bool
	operand int32
}
type Config struct {
	size, repeats, warmup, samples, trial int
	value                                 int32
	seed                                  uint64
	output, runID, target, configID       string
}

func fail(s string) { fmt.Fprintf(os.Stderr, "error: %s\n%s\n", s, usage); os.Exit(2) }
func parse(args []string) Config {
	if len(args) == 1 && args[0] == "--help" {
		fmt.Println(usage)
		os.Exit(0)
	}
	allowed := map[string]bool{"--size": true, "--seed": true, "--repeats": true, "--value": true, "--warmup-samples": true, "--samples": true, "--output": true, "--run-id": true, "--trial": true, "--target": true, "--config-id": true}
	m := map[string]string{}
	for i := 0; i < len(args); i += 2 {
		if !allowed[args[i]] {
			fail("unknown option: " + args[i])
		}
		if _, ok := m[args[i]]; ok {
			fail("duplicate option: " + args[i])
		}
		if i+1 >= len(args) {
			fail("missing value for " + args[i])
		}
		m[args[i]] = args[i+1]
	}
	num := func(k string, d, min, max int64) int64 {
		raw, ok := m[k]
		if !ok {
			raw = strconv.FormatInt(d, 10)
		}
		v, e := strconv.ParseInt(raw, 10, 64)
		if e != nil || v < min || v > max {
			fail("invalid value for " + k + ": " + raw)
		}
		return v
	}
	for _, k := range []string{"--output", "--run-id", "--target"} {
		if m[k] == "" {
			fail(k + " is required")
		}
	}
	if m["--target"] != "go" {
		fail("invalid Go target")
	}
	config := m["--config-id"]
	if config == "" {
		config = "default"
	}
	if !ident.MatchString(m["--run-id"]) || !ident.MatchString(config) {
		fail("invalid identifier")
	}
	var seed uint64
	if raw, ok := m["--seed"]; ok {
		v, e := strconv.ParseUint(raw, 10, 64)
		if e != nil {
			fail("invalid value for --seed: " + raw)
		}
		seed = v
	} else {
		var b [8]byte
		if _, e := rand.Read(b[:]); e != nil {
			fail("cannot generate seed")
		}
		seed = binary.LittleEndian.Uint64(b[:])
	}
	return Config{int(num("--size", 100000, 1, 2147483647)), int(num("--repeats", 100, 1, 2147483647)), int(num("--warmup-samples", 5, 0, 2147483647)), int(num("--samples", 20, 1, 2147483647)), int(num("--trial", 1, 1, 2147483647)), int32(num("--value", 1, -2147483648, 2147483647)), seed, m["--output"], m["--run-id"], m["--target"], config}
}
func next(state *uint64) uint64 {
	*state += 0x9e3779b97f4a7c15
	z := *state
	z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ^ (z >> 27)) * 0x94d049bb133111eb
	return z ^ (z >> 31)
}
func prepare(size int, seed uint64) ([]Instruction, []Direct) {
	ops := make([]Instruction, 0, size)
	direct := make([]Direct, 0, size)
	state := seed
	for i := 0; i < size; i++ {
		bits := next(&state)
		add := bits&1 != 0
		operand := int32((bits>>1)&15) + 1
		operation := Mul
		if add {
			operation = Add
		}
		ops = append(ops, Instruction{operation, operand})
		direct = append(direct, Direct{add, operand})
	}
	return ops, direct
}
func run(ops []Instruction, repeats int, value int32) int32 {
	var sum uint32
	for n := 0; n < repeats; n++ {
		for _, instruction := range ops {
			switch instruction.operation {
			case Add:
				sum += uint32(value) + uint32(instruction.operand)
			case Mul:
				sum += uint32(value) * uint32(instruction.operand)
			}
		}
	}
	return int32(sum)
}
func expected(d []Direct, repeats int, value int32) int32 {
	var one uint32
	for _, x := range d {
		if x.add {
			one += uint32(value) + uint32(x.operand)
		} else {
			one += uint32(value) * uint32(x.operand)
		}
	}
	return int32(one * uint32(repeats))
}
func main() {
	c := parse(os.Args[1:])
	ops, direct := prepare(c.size, c.seed)
	want := expected(direct, c.repeats, c.value)
	if e := os.MkdirAll(c.output, 0755); e != nil {
		panic(e)
	}
	filePath := filepath.Join(c.output, c.target+"-report.csv")
	info, e := os.Stat(filePath)
	exists := e == nil && info.Size() > 0
	f, e := os.OpenFile(filePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if e != nil {
		panic(e)
	}
	defer f.Close()
	w := csv.NewWriter(f)
	if !exists {
		_ = w.Write(header)
	}
	start := time.Now()
	last := int32(0)
	total := c.warmup + c.samples
	env := os.Getenv("BENCH_ENVIRONMENT")
	if env == "" {
		env = "unknown"
	}
	caseID := fmt.Sprintf("size-%d-repeats-%d-value-%d-seed-%d", c.size, c.repeats, c.value, c.seed)
	for i := 1; i <= total; i++ {
		before := time.Now()
		actual := run(ops, c.repeats, c.value)
		after := time.Now()
		if actual != want {
			panic(fmt.Sprintf("checksum mismatch: expected %d, got %d", want, actual))
		}
		last = actual
		phase := "unclassified"
		if i <= c.warmup {
			phase = "warmup"
		}
		row := []string{"2", c.runID, "enum-dispatch", caseID, "Go", c.target, c.configID, runtime.Version(), "go build -trimpath -ldflags=-s -w", env, strconv.Itoa(c.trial), phase, strconv.Itoa(i), fmt.Sprintf("%.6f", float64(after.Sub(start).Nanoseconds())/1e6), "time_per_op", strconv.FormatInt(after.Sub(before).Nanoseconds(), 10), "ns/op"}
		if e = w.Write(row); e != nil {
			panic(e)
		}
	}
	w.Flush()
	if e = w.Error(); e != nil {
		panic(e)
	}
	fmt.Fprintf(os.Stderr, "effective size=%d seed=%d repeats=%d value=%d warmup_samples=%d samples=%d run_id=%s trial=%d target=%s config_id=%s\ntoolchain=%s flags=go build -trimpath -ldflags=-s -w environment=%s\nchecksum=%d\n", c.size, c.seed, c.repeats, c.value, c.warmup, c.samples, c.runID, c.trial, c.target, c.configID, runtime.Version(), env, last)
}
