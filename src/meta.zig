const std = @import("std");

/// Returns true if T is a string slice (`[]const u8`, `[:0]const u8`, `[]u8`, `[:0]u8`).
pub fn isString(comptime T: type) bool {
    const info = @typeInfo(T);
    switch (info) {
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                return true;
            }
        },
        else => {},
    }
    return false;
}

/// Returns true if T is an optional type (?T).
pub fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

/// Returns true if T is a tagged union (subcommand).
pub fn isTaggedUnion(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .@"union" and info.@"union".tag_type != null;
}

/// Returns true if T is a struct.
pub fn isStruct(comptime T: type) bool {
    return @typeInfo(T) == .@"struct";
}

/// Returns true if T is an enum.
pub fn isEnum(comptime T: type) bool {
    return @typeInfo(T) == .@"enum";
}

/// Returns true if T is a boolean.
pub fn isBool(comptime T: type) bool {
    return T == bool;
}

/// Returns true if T is an integer.
pub fn isInt(comptime T: type) bool {
    return @typeInfo(T) == .int;
}

/// Returns true if T is a float.
pub fn isFloat(comptime T: type) bool {
    return @typeInfo(T) == .float;
}

/// Unwraps optional type ?T to T.
pub fn ChildType(comptime T: type) type {
    if (isOptional(T)) {
        return @typeInfo(T).optional.child;
    }
    return T;
}

/// Converts snake_case identifier to kebab-case at comptime.
pub fn toKebabCase(comptime str: []const u8) []const u8 {
    const static = struct {
        const transformed = blk: {
            var buf: [str.len]u8 = undefined;
            for (str, 0..) |c, i| {
                if (c == '_') {
                    buf[i] = '-';
                } else {
                    buf[i] = c;
                }
            }
            break :blk buf;
        };
    };
    return &static.transformed;
}

/// Checks if string matches field name in either snake_case or kebab-case.
pub fn fieldNameMatches(comptime field_name: []const u8, name: []const u8) bool {
    if (std.mem.eql(u8, field_name, name)) return true;
    const kebab = toKebabCase(field_name);
    if (std.mem.eql(u8, kebab, name)) return true;
    return false;
}

/// Checks if T has `pub const zcli`.
pub fn hasZcliMeta(comptime T: type) bool {
    return @hasDecl(T, "zcli");
}

/// App-level metadata container.
pub const AppMeta = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    description: ?[]const u8 = null,
    author: ?[]const u8 = null,
};

/// Metadata accessor for struct-level fields (name, version, description, author).
pub fn getAppMeta(comptime T: type) AppMeta {
    if (!hasZcliMeta(T)) return .{};
    const meta = T.zcli;
    const MetaType = @TypeOf(meta);

    var res: AppMeta = .{};

    if (@hasField(MetaType, "name")) res.name = meta.name;
    if (@hasField(MetaType, "version")) res.version = meta.version;
    if (@hasField(MetaType, "description")) res.description = meta.description;
    if (@hasField(MetaType, "author")) res.author = meta.author;

    return res;
}

/// Retrieves short character for a specific field if defined in `zcli.short`.
pub fn getShortChar(comptime T: type, comptime field_name: []const u8) ?u8 {
    if (!hasZcliMeta(T)) return null;
    const meta = T.zcli;
    const MetaType = @TypeOf(meta);

    if (@hasField(MetaType, "short")) {
        const short_meta = meta.short;
        const ShortType = @TypeOf(short_meta);
        if (@hasField(ShortType, field_name)) {
            return @field(short_meta, field_name);
        }
    }
    return null;
}

/// Retrieves environment variable name for a specific field if defined in `zcli.env`.
pub fn getEnvVarName(comptime T: type, comptime field_name: []const u8) ?[]const u8 {
    if (!hasZcliMeta(T)) return null;
    const meta = T.zcli;
    const MetaType = @TypeOf(meta);

    if (@hasField(MetaType, "env")) {
        const env_meta = meta.env;
        const EnvType = @TypeOf(env_meta);
        if (@hasField(EnvType, field_name)) {
            return @field(env_meta, field_name);
        }
    }
    return null;
}

/// Retrieves help description for a specific field if defined in `zcli.help`.
pub fn getHelpText(comptime T: type, comptime field_name: []const u8) ?[]const u8 {
    if (!hasZcliMeta(T)) return null;
    const meta = T.zcli;
    const MetaType = @TypeOf(meta);

    if (@hasField(MetaType, "help")) {
        const help_meta = meta.help;
        const HelpType = @TypeOf(help_meta);
        if (@hasField(HelpType, field_name)) {
            return @field(help_meta, field_name);
        }
    }
    return null;
}

/// Checks if a field is explicitly marked as positional in `zcli.positional`.
pub fn isPositionalField(comptime T: type, comptime field_name: []const u8) bool {
    if (!hasZcliMeta(T)) return false;
    const meta = T.zcli;
    const MetaType = @TypeOf(meta);

    if (@hasField(MetaType, "positional")) {
        const pos_meta = meta.positional;
        const PosType = @TypeOf(pos_meta);
        if (@hasField(PosType, field_name)) {
            return @field(pos_meta, field_name);
        }
    }
    return false;
}

/// Checks if a field has a default value defined on the struct.
pub fn hasDefault(comptime field: std.builtin.Type.StructField) bool {
    return field.default_value_ptr != null;
}

/// Extracts the default value of a struct field at comptime.
pub fn getDefaultValue(comptime field: std.builtin.Type.StructField) field.type {
    if (field.default_value_ptr) |ptr| {
        const typed_ptr: *const field.type = @ptrCast(@alignCast(ptr));
        return typed_ptr.*;
    }
    unreachable;
}

// --- Unit Tests for Meta ---
test "meta: basic type predicates and metadata extractors" {
    const testing = std.testing;

    const Sample = struct {
        port: u16 = 8080,
        host: []const u8 = "0.0.0.0",
        verbose: bool = false,
        name: ?[]const u8 = null,

        pub const zcli = .{
            .name = "sample-app",
            .version = "1.2.0",
            .description = "A sample CLI tool",
            .short = .{ .port = 'p', .verbose = 'v', .host = 'h' },
            .env = .{ .port = "PORT", .host = "HOST" },
            .help = .{ .port = "Listening port", .host = "Bind host" },
        };
    };

    try testing.expect(isStruct(Sample));
    try testing.expect(isString([]const u8));
    try testing.expect(isBool(bool));
    try testing.expect(isInt(u16));
    try testing.expect(isOptional(?[]const u8));
    try testing.expectEqual(u16, ChildType(u16));
    try testing.expectEqual([]const u8, ChildType(?[]const u8));

    const app_meta = getAppMeta(Sample);
    try testing.expectEqualStrings("sample-app", app_meta.name.?);
    try testing.expectEqualStrings("1.2.0", app_meta.version.?);
    try testing.expectEqualStrings("A sample CLI tool", app_meta.description.?);

    try testing.expectEqual(@as(?u8, 'p'), getShortChar(Sample, "port"));
    try testing.expectEqual(@as(?u8, 'v'), getShortChar(Sample, "verbose"));
    try testing.expectEqualStrings("PORT", getEnvVarName(Sample, "port").?);
    try testing.expectEqualStrings("Listening port", getHelpText(Sample, "port").?);

    try testing.expect(fieldNameMatches("server_port", "server-port"));
    try testing.expect(fieldNameMatches("server_port", "server_port"));
}
