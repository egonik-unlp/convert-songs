const std = @import("std");
const http = std.http;
const album_code = "06zWjeOA3MwBHLApKUS3Qs?si=LkxC6rN9QhmXiY67dQ6QYQ";
const SerializedToken = @import("spotify-token").SerializedToken;
const AlbumRequest = @import("album").AutoGenerated;
const TrackSearch = @import("track").TrackSearchResult;

fn make_sample_request(token: []const u8, alloc: std.mem.Allocator, album_id: []const u8) !std.ArrayList(u8) {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var local_arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer local_arena.deinit();
    const url = try std.fmt.allocPrint(local_arena.allocator(), "https://api.spotify.com/v1/albums/{s}", .{album_id});
    var client = http.Client{ .allocator = local_arena.allocator() };
    var buffer = std.ArrayList(u8).init(alloc);
    const bearer = try std.fmt.allocPrint(local_arena.allocator(), "Bearer {s}", .{token});
    const respcode = try client.fetch(http.Client.FetchOptions{
        .headers = .{ .authorization = .{ .override = bearer } },
        .location = .{ .uri = try std.Uri.parse(url) },
        .method = .GET,
        .response_storage = .{ .dynamic = &buffer },
    });
    std.debug.print("Request Status: {}\n", .{respcode.status});

    return buffer;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const args = try std.process.argsAlloc(arena.allocator());
    const path = if (args.len >= 2) args[1] else {
        std.debug.print("Provide a spotify album code\n", .{});
        return;
    };
    var tokener = try SerializedToken.init(arena.allocator());
    const token = try tokener.retrieve();
    std.debug.print("Request made using token : {s}\n", .{token});
    const api_response = try make_sample_request(
        token,
        arena.allocator(),
        path,
    );
    const resp = api_response.items;
    try write_to_json(resp);
    const laika = try deserialize(resp, arena.allocator());
    std.debug.print("Tracks = {s}\n", .{laika.tracks.href});
    std.debug.print("Artista = {s}\n", .{laika.artists[0].name});
    const track_search = try TrackSearch.make_request(
        arena.allocator(),
        &tokener,
        "fine day",
        null,
        "Opus III",
        10,
    );

    std.debug.print("{s}", .{track_search.tracks.items[0].name});
    for (track_search.tracks.items, 0..) |result, num| {
        std.debug.print("\nResult number : {d}\nartist : {s} trackname : {s} albumname: {s}", .{ num, result.artists[0].name, result.name, result.album.name });
    }
}

fn write_to_json(response: []const u8) !void {
    const cwd = std.fs.cwd();
    const file = try cwd.createFile("album.json", .{});
    try file.writeAll(response);
}

fn deserialize(response: []const u8, alloc: std.mem.Allocator) !AlbumRequest {
    const parsed = try std.json.parseFromSlice(AlbumRequest, alloc, response, .{ .ignore_unknown_fields = true });
    return parsed.value;
}
