const std = @import("std");
const meta = @import("meta.zig");

pub const ParseError = error{
    MissingRequiredOption,
    MissingOptionValue,
    InvalidArgument,
    UnknownOption,
    UnknownSubcommand,
    MissingSubcommand,
    HelpRequested,
    VersionRequested,
    TooManyPositionalArguments,
    EnvironmentVariableError,
};

/// Options configuring the parser behavior.
pub const ParseOptions = struct {
    allow_unknown: bool = false,
    stop_at_first_positional: bool = false,
};

/// Parse CLI arguments into type T without heap allocations.
pub fn parse(comptime T: type, args: []const []const u8) ParseError!T {
    return parseWithOptions(T, args, null, .{});
}

/// Parse CLI arguments into type T with environment fallback.
pub fn parseWithEnv(
    comptime T: type,
    args: []const []const u8,
    environ: ?std.process.Environ,
) ParseError!T {
    return parseWithOptions(T, args, environ, .{});
}

/// Parse CLI arguments into type T with custom options and optional environment.
pub fn parseWithOptions(
    comptime T: type,
    args: []const []const u8,
    environ: ?std.process.Environ,
    options: ParseOptions,
) ParseError!T {
    if (comptime meta.isTaggedUnion(T)) {
        return parseSubcommand(T, args, environ, options);
    } else if (comptime meta.isStruct(T)) {
        return parseStruct(T, args, environ, options);
    } else {
        @compileError("zcli.parse expects a struct or tagged union type, found " ++ @typeName(T));
    }
}

/// Initializes default struct field values.
pub fn initDefaults(comptime T: type) T {
    const fields = @typeInfo(T).@"struct".fields;
    var res: T = undefined;
    inline for (fields) |f| {
        if (f.default_value_ptr) |ptr| {
            const typed_ptr: *const f.type = @ptrCast(@alignCast(ptr));
            @field(res, f.name) = typed_ptr.*;
        } else if (@typeInfo(f.type) == .optional) {
            @field(res, f.name) = null;
        }
    }
    return res;
}

/// Parses a tagged union subcommand tree.
fn parseSubcommand(
    comptime T: type,
    args: []const []const u8,
    environ: ?std.process.Environ,
    options: ParseOptions,
) ParseError!T {
    _ = options;
    if (args.len == 0) {
        return error.MissingSubcommand;
    }

    const first_arg = args[0];

    // Check for help/version on top-level
    if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
        return error.HelpRequested;
    }
    if (std.mem.eql(u8, first_arg, "--version") or std.mem.eql(u8, first_arg, "-V")) {
        return error.VersionRequested;
    }

    const u_info = @typeInfo(T).@"union";
    const sub_args = args[1..];

    inline for (u_info.fields) |u_field| {
        const matches_name = std.mem.eql(u8, u_field.name, first_arg) or
            std.mem.eql(u8, meta.toKebabCase(u_field.name), first_arg);

        if (matches_name) {
            if (u_field.type == void) {
                return @unionInit(T, u_field.name, {});
            } else if (comptime meta.isStruct(u_field.type)) {
                const sub_val = try parseStruct(u_field.type, sub_args, environ, .{});
                return @unionInit(T, u_field.name, sub_val);
            } else if (comptime meta.isTaggedUnion(u_field.type)) {
                const sub_val = try parseSubcommand(u_field.type, sub_args, environ, .{});
                return @unionInit(T, u_field.name, sub_val);
            } else {
                @compileError("Union variant payload must be a struct, tagged union, or void");
            }
        }
    }

    return error.UnknownSubcommand;
}

