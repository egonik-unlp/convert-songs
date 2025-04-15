const std = @import("std");
const InnerToken = struct { token: []const u8, expiration_timestamp: i64 };
const dumpfile = "dump.a";
const TokenTuple = std.meta.Tuple(&.{ []u8, i32 });
// const dotenv = @import("dotenv");
const envfiles = @import("envfiles");
const http = std.http;
const env_embedded = @embedFile(".env");
const SpotifyResponse = struct {
    access_token: []u8,
    token_type: []u8,
    expires_in: i32,
    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (fmt.len != 0) {
            std.fmt.invalidFmtError(fmt, self);
        }
        return writer.print("{s}\naccess_token: {s}\ntoken_type: {s}\nexpires_in: {d}\n", .{ @typeName(@TypeOf(self)), self.access_token, self.token_type, self.expires_in });
    }
};

pub const SerializedToken = struct {
    expiration_timestamp: i64,
    token: []const u8,
    arena: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) !SerializedToken {
        const filename = dumpfile;
        const cwd = std.fs.cwd();
        const file = cwd.openFile(filename, .{});
        const token, const expiration_timestamp = blk: {
            if (file) |value| {
                std.debug.print("Token file already exists\n", .{});
                const str = try value.readToEndAlloc(allocator, 4096);
                const token_data = try std.json.parseFromSlice(InnerToken, allocator, str, .{ .ignore_unknown_fields = true, .parse_numbers = true });

                defer value.close(); // Cierra el archivo abierto, dentro de este scope.
                std.debug.print("Retrieved token: {s}\n", .{token_data.value.token});
                break :blk .{ token_data.value.token, token_data.value.expiration_timestamp };
            } else |err| {
                switch (err) {
                    std.fs.File.OpenError.FileNotFound => {
                        std.debug.print("Token file does not exist\n", .{});
                        const token, const void_timestamp = try get_token(allocator);
                        const expiration_timestamp = void_timestamp + @divTrunc(std.time.milliTimestamp(), 1000);
                        const dump_data = InnerToken{ .expiration_timestamp = expiration_timestamp, .token = token };
                        const dumpu8 = try std.json.stringifyAlloc(allocator, dump_data, .{});
                        const filew = try std.fs.cwd().createFile(dumpfile, .{ .read = true });
                        try filew.writeAll(dumpu8);
                        defer filew.close();
                        break :blk .{ token, expiration_timestamp };
                    },

                    else => return err,
                }
            }
        };
        const ret = SerializedToken{ .expiration_timestamp = expiration_timestamp, .token = token, .arena = allocator };
        return ret;
    }
    pub fn update(self: *SerializedToken) !void {
        const token, const void_timestamp = try get_token(self.arena);
        const expiration_timestamp = void_timestamp + @divTrunc(std.time.milliTimestamp(), 1000);
        self.expiration_timestamp = expiration_timestamp;
        self.token = token;
        const dump_data = InnerToken{ .expiration_timestamp = expiration_timestamp, .token = token };
        const dumpu8 = try std.json.stringifyAlloc(self.arena, dump_data, .{});
        const file = try std.fs.cwd().openFile(dumpfile, .{ .mode = .read_write });
        try file.writeAll(dumpu8);
        defer file.close();
    }
    pub fn retrieve(self: *SerializedToken) ![]const u8 {
        const current_timestamp = @divTrunc(std.time.milliTimestamp(), 1000);
        if (current_timestamp > self.expiration_timestamp) {
            std.debug.print("Current token is void. Updating token...\n", .{});
            try self.update();
            std.debug.print("Updates\n", .{});
        }
        return self.token;
    }
};
fn get_token(allo: std.mem.Allocator) !TokenTuple {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var local_arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer local_arena.deinit();
    const client_id, const client_secret = try get_dotenv(local_arena.allocator());
    var client = http.Client{ .allocator = local_arena.allocator() };
    const url = try std.Uri.parse("https://accounts.spotify.com/api/token");
    var buf: [4096]u8 = undefined;
    const headers = http.Client.Request.Headers{ .content_type = .{ .override = "application/x-www-form-urlencoded" } };
    const body = try std.fmt.allocPrint(local_arena.allocator(), "grant_type=client_credentials&client_id={s}&client_secret={s}", .{ client_id, client_secret });
    var response = std.ArrayList(u8).init(local_arena.allocator());
    const options = http.Client.FetchOptions{ .response_storage = .{ .dynamic = &response }, .method = .POST, .payload = body, .server_header_buffer = &buf, .headers = headers, .location = http.Client.FetchOptions.Location{ .uri = url } };
    _ = try client.fetch(options);
    const obj = try std.json.parseFromSlice(SpotifyResponse, allo, response.items, .{ .ignore_unknown_fields = true });
    const token = obj.value.access_token;
    const expiration = obj.value.expires_in;
    const ret: TokenTuple = .{ token, expiration };
    return ret;
}

fn get_dotenv(allocator: std.mem.Allocator) ![2][]const u8 {
    // const env = try envfiles.Env.init(".env", allocator);
    const env = try envfiles.Env.init_string(env_embedded, allocator);
    const client_id = try env.getVal("client_id");
    const client_secret = try env.getVal("client_secret");
    return .{ client_id, client_secret };
}
test "holds token" {
    const testing = std.testing.allocator;
    var local_arena = std.heap.ArenaAllocator.init(testing);
    defer local_arena.deinit();
    var token_wrapper = try SerializedToken.init(local_arena.allocator());
    const token1 = try token_wrapper.retrieve();
    var token_wrapper2 = try SerializedToken.init(local_arena.allocator());
    const token2 = try token_wrapper2.retrieve();
    std.debug.print("t1{s}\nt2{s}\n", .{ token1, token2 });
    try std.testing.expectEqualStrings(token1, token2);
}
test "gets token" {
    const testing = std.testing.allocator;
    var local_arena = std.heap.ArenaAllocator.init(testing);
    defer local_arena.deinit();
    var token_wrapper = try SerializedToken.init(local_arena.allocator());
    const token = try token_wrapper.retrieve();
    std.debug.print("{s}", .{token});
    try std.testing.expect(true);
}
