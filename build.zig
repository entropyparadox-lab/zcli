const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Root module for library
    const zcli_mod = b.addModule("zcli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 2. Unit & Integration Tests using root_module
    const unit_tests = b.addTest(.{
        .root_module = zcli_mod,
    });

    const integration_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_mod.addImport("zcli", zcli_mod);

    const integration_tests = b.addTest(.{
        .root_module = integration_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run library unit and integration tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // 3. Examples executable using root_module
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("zcli", zcli_mod);

    const example_exe = b.addExecutable(.{
        .name = "zcli-example",
        .root_module = example_mod,
    });

    const run_example = b.addRunArtifact(example_exe);
    if (b.args) |args| {
        run_example.addArgs(args);
    }
    const example_step = b.step("run-example", "Run zcli example application");
    example_step.dependOn(&run_example.step);

    // 4. Benchmarking executable (ReleaseFast by default)
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("tests/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("zcli", zcli_mod);

    const bench_exe = b.addExecutable(.{
        .name = "zcli-bench",
        .root_module = bench_mod,
    });

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run zcli performance benchmark suite");
    bench_step.dependOn(&run_bench.step);
}
