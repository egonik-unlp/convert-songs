const std = @import("std");
const http = std.http;
const fmt = std.fmt;
const dotenv = @import("dotenv");
const album_code = "06zWjeOA3MwBHLApKUS3Qs?si=LkxC6rN9QhmXiY67dQ6QYQ";
const SpotifyResponse = struct {
    access_token: []u8,
    token_type: []u8,
    expires_in: i32,
};

fn get_token(allo: std.mem.Allocator) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var local_arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer local_arena.deinit();
    const client_id, const client_secret = try get_dotenv(local_arena.allocator());
    var client = http.Client{ .allocator = local_arena.allocator() };
    const url = try std.Uri.parse("https://accounts.spotify.com/api/token");
    var buf: [4096]u8 = undefined;
    const headers = http.Client.Request.Headers{ .content_type = .{ .override = "application/x-www-form-urlencoded" } };
    const body = try fmt.allocPrint(local_arena.allocator(), "grant_type=client_credentials&client_id={s}&client_secret={s}", .{ client_id, client_secret });
    var response = std.ArrayList(u8).init(local_arena.allocator());
    const options = http.Client.FetchOptions{ .response_storage = .{ .dynamic = &response }, .method = .POST, .payload = body, .server_header_buffer = &buf, .headers = headers, .location = http.Client.FetchOptions.Location{ .uri = url } };
    _ = try client.fetch(options);
    const obj = try std.json.parseFromSlice(SpotifyResponse, allo, response.items, .{});
    const token = obj.value.access_token;
    return token;
}
fn get_dotenv(allocator: std.mem.Allocator) ![2][]const u8 {
    var envs = try dotenv.getDataFrom(allocator, ".env");
    const client_id = envs.get("client_id").?.?;
    const client_secret = envs.get("client_secret").?.?;
    return .{ client_id, client_secret };
}
fn make_sample_request(token: []u8, alloc: std.mem.Allocator, album_id: []const u8) !std.ArrayList(u8) {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var local_arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer local_arena.deinit();
    const url = try fmt.allocPrint(local_arena.allocator(), "https://api.spotify.com/v1/albums/{s}", .{album_id});
    var client = http.Client{ .allocator = local_arena.allocator() };
    var buffer = std.ArrayList(u8).init(alloc);
    const bearer = try fmt.allocPrint(local_arena.allocator(), "Bearer {s}", .{token});
    const respcode = try client.fetch(http.Client.FetchOptions{
        .headers = .{ .authorization = .{ .override = bearer } },
        .location = .{ .uri = try std.Uri.parse(url) },
        .method = .GET,
        .response_storage = .{ .dynamic = &buffer },
    });
    _ = respcode;
    // std.debug.print("Buffer after request {}\n", .{buffer});
    // std.debug.print("Request Status: {d}\n", .{respcode.status});

    return buffer;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const token = try get_token(arena.allocator());
    const api_response = try make_sample_request(
        token,
        arena.allocator(),
        album_code,
    );
    const resp = api_response.items;
    _ = resp;
    // std.debug.print("token = {s}", .{token});
    // std.debug.print("Info album = {s}", .{resp});
}