/// Parses a struct with zero allocations.
fn parseStruct(
    comptime T: type,
    args: []const []const u8,
    environ: ?std.process.Environ,
    options: ParseOptions,
) ParseError!T {
    const struct_fields = @typeInfo(T).@"struct".fields;
    var result = initDefaults(T);
    var is_set = [_]bool{false} ** struct_fields.len;

    // Determine positional vs non-positional fields
    const positional_fields = comptime blk: {
        var count: usize = 0;
        for (struct_fields) |f| {
            if (meta.isPositionalField(T, f.name)) count += 1;
        }
        break :blk count;
    };

    var positional_idx: usize = 0;
    var end_of_options = false;
    var arg_idx: usize = 0;

    while (arg_idx < args.len) : (arg_idx += 1) {
        const arg = args[arg_idx];

        if (end_of_options) {
            try assignPositional(T, &result, &is_set, arg, &positional_idx, positional_fields);
            continue;
        }

        if (std.mem.eql(u8, arg, "--")) {
            end_of_options = true;
            continue;
        }

        // Check for help/version flags
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.HelpRequested;
        }
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
            return error.VersionRequested;
        }

        // Long option: --flag or --flag=value or --no-flag
        if (std.mem.startsWith(u8, arg, "--")) {
            const raw_flag = arg[2..];
            if (raw_flag.len == 0) continue;

            var flag_name = raw_flag;
            var inline_value: ?[]const u8 = null;

            if (std.mem.indexOfScalar(u8, raw_flag, '=')) |eq_pos| {
                flag_name = raw_flag[0..eq_pos];
                inline_value = raw_flag[eq_pos + 1 ..];
            }

            var matched = false;

            // Check for negative boolean flag (--no-feature)
            const is_no_prefix = std.mem.startsWith(u8, flag_name, "no-") or std.mem.startsWith(u8, flag_name, "no_");
            const inverted_name = if (is_no_prefix) flag_name[3..] else null;

            inline for (struct_fields, 0..) |f, f_idx| {
                const FieldType = f.type;
                const matches_positive = meta.fieldNameMatches(f.name, flag_name);
                const matches_negative = if (inverted_name) |inv| meta.fieldNameMatches(f.name, inv) else false;

                if (matches_positive or matches_negative) {
                    matched = true;
                    if (comptime meta.isBool(FieldType)) {
                        if (matches_negative) {
                            @field(result, f.name) = false;
                        } else if (inline_value) |inv_val| {
                            @field(result, f.name) = try parseBool(inv_val);
                        } else {
                            @field(result, f.name) = true;
                        }
                        is_set[f_idx] = true;
                    } else {
                        if (matches_negative) {
                            return error.InvalidArgument;
                        }
                        const value_str = if (inline_value) |iv| iv else blk: {
                            arg_idx += 1;
                            if (arg_idx >= args.len) {
                                return error.MissingOptionValue;
                            }
                            break :blk args[arg_idx];
                        };

                        @field(result, f.name) = try parseValue(FieldType, value_str);
                        is_set[f_idx] = true;
                    }
                }
            }

            if (!matched) {
                if (!options.allow_unknown) {
                    return error.UnknownOption;
                }
            }
        }
        // Short option: -f or -f=value or -fvalue or clustered booleans -xvf
        else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
            const short_slice = arg[1..];
            var matched = false;

            var char_idx: usize = 0;
            while (char_idx < short_slice.len) {
                const ch = short_slice[char_idx];
                var char_matched = false;

                inline for (struct_fields, 0..) |f, f_idx| {
                    const short_char = comptime meta.getShortChar(T, f.name);
                    if (short_char) |sc| {
                        if (sc == ch) {
                            char_matched = true;
                            matched = true;
                            const FieldType = f.type;

                            if (comptime meta.isBool(FieldType)) {
                                @field(result, f.name) = true;
                                is_set[f_idx] = true;
                                char_idx += 1;
                            } else {
                                // Non-boolean takes the remainder of the short slice or next arg
                                const remainder = short_slice[char_idx + 1 ..];
                                if (remainder.len > 0) {
                                    const clean_val = if (std.mem.startsWith(u8, remainder, "="))
                                        remainder[1..]
                                    else
                                        remainder;
                                    @field(result, f.name) = try parseValue(FieldType, clean_val);
                                    is_set[f_idx] = true;
                                    char_idx = short_slice.len; // consumed all
                                } else {
                                    arg_idx += 1;
                                    if (arg_idx >= args.len) {
                                        return error.MissingOptionValue;
                                    }
                                    @field(result, f.name) = try parseValue(FieldType, args[arg_idx]);
                                    is_set[f_idx] = true;
                                    char_idx = short_slice.len;
                                }
                            }
                        }
                    }
                }

                if (!char_matched) {
                    if (!options.allow_unknown) {
                        return error.UnknownOption;
                    }
                    char_idx += 1;
                }
            }
        }
        // Positional argument
        else {
            try assignPositional(T, &result, &is_set, arg, &positional_idx, positional_fields);
        }
    }

    // Check environment variables for unset fields
    if (environ) |env| {
        inline for (struct_fields, 0..) |f, f_idx| {
            if (!is_set[f_idx]) {
                const env_var = comptime meta.getEnvVarName(T, f.name);
                if (env_var) |env_key| {
                    if (env.getPosix(env_key)) |val| {
                        @field(result, f.name) = try parseValue(f.type, val);
                        is_set[f_idx] = true;
                    }
                }
            }
        }
    }

    // Check required fields
    inline for (struct_fields, 0..) |f, f_idx| {
        if (!is_set[f_idx]) {
            if (f.default_value_ptr == null and !meta.isOptional(f.type)) {
                return error.MissingRequiredOption;
            }
        }
    }

    return result;
}

