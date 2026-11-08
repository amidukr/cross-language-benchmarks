use std::{
    collections::HashMap,
    env,
    fs::{self, OpenOptions},
    io::{Read, Write},
    path::PathBuf,
    process,
    time::Instant,
};
const USAGE: &str = "usage: virtual-dispatch [--size N] [--seed U64] [--repeats N] [--value I32] [--warmup-samples N] [--samples N] --output DIR --run-id ID [--trial N] --target rust [--config-id ID]";
trait Operation {
    fn process(&self, value: i32) -> i32;
}
struct Add(i32);
impl Operation for Add {
    fn process(&self, v: i32) -> i32 {
        v.wrapping_add(self.0)
    }
}
struct Mul(i32);
impl Operation for Mul {
    fn process(&self, v: i32) -> i32 {
        v.wrapping_mul(self.0)
    }
}
struct Config {
    size: usize,
    seed: u64,
    repeats: u32,
    value: i32,
    warmup: u32,
    samples: u32,
    output: PathBuf,
    run_id: String,
    trial: u32,
    target: String,
    config_id: String,
}
fn fail(s: &str) -> ! {
    eprintln!("error: {s}\n{USAGE}");
    process::exit(2)
}
fn ident(s: &str) -> bool {
    let mut c = s.chars();
    matches!(c.next(),Some(x)if x.is_ascii_alphanumeric())
        && c.all(|x| x.is_ascii_alphanumeric() || "._-".contains(x))
}
fn parse() -> Config {
    let args: Vec<String> = env::args().skip(1).collect();
    if args == ["--help"] {
        println!("{USAGE}");
        process::exit(0)
    }
    let allowed = [
        "--size",
        "--seed",
        "--repeats",
        "--value",
        "--warmup-samples",
        "--samples",
        "--output",
        "--run-id",
        "--trial",
        "--target",
        "--config-id",
    ];
    let mut m = HashMap::new();
    let mut i = 0;
    while i < args.len() {
        if !allowed.contains(&args[i].as_str()) {
            fail(&format!("unknown option: {}", args[i]))
        }
        if m.contains_key(&args[i]) {
            fail(&format!("duplicate option: {}", args[i]))
        }
        if i + 1 >= args.len() {
            fail(&format!("missing value for {}", args[i]))
        }
        m.insert(args[i].clone(), args[i + 1].clone());
        i += 2
    }
    let get = |k: &str| {
        m.get(k)
            .cloned()
            .unwrap_or_else(|| fail(&format!("{k} is required")))
    };
    let num = |k: &str, d: &str, min: i64, max: i64| {
        let raw = m.get(k).map(String::as_str).unwrap_or(d);
        raw.parse::<i64>()
            .ok()
            .filter(|v| *v >= min && *v <= max)
            .unwrap_or_else(|| fail(&format!("invalid value for {k}: {raw}")))
    };
    let target = get("--target");
    if target != "rust" {
        fail("invalid Rust target")
    }
    let run_id = get("--run-id");
    let config_id = m
        .get("--config-id")
        .cloned()
        .unwrap_or_else(|| "default".into());
    if !ident(&run_id) || !ident(&config_id) {
        fail("invalid identifier")
    }
    let seed = match m.get("--seed") {
        Some(v) => v.parse().unwrap_or_else(|_| fail("invalid --seed")),
        None => {
            let mut b = [0; 8];
            std::fs::File::open("/dev/urandom")
                .and_then(|mut f| f.read_exact(&mut b))
                .unwrap_or_else(|_| fail("cannot generate seed"));
            u64::from_le_bytes(b)
        }
    };
    Config {
        size: num("--size", "100000", 1, i32::MAX as i64) as usize,
        seed,
        repeats: num("--repeats", "100", 1, i32::MAX as i64) as u32,
        value: num("--value", "1", i32::MIN as i64, i32::MAX as i64) as i32,
        warmup: num("--warmup-samples", "5", 0, i32::MAX as i64) as u32,
        samples: num("--samples", "20", 1, i32::MAX as i64) as u32,
        output: get("--output").into(),
        run_id,
        trial: num("--trial", "1", 1, i32::MAX as i64) as u32,
        target,
        config_id,
    }
}
fn next(s: &mut u64) -> u64 {
    *s = s.wrapping_add(0x9e3779b97f4a7c15);
    let mut z = *s;
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
    z ^ (z >> 31)
}
fn prepare(size: usize, seed: u64) -> (Vec<Box<dyn Operation>>, Vec<(bool, i32)>) {
    let (mut ops, mut direct, mut state) =
        (Vec::with_capacity(size), Vec::with_capacity(size), seed);
    for _ in 0..size {
        let b = next(&mut state);
        let add = b & 1 != 0;
        let operand = ((b >> 1) & 15) as i32 + 1;
        if add {
            ops.push(Box::new(Add(operand)) as Box<dyn Operation>)
        } else {
            ops.push(Box::new(Mul(operand)))
        }
        direct.push((add, operand))
    }
    (ops, direct)
}
fn run(ops: &[Box<dyn Operation>], repeats: u32, value: i32) -> i32 {
    let mut sum = 0i32;
    for _ in 0..repeats {
        for op in ops {
            sum = sum.wrapping_add(op.process(value))
        }
    }
    sum
}
fn expected(d: &[(bool, i32)], repeats: u32, value: i32) -> i32 {
    let mut one = 0i32;
    for &(add, x) in d {
        one = one.wrapping_add(if add {
            value.wrapping_add(x)
        } else {
            value.wrapping_mul(x)
        })
    }
    one.wrapping_mul(repeats as i32)
}
fn csv(s: &str) -> String {
    if s.contains([',', '"', '\r', '\n']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.into()
    }
}
fn main() {
    let c = parse();
    let (ops, direct) = prepare(c.size, c.seed);
    let want = expected(&direct, c.repeats, c.value);
    fs::create_dir_all(&c.output).unwrap();
    let path = c.output.join(format!("{}-report.csv", c.target));
    let exists = fs::metadata(&path).map(|m| m.len() > 0).unwrap_or(false);
    let mut out = String::new();
    if !exists {
        out.push_str("schema_version,run_id,benchmark,case_id,language,target,config_id,toolchain,flags,environment,trial,phase,sample,elapsed_ms,metric,value,unit\n")
    }
    let start = Instant::now();
    let total = c.warmup + c.samples;
    let envv = env::var("BENCH_ENVIRONMENT").unwrap_or_else(|_| "unknown".into());
    let case_id = format!(
        "size-{}-repeats-{}-value-{}-seed-{}",
        c.size, c.repeats, c.value, c.seed
    );
    let mut last = 0;
    for index in 1..=total {
        let before = Instant::now();
        let actual = run(&ops, c.repeats, c.value);
        let duration = before.elapsed();
        if actual != want {
            panic!("checksum mismatch: expected {want}, got {actual}")
        }
        last = actual;
        let row = [
            "2".into(),
            c.run_id.clone(),
            "virtual-dispatch".into(),
            case_id.clone(),
            "Rust".into(),
            c.target.clone(),
            c.config_id.clone(),
            format!("rustc {}", option_env!("RUSTC_VERSION").unwrap_or("1.90.0")),
            "cargo build --release --locked; lto=true; codegen-units=1".into(),
            envv.clone(),
            c.trial.to_string(),
            if index <= c.warmup {
                "warmup".into()
            } else {
                "unclassified".into()
            },
            index.to_string(),
            format!("{:.6}", start.elapsed().as_secs_f64() * 1000.0),
            "time_per_op".into(),
            duration.as_nanos().to_string(),
            "ns/op".into(),
        ];
        out.push_str(&row.iter().map(|x| csv(x)).collect::<Vec<_>>().join(","));
        out.push('\n')
    }
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .unwrap()
        .write_all(out.as_bytes())
        .unwrap();
    eprintln!(
        "effective size={} seed={} repeats={} value={} warmup_samples={} samples={} run_id={} trial={} target={} config_id={}\ntoolchain=rustc {} flags=cargo build --release --locked; lto=true; codegen-units=1 environment={}\nchecksum={}",
        c.size,
        c.seed,
        c.repeats,
        c.value,
        c.warmup,
        c.samples,
        c.run_id,
        c.trial,
        c.target,
        c.config_id,
        option_env!("RUSTC_VERSION").unwrap_or("1.90.0"),
        envv,
        last
    )
}
