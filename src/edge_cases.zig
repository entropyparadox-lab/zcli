const std = @import("std");
const zcli = @import("root.zig");
const testing = std.testing;

// ============================================================================
// 1. Help and Version Flag Interceptions
// ============================================================================

test "zcli: help and version requested returns exact error" {
    const SimpleConfig = struct {
        port: u16 = 8080,
        pub const zcli = .{
            .name = "test-cli",
            .version = "1.2.3",
            .short = .{ .port = 'p' },
        };
    };

    // Long help
    const h1 = [_][]const u8{"--help"};
    try testing.expectError(error.HelpRequested, zcli.parse(SimpleConfig, &h1));

    // Short help
    const h2 = [_][]const u8{"-h"};
    try testing.expectError(error.HelpRequested, zcli.parse(SimpleConfig, &h2));

    // Long version
    const v1 = [_][]const u8{"--version"};
    try testing.expectError(error.VersionRequested, zcli.parse(SimpleConfig, &v1));

    // Short version
    const v2 = [_][]const u8{"-V"};
    try testing.expectError(error.VersionRequested, zcli.parse(SimpleConfig, &v2));
}

// ============================================================================
// 2. Missing & Invalid Values
// ============================================================================

test "zcli: missing flag value returns error" {
    const ServerConfig = struct {
        port: u16 = 8080,
        host: []const u8 = "127.0.0.1",
        pub const zcli = .{
            .short = .{ .port = 'p' },
        };
    };

    // Missing value at end of arguments
    const a1 = [_][]const u8{"--port"};
    try testing.expectError(error.MissingOptionValue, zcli.parse(ServerConfig, &a1));

    const a2 = [_][]const u8{"-p"};
    try testing.expectError(error.MissingOptionValue, zcli.parse(ServerConfig, &a2));
}

test "zcli: invalid type conversions return specific errors" {
    const TypedConfig = struct {
        port: u16 = 8080,
        ratio: f64 = 1.0,
        mode: enum { fast, safe } = .safe,
    };

    // Invalid int
    const a1 = [_][]const u8{ "--port", "not_a_number" };
    try testing.expectError(error.InvalidArgument, zcli.parse(TypedConfig, &a1));

    // Invalid float
    const a2 = [_][]const u8{ "--ratio", "invalid_float" };
    try testing.expectError(error.InvalidArgument, zcli.parse(TypedConfig, &a2));

    // Invalid enum
    const a3 = [_][]const u8{ "--mode", "unknown_mode" };
    try testing.expectError(error.InvalidArgument, zcli.parse(TypedConfig, &a3));
}

test "zcli: clustered boolean short flags" {
    const FlagConfig = struct {
        all: bool = false,
        long: bool = false,
        human: bool = false,
        pub const zcli = .{
            .short = .{
                .all = 'a',
                .long = 'l',
                .human = 'h',
            },
        };
    };

    const args = [_][]const u8{"-al"};
    const parsed = try zcli.parse(FlagConfig, &args);
    try testing.expect(parsed.all);
    try testing.expect(parsed.long);
    try testing.expect(!parsed.human);
}

test "zcli: unknown option returns error" {
    const SimpleConfig = struct {
        id: u32 = 1,
    };

    const args = [_][]const u8{"--unrecognized-flag"};
    try testing.expectError(error.UnknownOption, zcli.parse(SimpleConfig, &args));
}