/// Assigns a positional argument to the next available positional field.
fn assignPositional(
    comptime T: type,
    result: *T,
    is_set: anytype,
    arg: []const u8,
    positional_idx: *usize,
    comptime positional_count: usize,
) ParseError!void {
    const struct_fields = @typeInfo(T).@"struct".fields;
    var current_pos: usize = 0;

    inline for (struct_fields, 0..) |f, f_idx| {
        const is_explicit_pos = comptime meta.isPositionalField(T, f.name);
        const is_implicit_pos = comptime (positional_count == 0 and meta.isString(f.type) and !meta.hasDefault(f));

        if (is_explicit_pos or is_implicit_pos) {
            if (current_pos == positional_idx.*) {
                @field(result.*, f.name) = try parseValue(f.type, arg);
                is_set[f_idx] = true;
                positional_idx.* += 1;
                return;
            }
            current_pos += 1;
        }
    }

    return error.TooManyPositionalArguments;
}

/// Parses a boolean from string.
fn parseBool(str: []const u8) ParseError!bool {
    if (std.mem.eql(u8, str, "true") or std.mem.eql(u8, str, "1") or std.mem.eql(u8, str, "yes")) {
        return true;
    } else if (std.mem.eql(u8, str, "false") or std.mem.eql(u8, str, "0") or std.mem.eql(u8, str, "no")) {
        return false;
    }
    return error.InvalidArgument;
}

/// Parses a string representation into typed value T.
fn parseValue(comptime T: type, str: []const u8) ParseError!T {
    if (comptime meta.isOptional(T)) {
        const Inner = meta.ChildType(T);
        return try parseValue(Inner, str);
    }

    if (comptime meta.isString(T)) {
        return str;
    }

    if (comptime meta.isBool(T)) {
        return try parseBool(str);
    }

    if (comptime meta.isInt(T)) {
        return std.fmt.parseInt(T, str, 10) catch error.InvalidArgument;
    }

    if (comptime meta.isFloat(T)) {
        return std.fmt.parseFloat(T, str) catch error.InvalidArgument;
    }

    if (comptime meta.isEnum(T)) {
        const enum_fields = @typeInfo(T).@"enum".fields;
        inline for (enum_fields) |ef| {
            if (std.mem.eql(u8, ef.name, str) or
                std.mem.eql(u8, meta.toKebabCase(ef.name), str))
            {
                return @enumFromInt(ef.value);
            }
        }
        return error.InvalidArgument;
    }

    @compileError("Unsupported CLI option type: " ++ @typeName(T));
}

// --- Comprehensive Unit Tests ---

