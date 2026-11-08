#!/usr/bin/env python3
import csv
import os
import random
import re
import secrets
import sys
import time
from pathlib import Path

USAGE = "usage: virtual_dispatch.py [--size N] [--seed U64] [--repeats N] [--value I32] [--warmup-samples N] [--samples N] --output DIR --run-id ID [--trial N] --target cpython [--config-id ID]"
IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\Z")
HEADER = ["schema_version", "run_id", "benchmark", "case_id", "language", "target", "config_id", "toolchain", "flags", "environment", "trial", "phase", "sample", "elapsed_ms", "metric", "value", "unit"]

class Operation:
    def process(self, value: int) -> int:
        raise NotImplementedError

class AddOperation(Operation):
    def __init__(self, operand: int): self.operand = operand
    def process(self, value: int) -> int: return i32(value + self.operand)

class MulOperation(Operation):
    def __init__(self, operand: int): self.operand = operand
    def process(self, value: int) -> int: return i32(value * self.operand)

def i32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value if value < 0x80000000 else value - 0x100000000

def fail(message: str) -> None:
    print(f"error: {message}\n{USAGE}", file=sys.stderr)
    raise SystemExit(2)

def parse(argv):
    if argv == ["--help"]:
        print(USAGE)
        raise SystemExit(0)
    allowed = {"--size", "--seed", "--repeats", "--value", "--warmup-samples", "--samples", "--output", "--run-id", "--trial", "--target", "--config-id"}
    values = {}
    i = 0
    while i < len(argv):
        key = argv[i]
        if key not in allowed: fail(f"unknown option: {key}")
        if key in values: fail(f"duplicate option: {key}")
        if i + 1 == len(argv): fail(f"missing value for {key}")
        values[key] = argv[i + 1]
        i += 2
    def number(key, default, low, high):
        raw = values.get(key, str(default))
        if not raw or not re.fullmatch(r"-?[0-9]+", raw): fail(f"invalid value for {key}: {raw}")
        value = int(raw)
        if not low <= value <= high: fail(f"out-of-range value for {key}: {raw}")
        return value
    cfg = {
        "size": number("--size", 100000, 1, 2147483647),
        "repeats": number("--repeats", 100, 1, 2147483647),
        "value": number("--value", 1, -2147483648, 2147483647),
        "warmup": number("--warmup-samples", 5, 0, 2147483647),
        "samples": number("--samples", 20, 1, 2147483647),
        "trial": number("--trial", 1, 1, 2147483647),
    }
    seed_raw = values.get("--seed")
    if seed_raw is None:
        cfg["seed"] = secrets.randbits(64)
    elif not re.fullmatch(r"[0-9]+", seed_raw) or not 0 <= int(seed_raw) <= 0xFFFFFFFFFFFFFFFF:
        fail(f"invalid value for --seed: {seed_raw}")
    else: cfg["seed"] = int(seed_raw)
    for key in ("--output", "--run-id", "--target"):
        if key not in values or not values[key]: fail(f"{key} is required")
    if values["--target"] != "cpython": fail("invalid target for Python")
    cfg.update(output=values["--output"], run_id=values["--run-id"], target=values["--target"], config_id=values.get("--config-id", "default"))
    for key in ("run_id", "config_id"):
        if not IDENTIFIER.fullmatch(cfg[key]): fail(f"invalid identifier for --{key.replace('_', '-')}")
    return cfg

def prepare(size, seed):
    rng = random.Random(seed)
    operations, direct = [], []
    for _ in range(size):
        add = bool(rng.getrandbits(1)); operand = rng.randrange(1, 17)
        operations.append(AddOperation(operand) if add else MulOperation(operand))
        direct.append((add, operand))
    return operations, direct

def run(operations, repeats, value):
    checksum = 0
    for _ in range(repeats):
        for operation in operations:
            checksum = i32(checksum + operation.process(value))
    return checksum

def expected(direct, repeats, value):
    one_pass = 0
    for add, operand in direct:
        result = i32(value + operand) if add else i32(value * operand)
        one_pass = (one_pass + (result & 0xFFFFFFFF)) & 0xFFFFFFFF
    return i32(one_pass * repeats)

def main():
    cfg = parse(sys.argv[1:])
    operations, direct = prepare(cfg["size"], cfg["seed"])
    want = expected(direct, cfg["repeats"], cfg["value"])
    output = Path(cfg["output"]); output.mkdir(parents=True, exist_ok=True)
    path = output / "results.csv"
    toolchain = f"CPython {sys.version.split()[0]}"
    environment = os.environ.get("BENCH_ENVIRONMENT", "unknown")
    case_id = f"size-{cfg['size']}-repeats-{cfg['repeats']}-value-{cfg['value']}-seed-{cfg['seed']}"
    rows = []
    start = time.monotonic_ns()
    total = cfg["warmup"] + cfg["samples"]
    last = None
    for index in range(1, total + 1):
        before = time.monotonic_ns(); actual = run(operations, cfg["repeats"], cfg["value"]); after = time.monotonic_ns()
        if actual != want: raise RuntimeError(f"checksum mismatch: expected {want}, got {actual}")
        last = actual
        phase = "warmup" if index <= cfg["warmup"] else "unclassified"
        rows.append([2, cfg["run_id"], "virtual-dispatch", case_id, "Python", cfg["target"], cfg["config_id"], toolchain, "", environment, cfg["trial"], phase, index, f"{(after-start)/1e6:.6f}", "time_per_op", after-before, "ns/op"])
    exists = path.exists() and path.stat().st_size > 0
    with path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        if not exists: writer.writerow(HEADER)
        writer.writerows(rows)
    print(f"effective size={cfg['size']} seed={cfg['seed']} repeats={cfg['repeats']} value={cfg['value']} warmup_samples={cfg['warmup']} samples={cfg['samples']} run_id={cfg['run_id']} trial={cfg['trial']} target={cfg['target']} config_id={cfg['config_id']}", file=sys.stderr)
    print(f"toolchain={toolchain} flags=<defaults> environment={environment}", file=sys.stderr)
    print(f"checksum={last}", file=sys.stderr)

if __name__ == "__main__":
    main()
