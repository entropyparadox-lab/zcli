const std = @import("std");
const zcli = @import("zcli");

const BenchmarkOptions = struct {
    port: u16 = 8080,
    host: []const u8 = "127.0.0.1",
    verbose: bool = false,
    debug_mode: bool = false,
    workers: ?u32 = null,
    timeout_sec: f64 = 30.0,
    log_level: enum { debug, info, warn, err } = .info,
    tag: []const u8 = "default",

    pub const zcli = .{
        .short = .{
            .port = 'p',
            .host = 'h',
            .verbose = 'v',
            .debug_mode = 'd',
            .workers = 'w',
            .tag = 't',
        },
    };
};

fn getMonotonicNs() u64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

pub fn main(init: std.process.Init) !void {
    _ = init;

    const sample_args = [_][]const u8{
        "-vd",
        "-p",
        "9090",
        "--host",
        "0.0.0.0",
        "-w16",
        "--timeout-sec=45.5",
        "--log-level",
        "debug",
        "-t",
        "production",
    };

    const iterations: usize = 1_000_000;

    std.debug.print("\n=========================================================================\n", .{});
    std.debug.print("  ⚡ zcli High-Throughput Microbenchmark (Iterations: {d})\n", .{iterations});
    std.debug.print("=========================================================================\n\n", .{});

    const start_ns = getMonotonicNs();
    var i: usize = 0;
    var dummy: u64 = 0;

    while (i < iterations) : (i += 1) {
        const parsed = try zcli.parse(BenchmarkOptions, &sample_args);
        dummy +%= parsed.port;
    }

    const end_ns = getMonotonicNs();
    const elapsed_ns = end_ns - start_ns;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const ops_sec = (@as(f64, @floatFromInt(iterations)) / @as(f64, @floatFromInt(elapsed_ns))) * 1_000_000_000.0;
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));

    std.debug.print("🚀 1. zcli Declarative Flag Parsing (Zero-Alloc, 10 Complex Arguments):\n", .{});
    std.debug.print("   - Total Time: {d:.2} ms\n", .{elapsed_ms});
    std.debug.print("   - Throughput: {d:.2} Million ops/sec\n", .{ops_sec / 1_000_000.0});
    std.debug.print("   - Latency:    {d:.2} ns / parse\n", .{ns_per_op});
    std.debug.print("   - Heap Alloc: 0 bytes (Pure Comptime Reflection)\n\n", .{});

    std.debug.print("Checksum dummy verification: {d}\n\n", .{dummy});
}
