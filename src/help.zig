const std = @import("std");
const meta = @import("meta.zig");

pub const HelpOptions = struct {
    colors: bool = true,
    indent_spaces: usize = 2,
};

pub const BufferWriter = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn init(buf: []u8) BufferWriter {
        return .{ .buf = buf, .pos = 0 };
    }

    pub fn print(self: *BufferWriter, comptime fmt: []const u8, args: anytype) !void {
        const slice = self.buf[self.pos..];
        const written = std.fmt.bufPrint(slice, fmt, args) catch return error.NoSpaceLeft;
        self.pos += written.len;
    }

    pub fn writeAll(self: *BufferWriter, bytes: []const u8) !void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos .. self.pos + bytes.len], bytes);
        self.pos += bytes.len;
    }

    pub fn getWritten(self: *const BufferWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

/// Writes formatted CLI help text to a writer.
pub fn formatHelp(comptime T: type, writer: anytype, options: HelpOptions) !void {
    _ = options;
    const app_meta = meta.getAppMeta(T);
    const app_name = app_meta.name orelse "app";

    // 1. Header: Description / Version
    if (app_meta.description) |desc| {
        try writer.print("{s}\n\n", .{desc});
    }

    // 2. Usage
    if (comptime meta.isTaggedUnion(T)) {
        try writer.print("Usage: {s} <COMMAND> [OPTIONS]\n\n", .{app_name});
    } else {
        try writer.print("Usage: {s} [OPTIONS]", .{app_name});

        const struct_fields = @typeInfo(T).@"struct".fields;
        inline for (struct_fields) |f| {
            if (meta.isPositionalField(T, f.name)) {
                try writer.print(" <{s}>", .{meta.toKebabCase(f.name)});
            }
        }
        try writer.print("\n\n", .{});
    }

    // 3. Subcommands (if Tagged Union)
    if (comptime meta.isTaggedUnion(T)) {
        try writer.print("Commands:\n", .{});
        const u_fields = @typeInfo(T).@"union".fields;
        inline for (u_fields) |uf| {
            const cmd_name = meta.toKebabCase(uf.name);
            const help_text = meta.getHelpText(T, uf.name) orelse "";
            try writer.print("  {s: <16} {s}\n", .{ cmd_name, help_text });
        }
        try writer.print("\n", .{});
    }

    // 4. Options / Flags (if Struct)
    if (comptime meta.isStruct(T)) {
        const struct_fields = @typeInfo(T).@"struct".fields;

        // Check if there are positional fields
        var has_positional = false;
        inline for (struct_fields) |f| {
            if (meta.isPositionalField(T, f.name)) {
                has_positional = true;
            }
        }

        if (has_positional) {
            try writer.print("Arguments:\n", .{});
            inline for (struct_fields) |f| {
                if (meta.isPositionalField(T, f.name)) {
                    const arg_name = meta.toKebabCase(f.name);
                    const help_text = meta.getHelpText(T, f.name) orelse "";
                    try writer.print("  <{s: <14}> {s}\n", .{ arg_name, help_text });
                }
            }
            try writer.print("\n", .{});
        }

        try writer.print("Options:\n", .{});
        inline for (struct_fields) |f| {
            if (!meta.isPositionalField(T, f.name)) {
                const flag_name = meta.toKebabCase(f.name);
                const short_char = meta.getShortChar(T, f.name);
                const help_text = meta.getHelpText(T, f.name) orelse "";
                const env_var = meta.getEnvVarName(T, f.name);

                var flag_buf: [64]u8 = undefined;
                var fb = BufferWriter.init(&flag_buf);

                if (short_char) |sc| {
                    try fb.print("-{c}, ", .{sc});
                } else {
                    try fb.writeAll("    ");
                }

                if (meta.isBool(f.type)) {
                    try fb.print("--{s}", .{flag_name});
                } else {
                    const TypeName = typeNameHint(f.type);
                    try fb.print("--{s} <{s}>", .{ flag_name, TypeName });
                }

                const flag_str = fb.getWritten();

                try writer.print("  {s: <24} {s}", .{ flag_str, help_text });

                // Print default value & env var
                if (f.default_value_ptr) |ptr| {
                    _ = ptr;
                    if (!meta.isBool(f.type)) {
                        try writer.print(" [default: {any}]", .{meta.getDefaultValue(f)});
                    }
                }
                if (env_var) |ev| {
                    try writer.print(" [env: {s}]", .{ev});
                }

                try writer.print("\n", .{});
            }
        }

        // Standard flags
        try writer.print("  -h, --help               Print help information\n", .{});
        try writer.print("  -V, --version            Print version information\n", .{});
    }
}

/// Returns a human-friendly type name string.
fn typeNameHint(comptime T: type) []const u8 {
    if (meta.isOptional(T)) {
        return typeNameHint(meta.ChildType(T));
    }
    if (meta.isString(T)) return "string";
    if (meta.isBool(T)) return "bool";
    if (meta.isInt(T)) return "int";
    if (meta.isFloat(T)) return "float";
    if (meta.isEnum(T)) return "enum";
    return @typeName(T);
}

// --- Unit Tests for Help ---
test "help: format help for struct" {
    const testing = std.testing;

    const ServerConfig = struct {
        port: u16 = 8080,
        host: []const u8 = "127.0.0.1",
        verbose: bool = false,

        pub const zcli = .{
            .name = "my-server",
            .description = "Lightning fast HTTP daemon",
            .short = .{ .port = 'p', .verbose = 'v', .host = 'h' },
            .env = .{ .port = "SERVER_PORT" },
            .help = .{
                .port = "Port to listen on",
                .host = "Bind interface",
                .verbose = "Enable debug logs",
            },
        };
    };

    var buf: [2048]u8 = undefined;
    var writer = BufferWriter.init(&buf);
    try formatHelp(ServerConfig, &writer, .{});

    const output = writer.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "Lightning fast HTTP daemon") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Usage: my-server [OPTIONS]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "-p, --port <int>") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[default: 8080]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[env: SERVER_PORT]") != null);
}
