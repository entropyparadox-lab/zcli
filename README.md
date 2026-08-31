# zcli ⚡

**Zero-Allocation Comptime Declarative CLI, Flag Parser & Completion Generator for Zig (v0.16.0+)**

`zcli` is an enterprise-grade, pure Zig command-line interface framework modeled after Rust's `clap` (derive) and Go's `cobra`. By leveraging Zig's powerful compile-time reflection (`@typeInfo`), `zcli` converts plain Zig structs and tagged unions into high-performance, type-safe CLI parsers with **zero heap allocations**, automated **ANSI help formatters**, and native **Bash/Zsh/Fish shell completion generators**.

---

## Benchmark Highlights (AMD Ryzen / ReleaseFast, 1,000,000 runs)

| Feature / Scenario | Allocation | Throughput (ops/sec) | Latency (ns/op) |
| :--- | :--- | :--- | :--- |
| **`zcli` Declarative Flag Parsing (10 Complex Args)** | **0 bytes (Zero-Alloc)** | **13.61 Million ops/sec** | **73.50 ns** |

---

## Key Features

- 🚀 **Zero-Allocation Architecture (`zcli.parse`)**: Borrows string slices directly from argument vectors without allocating memory on the heap.
- 🎯 **Declarative Struct Metadata (`pub const zcli = .{ ... }`)**:
  - Custom flag names, short character mappings (`.short = .{ .port = 'p' }`).
  - Environment variable fallbacks (`.env = .{ .port = "SERVER_PORT" }`).
  - Rich descriptions and field-level help messages.
  - Positional argument binding.
- 🌳 **Nested Subcommands via Tagged Unions (`union(enum)`)**:
  - Hierarchical command dispatching directly matching Zig enum variants.
- 🛠️ **POSIX-Compliant Argument Syntax**:
  - Long flags: `--port 8080`, `--port=8080`.
  - Negative boolean flags: `--no-color`, `--no-verbose`.
  - Short flags: `-p 8080`, `-p8080`.
  - Clustered short flags: `-xvf` or clustered with trailing value: `-vfp 8080`.
  - End-of-options delimiter: `--` captures remaining tokens as positional arguments.
- 🛡️ **Strict Type-Safe Deserialization**:
  - Supported types: integers (`u8`..`u128`, `i8`..`i128`), floats (`f32`, `f64`), booleans, enums (case-insensitive/kebab-case), string slices (`[]const u8`), and optionals (`?T`).
  - Automatic fallback to struct default values.
- 📖 **Automatic Help & Man Page Formatter (`zcli.formatHelp`)**:
  - Clean formatted CLI help listing descriptions, commands, options, defaults, and env vars.
- 🐚 **Dynamic Shell Completion Generation**:
  - **Bash (`zcli.generateBash`)**
  - **Zsh (`zcli.generateZsh`)**
  - **Fish (`zcli.generateFish`)**
- 📦 **Pure Zig 0.16.0+**: Zero C dependencies, instant build times, fully cross-compilable.

---

## Installation (`build.zig.zon`)

Add `zcli` to your `build.zig.zon`:

```bash
zig fetch --save https://github.com/entropyparadox-lab/zcli/archive/refs/tags/v1.0.0.tar.gz
```

In your `build.zig`:

```zig
const zcli_dep = b.dependency("zcli", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zcli", zcli_dep.module("zcli"));
```

---

## Quickstart

### 1. Basic Struct CLI

```zig
const std = @import("std");
const zcli = @import("zcli");

const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    verbose: bool = false,
    workers: ?u32 = null,
    log_level: enum { debug, info, warn, err } = .info,

    pub const zcli = .{
        .name = "my-server",
        .version = "1.0.0",
        .description = "High performance HTTP backend",
        .short = .{
            .port = 'p',
            .host = 'h',
            .verbose = 'v',
            .workers = 'w',
        },
        .env = .{
            .port = "SERVER_PORT",
            .host = "SERVER_HOST",
        },
        .help = .{
            .host = "Bind interface address",
            .port = "Listening port",
            .verbose = "Enable debug logging",
            .workers = "Worker thread pool size",
            .log_level = "Logging verbosity",
        },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // Parse directly from std.process.Init (Zig 0.16.0+)
    const cfg = zcli.parseWithInit(ServerConfig, init, allocator) catch |err| switch (err) {
        error.HelpRequested => {
            var buf: [4096]u8 = undefined;
            var writer = zcli.help.BufferWriter.init(&buf);
            try zcli.formatHelp(ServerConfig, &writer, .{});
            std.debug.print("{s}\n", .{writer.getWritten()});
            return;
        },
        else => return err,
    };

    std.debug.print("Listening on {s}:{d} (verbose={})\n", .{ cfg.host, cfg.port, cfg.verbose });
}
```

### 2. Subcommands via Tagged Union

```zig
const std = @import("std");
const zcli = @import("zcli");

const ServerOpts = struct {
    port: u16 = 8080,
    pub const zcli = .{ .short = .{ .port = 'p' } };
};

const ClientOpts = struct {
    url: []const u8 = "http://localhost:8080",
    pub const zcli = .{ .short = .{ .url = 'u' } };
};

const AppCli = union(enum) {
    server: ServerOpts,
    client: ClientOpts,
    version: void,

    pub const zcli = .{
        .name = "app",
        .description = "Multi-subcommand application",
        .help = .{
            .server = "Run server daemon",
            .client = "Run client request",
            .version = "Print version info",
        },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const cmd = try zcli.parseWithInit(AppCli, init, allocator);

    switch (cmd) {
        .server => |s| std.debug.print("Starting server on port {d}\n", .{s.port}),
        .client => |c| std.debug.print("Connecting to {s}\n", .{c.url}),
        .version => std.debug.print("v1.0.0\n", .{}),
    }
}
```

---

## Generating Shell Completions

Generate completion scripts programmatically or via CLI build step:

```zig
// Bash
try zcli.generateBash(ServerConfig, "my-server", stdout);

// Zsh
try zcli.generateZsh(ServerConfig, "my-server", stdout);

// Fish
try zcli.generateFish(ServerConfig, "my-server", stdout);
```

---

## Running Tests & Benchmarks

```bash
# Run full unit & integration test suite
zig build test

# Run microbenchmark suite
zig build bench

# Run example binary
zig build run-example -- server -p 9000 --verbose
```

---

## License

MIT License (c) 2026 Entropy Paradox Lab
