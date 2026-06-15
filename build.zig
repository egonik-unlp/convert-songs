const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .cpu_model = .baseline,
    } });

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "convert-songs",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        // Link libc so env reads use libc's `environ`. This .so is dlopen'd by a
        // non-Zig (Rust) host, so Zig's `std.start` never runs and `std.os.environ`
        // stays empty — without libc, getEnvVarOwned() always returns
        // EnvironmentVariableNotFound even when the var is set in the process env.
        .link_libc = true,
    });
    const lib = b.addLibrary(.{
        .name = "convert-rs",
        .linkage = .dynamic,
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // Dependencies
    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    const envfiles_dep = b.dependency("envfiles", .{ .target = target, .optimize = optimize });
    const envfiles_mod = envfiles_dep.module("envfiles");
    exe.root_module.addImport("envfiles", envfiles_mod);

    const httpz_dep = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const httpz_mod = httpz_dep.module("httpz");
    exe.root_module.addImport("httpz", httpz_mod);

    // Local modules
    const album = b.addModule("album", .{ .root_source_file = b.path("src/deserialize/album.zig") });
    exe.root_module.addImport("album", album);

    const track = b.addModule("track", .{ .root_source_file = b.path("src/deserialize/track.zig") });
    exe.root_module.addImport("track", track);
    lib_mod.addImport("track", track);

    const file_extractor = b.addModule("file-extractor", .{ .root_source_file = b.path("src/walker/file_extractor.zig") });
    exe.root_module.addImport("file-extractor", file_extractor);

    const playlist = b.addModule("playlist", .{ .root_source_file = b.path("src/deserialize/playlist.zig") });
    exe.root_module.addImport("playlist", playlist);
    playlist.addImport("track", track);
    lib_mod.addImport("playlist", playlist);

    const spotify_token = b.addModule("spotify-token", .{ .root_source_file = b.path("src/spotify_token.zig") });
    exe.root_module.addImport("spotify-token", spotify_token);
    spotify_token.addImport("envfiles", envfiles_mod);
    track.addImport("spotify-token", spotify_token);
    playlist.addImport("spotify-token", spotify_token);
    lib_mod.addImport("spotify-token", spotify_token);

    const server = b.addModule("server", .{ .root_source_file = b.path("src/server/server.zig") });
    exe.root_module.addImport("server", server);
    server.addImport("httpz", httpz_mod);

    // Build options: `zig build -Dremote=true` compiles for the remote site.
    const remote = b.option(bool, "remote", "Compile project for usage in remote site") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "remote_compile", remote);
    server.addOptions("compilation_options", options);

    // Run step: `zig build run -- arg1 arg2 etc`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
