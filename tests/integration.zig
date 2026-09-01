const std = @import("std");
const zcli = @import("zcli");

test "integration: full CLI test suite" {
    const testing = std.testing;

    const App = struct {
        port: u16 = 8080,
        host: []const u8 = "127.0.0.1",
        verbose: bool = false,
        name: ?[]const u8 = null,

        pub const zcli = .{
            .name = "test-cli",
            .version = "1.0.0",
            .short = .{ .port = 'p', .verbose = 'v', .host = 'h', .name = 'n' },
        };
    };

    // Missing required
    const RequiredApp = struct {
        api_key: []const u8,
        port: u16,
    };

    {
        const args = [_][]const u8{ "--port", "8080" };
        try testing.expectError(error.MissingRequiredOption, zcli.parse(RequiredApp, &args));
    }

    // Missing value
    {
        const args = [_][]const u8{"--port"};
        try testing.expectError(error.MissingOptionValue, zcli.parse(RequiredApp, &args));
    }

    // Invalid argument
    {
        const args = [_][]const u8{ "--port", "invalid_num", "--api-key", "secret" };
        try testing.expectError(error.InvalidArgument, zcli.parse(RequiredApp, &args));
    }

    // Unknown option
    {
        const args = [_][]const u8{"--random-flag"};
        try testing.expectError(error.UnknownOption, zcli.parse(App, &args));
    }

    // Help requested
    {
        const args = [_][]const u8{"--help"};
        try testing.expectError(error.HelpRequested, zcli.parse(App, &args));
    }

    // Version requested
    {
        const args = [_][]const u8{"-V"};
        try testing.expectError(error.VersionRequested, zcli.parse(App, &args));
    }
}
