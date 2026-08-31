const std = @import("std");
const zcli = @import("zcli");

const LogLevel = enum { debug, info, warn, err };

const ServerOptions = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    verbose: bool = false,
    workers: ?u32 = null,
    log_level: LogLevel = .info,

    pub const zcli = .{
        .name = "server",
        .description = "Start the HTTP API backend server",
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
            .host = "Bind address",
            .port = "Listening port",
            .verbose = "Enable debug logs",
            .workers = "Worker thread count",
            .log_level = "Logging verbosity",
        },
    };
};

const ClientOptions = struct {
    target: []const u8 = "http://127.0.0.1:8080",
    timeout_ms: u32 = 5000,
    insecure: bool = false,

    pub const zcli = .{
        .name = "client",
        .description = "Connect to a remote server",
        .short = .{ .target = 't', .insecure = 'k' },
        .help = .{
            .target = "Remote server URL",
            .timeout_ms = "Connection timeout in milliseconds",
            .insecure = "Allow insecure TLS connections",
        },
    };
};

const Cli = union(enum) {
    server: ServerOptions,
    client: ClientOptions,
    version: void,

    pub const zcli = .{
        .name = "entropy-cli",
        .version = "1.0.0",
        .description = "High-performance enterprise CLI toolkit",
        .help = .{
            .server = "Start the HTTP server",
            .client = "Run client request",
            .version = "Print version information",
        },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);

    var it = init.minimal.args.iterate();
    _ = it.next(); // Skip argv[0]
    while (it.next()) |arg| {
        try args_list.append(allocator, std.mem.sliceTo(arg, 0));
    }

    const command = zcli.parse(Cli, args_list.items) catch |err| switch (err) {
        error.HelpRequested => {
            var buf: [4096]u8 = undefined;
            var writer = zcli.help.BufferWriter.init(&buf);
            try zcli.formatHelp(Cli, &writer, .{});
            std.debug.print("{s}\n", .{writer.getWritten()});
            return;
        },
        error.VersionRequested => {
            std.debug.print("entropy-cli v1.0.0\n", .{});
            return;
        },
        error.MissingSubcommand => {
            std.debug.print("Error: Subcommand required. Run with --help for usage.\n", .{});
            return;
        },
        else => {
            std.debug.print("CLI Parsing Error: {any}\n", .{err});
            return;
        },
    };

    switch (command) {
        .server => |s| {
            std.debug.print("🚀 Starting Server on {s}:{d} (verbose: {}, workers: {any})\n", .{
                s.host,
                s.port,
                s.verbose,
                s.workers,
            });
        },
        .client => |c| {
            std.debug.print("📡 Connecting to {s} (timeout: {d}ms, insecure: {})\n", .{
                c.target,
                c.timeout_ms,
                c.insecure,
            });
        },
        .version => {
            std.debug.print("entropy-cli v1.0.0\n", .{});
        },
    }
}