test "parser: basic flags, options, defaults, and optionals" {
    const testing = std.testing;

    const ServerConfig = struct {
        port: u16 = 8080,
        host: []const u8 = "127.0.0.1",
        verbose: bool = false,
        workers: ?u32 = null,
        log_level: enum { debug, info, warn, err } = .info,

        pub const zcli = .{
            .short = .{
                .port = 'p',
                .host = 'h',
                .verbose = 'v',
                .workers = 'w',
            },
        };
    };

    // 1. Defaults
    {
        const args = [_][]const u8{};
        const cfg = try parse(ServerConfig, &args);
        try testing.expectEqual(@as(u16, 8080), cfg.port);
        try testing.expectEqualStrings("127.0.0.1", cfg.host);
        try testing.expectEqual(false, cfg.verbose);
        try testing.expectEqual(@as(?u32, null), cfg.workers);
        try testing.expectEqual(.info, cfg.log_level);
    }

    // 2. Overrides via long flags and inline equals
    {
        const args = [_][]const u8{
            "--port=9090",
            "--host",
            "0.0.0.0",
            "--verbose",
            "--workers=8",
            "--log-level",
            "debug",
        };
        const cfg = try parse(ServerConfig, &args);
        try testing.expectEqual(@as(u16, 9090), cfg.port);
        try testing.expectEqualStrings("0.0.0.0", cfg.host);
        try testing.expectEqual(true, cfg.verbose);
        try testing.expectEqual(@as(?u32, 8), cfg.workers);
        try testing.expectEqual(.debug, cfg.log_level);
    }

    // 3. Short flags and attached values
    {
        const args = [_][]const u8{
            "-p", "3000",
            "-hlocalhost",
            "-v",
            "-w4",
        };
        const cfg = try parse(ServerConfig, &args);
        try testing.expectEqual(@as(u16, 3000), cfg.port);
        try testing.expectEqualStrings("localhost", cfg.host);
        try testing.expectEqual(true, cfg.verbose);
        try testing.expectEqual(@as(?u32, 4), cfg.workers);
    }

    // 4. Clustered boolean flags with value at end
    {
        const Clustered = struct {
            all: bool = false,
            force: bool = false,
            verbose: bool = false,
            port: u16 = 80,

            pub const zcli = .{
                .short = .{
                    .all = 'a',
                    .force = 'f',
                    .verbose = 'v',
                    .port = 'p',
                },
            };
        };

        const args = [_][]const u8{ "-afvp", "8088" };
        const res = try parse(Clustered, &args);
        try testing.expect(res.all);
        try testing.expect(res.force);
        try testing.expect(res.verbose);
        try testing.expectEqual(@as(u16, 8088), res.port);
    }
}

test "parser: negative booleans (--no-verbose)" {
    const testing = std.testing;

    const Config = struct {
        color: bool = true,
        debug_mode: bool = true,
    };

    const args = [_][]const u8{ "--no-color", "--no_debug_mode" };
    const cfg = try parse(Config, &args);
    try testing.expectEqual(false, cfg.color);
    try testing.expectEqual(false, cfg.debug_mode);
}

test "parser: positional arguments and end-of-options delimiter (--)" {
    const testing = std.testing;

    const CopyCmd = struct {
        source: []const u8,
        destination: []const u8,
        recursive: bool = false,

        pub const zcli = .{
            .short = .{ .recursive = 'r' },
            .positional = .{ .source = true, .destination = true },
        };
    };

    const args = [_][]const u8{ "-r", "--", "file1.txt", "-not-a-flag.txt" };
    const cmd = try parse(CopyCmd, &args);
    try testing.expect(cmd.recursive);
    try testing.expectEqualStrings("file1.txt", cmd.source);
    try testing.expectEqualStrings("-not-a-flag.txt", cmd.destination);
}

test "parser: subcommands via tagged union" {
    const testing = std.testing;

    const RunOpts = struct {
        release: bool = false,
        bin: []const u8 = "main",

        pub const zcli = .{
            .short = .{ .release = 'r' },
        };
    };

    const TestOpts = struct {
        filter: ?[]const u8 = null,
        fail_fast: bool = false,
    };

    const CargoCli = union(enum) {
        run: RunOpts,
        @"test": TestOpts,
        clean: void,
    };

    // 1. Run subcommand
    {
        const args = [_][]const u8{ "run", "-r", "--bin", "server" };
        const cli = try parse(CargoCli, &args);
        switch (cli) {
            .run => |r| {
                try testing.expect(r.release);
                try testing.expectEqualStrings("server", r.bin);
            },
            else => return error.TestUnexpectedResult,
        }
    }

    // 2. Test subcommand with kebab-case
    {
        const args = [_][]const u8{ "test", "--filter", "math", "--fail-fast" };
        const cli = try parse(CargoCli, &args);
        switch (cli) {
            .@"test" => |t| {
                try testing.expectEqualStrings("math", t.filter.?);
                try testing.expect(t.fail_fast);
            },
            else => return error.TestUnexpectedResult,
        }
    }

    // 3. Void subcommand
    {
        const args = [_][]const u8{"clean"};
        const cli = try parse(CargoCli, &args);
        switch (cli) {
            .clean => {},
            else => return error.TestUnexpectedResult,
        }
    }
}
