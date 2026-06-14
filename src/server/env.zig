const std = @import("std");

// Spotify credentials are read from the process environment at runtime (env vars
// `client_id` / `client_secret`), not baked in at compile time. This keeps the
// secret out of the repo and the built image: it is injected by the host (e.g.
// Render env vars) and read by the loaded .so via the host process environment.
// For local dev, export them (e.g. `set -a; . .env; set +a`) before running.
pub fn clientId(a: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(a, "client_id");
}

pub fn clientSecret(a: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(a, "client_secret");
}
