import java.io.*;
import java.lang.management.ManagementFactory;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.regex.Pattern;

public final class VirtualDispatch {
  interface Operation {
    int process(int value);
  }
  record AddOperation(int operand) implements Operation {
    public int process(int value) { return value + operand; }
  }
  record MulOperation(int operand) implements Operation {
    public int process(int value) { return value * operand; }
  }
  record Direct(boolean add, int operand) {}
  record Data(List<Operation> operations, List<Direct> direct) {}
  static final String USAGE =
      "usage: VirtualDispatch [--size N] [--seed U64] [--repeats N] [--value " +
      "I32] [--warmup-samples N] [--samples N] --output DIR --run-id ID " +
      "[--trial N] --target TARGET [--config-id ID]";
  static final String HEADER =
      "schema_version,run_id,benchmark,case_id,language,target,config_id," +
      "toolchain,flags,environment,trial,phase,sample,elapsed_ms,metric," +
      "value,unit\n";
  static final Pattern IDENTIFIER =
      Pattern.compile("[A-Za-z0-9][A-Za-z0-9._-]*");
  record Config(int size, long seed, int repeats, int value, int warmup,
                int samples, Path output, String runId, int trial,
                String target, String configId) {}

  static void fail(String message) {
    System.err.println("error: " + message + "\n" + USAGE);
    System.exit(2);
  }
  static int integer(Map<String, String> m, String key, int fallback, int low,
                     int high) {
    String raw = m.getOrDefault(key, Integer.toString(fallback));
    try {
      long v = Long.parseLong(raw);
      if (v < low || v > high)
        throw new NumberFormatException();
      return (int)v;
    } catch (NumberFormatException e) {
      fail("invalid value for " + key + ": " + raw);
      return 0;
    }
  }
  static Config parse(String[] args) {
    if (args.length == 1 && args[0].equals("--help")) {
      System.out.println(USAGE);
      System.exit(0);
    }
    Set<String> allowed =
        Set.of("--size", "--seed", "--repeats", "--value", "--warmup-samples",
               "--samples", "--output", "--run-id", "--trial", "--target",
               "--config-id");
    Map<String, String> m = new HashMap<>();
    for (int i = 0; i < args.length; i += 2) {
      String key = args[i];
      if (!allowed.contains(key))
        fail("unknown option: " + key);
      if (m.containsKey(key))
        fail("duplicate option: " + key);
      if (i + 1 >= args.length)
        fail("missing value for " + key);
      m.put(key, args[i + 1]);
    }
    for (String key : List.of("--output", "--run-id", "--target"))
      if (!m.containsKey(key) || m.get(key).isEmpty())
        fail(key + " is required");
    if (!Set.of("temurin-c2", "graalvm-jit", "graalvm-native")
             .contains(m.get("--target")))
      fail("invalid Java target");
    String runId = m.get("--run-id"),
           config = m.getOrDefault("--config-id", "default");
    if (!IDENTIFIER.matcher(runId).matches() ||
        !IDENTIFIER.matcher(config).matches())
      fail("invalid identifier");
    long seed;
    if (m.containsKey("--seed")) {
      try {
        seed = Long.parseUnsignedLong(m.get("--seed"));
      } catch (NumberFormatException e) {
        fail("invalid value for --seed: " + m.get("--seed"));
        return null;
      }
    } else
      seed = new SplittableRandom().nextLong();
    return new Config(
        integer(m, "--size", 100000, 1, Integer.MAX_VALUE), seed,
        integer(m, "--repeats", 100, 1, Integer.MAX_VALUE),
        integer(m, "--value", 1, Integer.MIN_VALUE, Integer.MAX_VALUE),
        integer(m, "--warmup-samples", 5, 0, Integer.MAX_VALUE),
        integer(m, "--samples", 20, 1, Integer.MAX_VALUE),
        Path.of(m.get("--output")), runId,
        integer(m, "--trial", 1, 1, Integer.MAX_VALUE), m.get("--target"),
        config);
  }
  static Data prepare(int size, long seed) {
    var random = new SplittableRandom(seed);
    var ops = new ArrayList<Operation>(size);
    var direct = new ArrayList<Direct>(size);
    for (int i = 0; i < size; i++) {
      boolean add = random.nextBoolean();
      int operand = random.nextInt(1, 17);
      ops.add(add ? new AddOperation(operand) : new MulOperation(operand));
      direct.add(new Direct(add, operand));
    }
    return new Data(ops, direct);
  }
  static int run(List<Operation> operations, int repeats, int value) {
    int checksum = 0;
    for (int n = 0; n < repeats; n++)
      for (Operation operation : operations)
        checksum += operation.process(value);
    return checksum;
  }
  static int expected(List<Direct> direct, int repeats, int value) {
    int one = 0;
    for (Direct d : direct)
      one += d.add ? value + d.operand : value * d.operand;
    return one * repeats;
  }
  static String csv(Object value) {
    String s = String.valueOf(value);
    return s.matches(".*[,\"\\r\\n].*") ? "\"" + s.replace("\"", "\"\"") + "\""
                                        : s;
  }
  public static void main(String[] args) throws Exception {
    Config c = parse(args);
    Data data = prepare(c.size, c.seed);
    int want = expected(data.direct, c.repeats, c.value);
    Files.createDirectories(c.output);
    Path result = c.output.resolve("results.csv");
    boolean exists = Files.exists(result) && Files.size(result) > 0;
    var out = new StringBuilder();
    if (!exists)
      out.append(HEADER);
    long start = System.nanoTime();
    int last = 0, total = c.warmup + c.samples;
    String toolchain = System.getProperty("java.runtime.name") + " " +
                       System.getProperty("java.runtime.version");
    String environment =
        System.getenv().getOrDefault("BENCH_ENVIRONMENT", "unknown");
    String caseId = "size-" + c.size + "-repeats-" + c.repeats + "-value-" +
                    c.value + "-seed-" + Long.toUnsignedString(c.seed);
    String flags = c.target.equals("graalvm-native")
                       ? "javac --release 25; native-image --no-fallback -O3"
                       : "javac --release 25";
    for (int index = 1; index <= total; index++) {
      long before = System.nanoTime();
      int actual = run(data.operations, c.repeats, c.value);
      long after = System.nanoTime();
      if (actual != want)
        throw new IllegalStateException("checksum mismatch: expected " + want +
                                        ", got " + actual);
      last = actual;
      Object[] row = {2,
                      c.runId,
                      "virtual-dispatch",
                      caseId,
                      "Java",
                      c.target,
                      c.configId,
                      toolchain,
                      flags,
                      environment,
                      c.trial,
                      index <= c.warmup ? "warmup" : "unclassified",
                      index,
                      String.format(Locale.ROOT, "%.6f", (after - start) / 1e6),
                      "time_per_op",
                      after - before,
                      "ns/op"};
      for (int i = 0; i < row.length; i++) {
        if (i > 0)
          out.append(',');
        out.append(csv(row[i]));
      }
      out.append('\n');
    }
    Files.writeString(result, out, StandardCharsets.UTF_8,
                      StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    System.err.printf(
        "effective size=%d seed=%s repeats=%d value=%d warmup_samples=%d " +
        "samples=%d run_id=%s trial=%d target=%s config_id=%s%n",
        c.size, Long.toUnsignedString(c.seed), c.repeats, c.value, c.warmup,
        c.samples, c.runId, c.trial, c.target, c.configId);
    System.err.println("toolchain=" + toolchain + " flags=" + flags +
                       " environment=" + environment);
    System.err.println("checksum=" + last);
  }
}
