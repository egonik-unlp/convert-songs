const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .cpu_model = .baseline,
    } });

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // // Every executable or library we compile will be based on one or more modules.
    // const lib_mod = b.createModule(.{
    //     // `root_source_file` is the Zig "entry point" of the module. If a module
    //     // only contains e.g. external object files, you can make this `null`.
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    // exe_mod.addImport("convert-songs_lib", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "convert-songs",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));
    const envfiles_dep = b.dependency("envfiles", .{ .target = target, .optimize = optimize });
    const envfiles_mod = envfiles_dep.module("envfiles");
    exe.root_module.addImport("envfiles", envfiles_mod);
    const album = b.addModule("album", .{ .root_source_file = .{ .cwd_relative = "src/deserialize/album.zig" } });
    exe.root_module.addImport("album", album);
    const track = b.addModule("track", .{ .root_source_file = .{ .cwd_relative = "src/deserialize/track.zig" } });
    exe.root_module.addImport("track", track);
    const file_extractor = b.addModule("file-extractor", .{ .root_source_file = .{ .cwd_relative = "src/walker/file_extractor.zig" } });
    exe.root_module.addImport("file-extractor", file_extractor);
    const playlist = b.addModule("playlist", .{ .root_source_file = .{ .cwd_relative = "src/deserialize/playlist.zig" } });
    exe.root_module.addImport("playlist", playlist);
    playlist.addImport("track", track);
    const server = b.addModule("server", .{ .root_source_file = .{ .cwd_relative = "src/server/server.zig" } });

    const remote = b.option(bool, "remote", "compile project as a remote backend") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "remote", remote);
    server.addOptions("compile_settings", options);

    exe.root_module.addImport("server", server);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const spotify_token = b.addModule("spotify-token", .{ .root_source_file = .{ .cwd_relative = "src/spotify_token.zig" } });
    exe.root_module.addImport("spotify-token", spotify_token);
    spotify_token.addImport("envfiles", envfiles_mod);
    track.addImport("spotify-token", spotify_token);
    playlist.addImport("spotify-token", spotify_token);

    const compile_remote = b.option(bool, "remote", "Compile projectremote_compile for usage in remote site") orelse false;
    const options = b.addOptions();

    options.addOption(bool, "remote_compile", compile_remote);
    server.addOptions("compilation_options", options);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const httpz_depend = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const httpz_mod = httpz_depend.module("httpz");
    exe.root_module.addImport("httpz", httpz_mod);
    server.addImport("httpz", httpz_mod);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    // exe_unit_tests.root_module.addImport("dotenv", dotenv_mod);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_exe_unit_tests.step);
}
