const std = @import("std");

pub const meta = @import("meta.zig");
pub const parser = @import("parser.zig");
pub const help = @import("help.zig");
pub const completion = @import("completion.zig");

// --- Top Level Aliases ---
pub const parse = parser.parse;
pub const parseWithEnv = parser.parseWithEnv;
pub const parseWithOptions = parser.parseWithOptions;
pub const ParseOptions = parser.ParseOptions;
pub const ParseError = parser.ParseError;

pub const formatHelp = help.formatHelp;
pub const formatHelpAlloc = help.formatHelpAlloc;
pub const HelpOptions = help.HelpOptions;

pub const generateBash = completion.generateBash;
pub const generateZsh = completion.generateZsh;
pub const generateFish = completion.generateFish;

/// Parses CLI arguments directly from `std.process.Init` (Zig v0.16.0+).
pub fn parseWithInit(comptime T: type, init: std.process.Init, allocator: std.mem.Allocator) !T {
    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);

    var it = init.minimal.args.iterate();
    _ = it.next(); // Skip executable path argv[0]
    while (it.next()) |arg| {
        try args_list.append(allocator, std.mem.sliceTo(arg, 0));
    }

    return parseWithEnv(T, args_list.items, init.minimal.environ);
}

// --- End-to-End Test Suite ---

test "zcli: end-to-end declarative CLI with full feature matrix" {
    const testing = std.testing;

    const LogLevel = enum { debug, info, warn, err };

    const AppConfig = struct {
        port: u16 = 8080,
        host: []const u8 = "127.0.0.1",
        verbose: bool = false,
        workers: ?u32 = null,
        log_level: LogLevel = .info,
        output_format: []const u8 = "json",
        dry_run: bool = false,
        timeout_sec: f64 = 30.0,

        pub const zcli = .{
            .name = "entropy-srv",
            .version = "1.0.0",
            .description = "Enterprise-grade async server",
            .short = .{
                .port = 'p',
                .host = 'h',
                .verbose = 'v',
                .workers = 'w',
                .dry_run = 'd',
                .output_format = 'o',
            },
            .env = .{
                .port = "SERVER_PORT",
                .host = "SERVER_HOST",
            },
            .help = .{
                .port = "Listening port",
                .host = "Bind host",
                .verbose = "Enable debug logging",
                .workers = "Worker count",
                .log_level = "Logging level",
                .output_format = "Log output format",
                .dry_run = "Perform dry run without listening",
                .timeout_sec = "Connection timeout in seconds",
            },
        };
    };

    // 1. Basic parsing with short options and clustered bools
    {
        const args = [_][]const u8{
            "-vd",
            "-p",
            "9099",
            "--host=0.0.0.0",
            "-w16",
            "--log-level",
            "debug",
            "--timeout-sec=45.5",
        };
        const cfg = try parse(AppConfig, &args);
        try testing.expectEqual(@as(u16, 9099), cfg.port);
        try testing.expectEqualStrings("0.0.0.0", cfg.host);
        try testing.expect(cfg.verbose);
        try testing.expect(cfg.dry_run);
        try testing.expectEqual(@as(?u32, 16), cfg.workers);
        try testing.expectEqual(LogLevel.debug, cfg.log_level);
        try testing.expectEqual(@as(f64, 45.5), cfg.timeout_sec);
    }

    // 2. Help generation
    {
        var buf: [4096]u8 = undefined;
        var writer = help.BufferWriter.init(&buf);
        try formatHelp(AppConfig, &writer, .{});
        const help_text = writer.getWritten();
        try testing.expect(std.mem.indexOf(u8, help_text, "Enterprise-grade async server") != null);
        try testing.expect(std.mem.indexOf(u8, help_text, "-p, --port <int>") != null);
        try testing.expect(std.mem.indexOf(u8, help_text, "-d, --dry-run") != null);
        try testing.expect(std.mem.indexOf(u8, help_text, "[env: SERVER_PORT]") != null);
    }

    // 3. Shell completions
    {
        var buf: [4096]u8 = undefined;
        var writer = help.BufferWriter.init(&buf);
        try generateBash(AppConfig, "entropy-srv", &writer);
        const bash_code = writer.getWritten();
        try testing.expect(std.mem.indexOf(u8, bash_code, "_entropy-srv_completion()") != null);
        try testing.expect(std.mem.indexOf(u8, bash_code, "--dry-run") != null);
    }
}

test "zcli: complex nested subcommand routing" {
    const testing = std.testing;

    const DbMigrateOpts = struct {
        target_version: ?u32 = null,
        dry_run: bool = false,

        pub const zcli = .{
            .short = .{ .dry_run = 'd', .target_version = 't' },
        };
    };

    const DbSeedOpts = struct {
        count: u32 = 100,
        fake_users: bool = true,
    };

    const DatabaseCmd = union(enum) {
        migrate: DbMigrateOpts,
        seed: DbSeedOpts,
        status: void,
    };

    const RootCli = union(enum) {
        db: DatabaseCmd,
        version: void,
    };

    // Parse nested subcommand: db migrate -d -t 42
    const args = [_][]const u8{ "db", "migrate", "-d", "-t", "42" };
    const parsed_root = try parse(RootCli, &args);

    switch (parsed_root) {
        .db => |db_sub| {
            switch (db_sub) {
                .migrate => |m| {
                    try testing.expect(m.dry_run);
                    try testing.expectEqual(@as(?u32, 42), m.target_version);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}
