'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const v8 = require('node:v8');

const usage =
    'usage: enum-dispatch.js [--size N] [--seed U64] [--repeats N] [--value I32] [--warmup-samples N] [--samples N] --output DIR --run-id ID [--trial N] --target node-v8 [--config-id ID]';
const header = [
  'schema_version', 'run_id', 'benchmark', 'case_id', 'language', 'target',
  'config_id', 'toolchain', 'flags', 'environment', 'trial', 'phase', 'sample',
  'elapsed_ms', 'metric', 'value', 'unit'
];
const identifier = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
function fail(message) {
  console.error(`error: ${message}\n${usage}`);
  process.exit(2);
}
const Operation = Object.freeze({ADD : 0, MUL : 1});

function parse(argv) {
  if (argv.length === 1 && argv[0] === '--help') {
    console.log(usage);
    process.exit(0);
  }
  const allowed = new Set([
    '--size', '--seed', '--repeats', '--value', '--warmup-samples', '--samples',
    '--output', '--run-id', '--trial', '--target', '--config-id'
  ]);
  const values = new Map();
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    if (!allowed.has(key))
      fail(`unknown option: ${key}`);
    if (values.has(key))
      fail(`duplicate option: ${key}`);
    if (i + 1 >= argv.length)
      fail(`missing value for ${key}`);
    values.set(key, argv[i + 1]);
  }
  const integer = (key, fallback, low, high) => {
    const raw = values.get(key) ?? String(fallback);
    if (!/^-?[0-9]+$/.test(raw))
      fail(`invalid value for ${key}: ${raw}`);
    const n = Number(raw);
    if (!Number.isSafeInteger(n) || n < low || n > high)
      fail(`out-of-range value for ${key}: ${raw}`);
    return n;
  };
  for (const key of ['--output', '--run-id', '--target'])
    if (!values.get(key))
      fail(`${key} is required`);
  if (values.get('--target') !== 'node-v8')
    fail('invalid target for JavaScript');
  let seed;
  if (!values.has('--seed'))
    seed = crypto.randomBytes(8).readBigUInt64LE();
  else {
    const raw = values.get('--seed');
    if (!/^[0-9]+$/.test(raw))
      fail(`invalid value for --seed: ${raw}`);
    seed = BigInt(raw);
    if (seed > 0xffffffffffffffffn)
      fail(`out-of-range value for --seed: ${raw}`);
  }
  const cfg = {
    size : integer('--size', 100000, 1, 2147483647),
    repeats : integer('--repeats', 100, 1, 2147483647),
    value : integer('--value', 1, -2147483648, 2147483647),
    warmup : integer('--warmup-samples', 5, 0, 2147483647),
    samples : integer('--samples', 20, 1, 2147483647),
    trial : integer('--trial', 1, 1, 2147483647),
    seed,
    output : values.get('--output'),
    runId : values.get('--run-id'),
    target : values.get('--target'),
    configId : values.get('--config-id') ?? 'default'
  };
  if (!identifier.test(cfg.runId) || !identifier.test(cfg.configId))
    fail('invalid identifier');
  return cfg;
}
// SplitMix64 gives reproducible local generation without affecting the timed
// path.
function generator(seed) {
  let state = seed;
  return () => {
    state = BigInt.asUintN(64, state + 0x9e3779b97f4a7c15n);
    let z = state;
    z = BigInt.asUintN(64, (z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n);
    z = BigInt.asUintN(64, (z ^ (z >> 27n)) * 0x94d049bb133111ebn);
    return BigInt.asUintN(64, z ^ (z >> 31n));
  };
}
function prepare(size, seed) {
  const next = generator(seed), operations = [], direct = [];
  for (let i = 0; i < size; i++) {
    const bits = next(), add = (bits & 1n) !== 0n,
          operand = Number((bits >> 1n) & 15n) + 1;
    operations.push({
      operation : add ? Operation.ADD : Operation.MUL,
      operand,
    });
    direct.push([ add, operand ]);
  }
  return [ operations, direct ];
}
function run(operations, repeats, value) {
  let checksum = 0;
  for (let n = 0; n < repeats; n++)
    for (const instruction of operations) {
      let result;
      switch (instruction.operation) {
        case Operation.ADD:
          result = (value + instruction.operand) | 0;
          break;
        case Operation.MUL:
          result = Math.imul(value, instruction.operand);
          break;
        default:
          throw new Error('invalid operation');
      }
      checksum = (checksum + result) | 0;
    }
  return checksum;
}
function expected(direct, repeats, value) {
  let one = 0;
  for (const [add, operand] of direct) {
    const result = add ? (value + operand) | 0 : Math.imul(value, operand);
    one = (one + result) | 0;
  }
  return Math.imul(one, repeats);
}
function csv(value) {
  const s = String(value);
  return /[",\r\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
}
function main() {
  const cfg = parse(process.argv.slice(2));
  const [operations, direct] = prepare(cfg.size, cfg.seed),
                     want = expected(direct, cfg.repeats, cfg.value);
  fs.mkdirSync(cfg.output, {recursive : true});
  const rows = [], start = process.hrtime.bigint(),
        total = cfg.warmup + cfg.samples;
  let last;
  for (let index = 1; index <= total; index++) {
    const before = process.hrtime.bigint();
    const actual = run(operations, cfg.repeats, cfg.value);
    const after = process.hrtime.bigint();
    if (actual !== want)
      throw new Error(`checksum mismatch: expected ${want}, got ${actual}`);
    last = actual;
    rows.push([
      2, cfg.runId, 'enum-dispatch',
      `size-${cfg.size}-repeats-${cfg.repeats}-value-${cfg.value}-seed-${
          cfg.seed}`,
      'JavaScript', cfg.target, cfg.configId,
      `Node.js ${process.version}; V8 ${process.versions.v8}`, '',
      process.env.BENCH_ENVIRONMENT ?? 'unknown', cfg.trial,
      index <= cfg.warmup ? 'warmup' : 'unclassified', index,
      (Number(after - start) / 1e6).toFixed(6), 'time_per_op',
      String(after - before), 'ns/op'
    ]);
  }
  const file = path.join(cfg.output, `${cfg.target}-report.csv`),
        exists = fs.existsSync(file) && fs.statSync(file).size > 0;
  const lines = [];
  if (!exists)
    lines.push(header.map(csv).join(','));
  for (const row of rows)
    lines.push(row.map(csv).join(','));
  fs.appendFileSync(file, lines.join('\n') + '\n');
  console.error(`effective size=${cfg.size} seed=${cfg.seed} repeats=${
      cfg.repeats} value=${cfg.value} warmup_samples=${cfg.warmup} samples=${
      cfg.samples} run_id=${cfg.runId} trial=${cfg.trial} target=${
      cfg.target} config_id=${cfg.configId}`);
  console.error(`toolchain=Node.js ${process.version}; V8 ${
      process.versions.v8} flags=<defaults> environment=${
      process.env.BENCH_ENVIRONMENT ?? 'unknown'}`);
  console.error(`checksum=${last}`);
}
main();
