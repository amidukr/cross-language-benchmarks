using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
interface IOperation {
  int Process(int value);
}
readonly record struct AddOperation(int Operand) : IOperation {
  public int Process(int v) => unchecked(v + Operand);
}
readonly record struct MulOperation(int Operand) : IOperation {
  public int Process(int v) => unchecked(v * Operand);
}
readonly record struct Direct(bool Add, int Operand);
record Config(int Size, ulong Seed, int Repeats, int Value, int Warmup,
              int Samples, string Output, string RunId, int Trial,
              string Target, string ConfigId);
static class Program {
  const string Usage =
      "usage: VirtualDispatch [--size N] [--seed U64] [--repeats N] [--value " +
      "I32] [--warmup-samples N] [--samples N] --output DIR --run-id ID " +
      "[--trial N] --target TARGET [--config-id ID]";
  static void Fail(string s) {
    Console.Error.WriteLine($"error: {s}\n{Usage}");
    Environment.Exit(2);
  }
  static int Num(Dictionary<string, string> m, string k, int d, int lo,
                 int hi) {
    var s = m.GetValueOrDefault(k, d.ToString(CultureInfo.InvariantCulture));
    if (!int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture,
                      out var v) ||
        v < lo || v > hi)
      Fail($"invalid value for {k}: {s}");
    return v;
  }
  static Config Parse(string[] a) {
    if (a.Length == 1 && a[0] == "--help") {
      Console.WriteLine(Usage);
      Environment.Exit(0);
    }
    var allowed =
        new HashSet<string> { "--size",   "--seed",           "--repeats",
                              "--value",  "--warmup-samples", "--samples",
                              "--output", "--run-id",         "--trial",
                              "--target", "--config-id" };
    var m = new Dictionary<string, string>();
    for (int i = 0; i < a.Length; i += 2) {
      if (!allowed.Contains(a[i]))
        Fail($"unknown option: {a[i]}");
      if (m.ContainsKey(a[i]))
        Fail($"duplicate option: {a[i]}");
      if (i + 1 >= a.Length)
        Fail($"missing value for {a[i]}");
      m[a[i]] = a[i + 1];
    }
    foreach (var k in new[] { "--output", "--run-id", "--target" })
      if (!m.TryGetValue(k, out var x) || x.Length == 0)
        Fail($"{k} is required");
    if (m["--target"] is not("coreclr" or "dotnet-native"))
      Fail("invalid C# target");
    var id = new Regex("^[A-Za-z0-9][A-Za-z0-9._-]*$",
                       RegexOptions.CultureInvariant);
    var config = m.GetValueOrDefault("--config-id", "default");
    if (!id.IsMatch(m["--run-id"]) || !id.IsMatch(config))
      Fail("invalid identifier");
    ulong seed;
    if (m.TryGetValue("--seed", out var raw)) {
      if (!ulong.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture,
                          out seed))
        Fail("invalid --seed");
    } else
      seed = BitConverter.ToUInt64(RandomNumberGenerator.GetBytes(8));
    return new(Num(m, "--size", 100000, 1, int.MaxValue), seed,
               Num(m, "--repeats", 100, 1, int.MaxValue),
               Num(m, "--value", 1, int.MinValue, int.MaxValue),
               Num(m, "--warmup-samples", 5, 0, int.MaxValue),
               Num(m, "--samples", 20, 1, int.MaxValue), m["--output"],
               m["--run-id"], Num(m, "--trial", 1, 1, int.MaxValue),
               m["--target"], config);
  }
  static ulong Next(ref ulong s) {
    unchecked {
      s += 0x9e3779b97f4a7c15UL;
      var z = s;
      z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9UL;
      z = (z ^ (z >> 27)) * 0x94d049bb133111ebUL;
      return z ^ (z >> 31);
    }
  }
  static (IOperation[], Direct[]) Prepare(int size, ulong seed) {
    var ops = new IOperation[size];
    var d = new Direct[size];
    for (var i = 0; i < size; i++) {
      var b = Next(ref seed);
      var add = (b & 1) != 0;
      var operand = (int)((b >> 1) & 15) + 1;
      ops[i] = add ? new AddOperation(operand) : new MulOperation(operand);
      d[i] = new(add, operand);
    }
    return (ops, d);
  }
  static int Run(IOperation[] ops, int repeats, int value) {
    var sum = 0;
    unchecked {
      for (var n = 0; n < repeats; n++)
        foreach (var op in ops)
          sum += op.Process(value);
    }
    return sum;
  }
  static int Expected(Direct[] d, int repeats, int value) {
    var one = 0;
    unchecked {
      foreach (var x in d)
        one += x.Add ? value + x.Operand : value * x.Operand;
      return one * repeats;
    }
  }
  static string Csv(object v) {
    var s = Convert.ToString(v, CultureInfo.InvariantCulture)!;
    return s.IndexOfAny([',', '"', '\r', '\n']) >= 0
               ? $"\"{s.Replace("\"","\"\"")}\""
               : s;
  }
  static void Main(string[] args) {
    var c = Parse(args);
    var (ops, direct) = Prepare(c.Size, c.Seed);
    var want = Expected(direct, c.Repeats, c.Value);
    Directory.CreateDirectory(c.Output);
    var file = Path.Combine(c.Output, "results.csv");
    var exists = File.Exists(file) && new FileInfo(file).Length > 0;
    var text = new StringBuilder();
    if (!exists)
      text.AppendLine("schema_version,run_id,benchmark,case_id,language," +
                      "target,config_id,toolchain,flags,environment,trial," +
                      "phase,sample,elapsed_ms,metric,value,unit");
    var start = Stopwatch.GetTimestamp();
    var last = 0;
    var env =
        Environment.GetEnvironmentVariable("BENCH_ENVIRONMENT") ?? "unknown";
    var caseId =
        $"size-{c.Size}-repeats-{c.Repeats}-value-{c.Value}-seed-{c.Seed}";
    var flags =
        c.Target == "dotnet-native"
            ? "dotnet publish -c Release -r linux-x64 -p:PublishAot=true"
            : "dotnet publish -c Release --no-self-contained";
    for (var i = 1; i <= c.Warmup + c.Samples; i++) {
      var before = Stopwatch.GetTimestamp();
      var actual = Run(ops, c.Repeats, c.Value);
      var after = Stopwatch.GetTimestamp();
      if (actual != want)
        throw new Exception(
            $"checksum mismatch: expected {want}, got {actual}");
      last = actual;
      object[] row = { 2,
                       c.RunId,
                       "virtual-dispatch",
                       caseId,
                       "C#",
                       c.Target,
                       c.ConfigId,
                       RuntimeInformation.FrameworkDescription,
                       flags,
                       env,
                       c.Trial,
                       i <= c.Warmup ? "warmup" : "unclassified",
                       i,
                       ((after - start) * 1000.0 / Stopwatch.Frequency)
                           .ToString("F6", CultureInfo.InvariantCulture),
                       "time_per_op",
                       (long)((after - before) * 1_000_000_000.0 /
                              Stopwatch.Frequency),
                       "ns/op" };
      text.AppendLine(string.Join(',', row.Select(Csv)));
    }
    File.AppendAllText(file, text.ToString(), Encoding.UTF8);
    Console.Error.WriteLine(
        $"effective size={c.Size} seed={c.Seed} repeats={c.Repeats} value={c.Value} warmup_samples={c.Warmup} samples={c.Samples} run_id={c.RunId} trial={c.Trial} target={c.Target} config_id={c.ConfigId}\ntoolchain={RuntimeInformation.FrameworkDescription} flags={flags} environment={env}\nchecksum={last}");
  }
}
