const std = @import("std");
const TrackSearchResult = @import("track").TrackSearchResult;
const SerializedToken = @import("spotify-token").SerializedToken;

const PlaylistRequest = struct {
    name: []const u8,
    description: []const u8,
    public: bool,
    pub fn build(name: []const u8, description: []const u8, public: bool) PlaylistRequest {
        return PlaylistRequest{ .name = name, .description = description, .public = public };
    }
    pub fn stringify(self: PlaylistRequest, allocator: std.mem.Allocator) ![]const u8 {
        return try std.json.stringifyAlloc(allocator, self, .{});
    }
};

pub const Playlist = struct {
    user_name: []const u8,
    name: []const u8,
    id: ?[]const u8,
    tracks: ?[]TrackSearchResult,
    allocator: std.mem.Allocator,
    pub fn build(allocator: std.mem.Allocator, user_name: []const u8, name: []const u8) !Playlist {
        var playlist = try allocator.create(Playlist);
        playlist.allocator = allocator;
        playlist.name = name;
        playlist.user_name = user_name;
        playlist.id = null;
        playlist.tracks = null;
        return playlist.*;
    }
    pub fn create(self: *Playlist) !void {
        var tokener = try SerializedToken.init(self.allocator);
        const token = try tokener.retrieve();
        const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
        const body = try PlaylistRequest.build("prueba", "prueba desc", true).stringify(self.allocator);
        const url = try std.fmt.allocPrint(self.allocator, "https://api.spotify.com/v1/users/{s}/playlists", .{self.user_name});
        const uri = try std.Uri.parse(url);
        var storage = std.ArrayList(u8).init(self.allocator);
        const options = std.http.Client.FetchOptions{
            .headers = .{
                .authorization = .{ .override = bearer },
            },
            .method = .POST,
            .location = .{ .uri = uri },
            .payload = body,
            .response_storage = .{ .dynamic = &storage },
        };
        var client = std.http.Client{ .allocator = self.allocator };
        const response = try client.fetch(options);
        _ = response;
        std.debug.print("{s}", .{storage.items});
    }
    pub fn populate(self: *Playlist, tracks: []TrackSearchResult) void {
        self.tracks = tracks;
    }
    pub fn upload(self: Playlist) !void {
        const total_tracks = self.tracks.?.len;
        var remainder: i32 = total_tracks;
        var next_chunk_len = @min(100, remainder);
        var so_far = 0;
        while (remainder > 0) {
            var queue = std.ArrayList(u8).init(self.allocator);
            const chunk = self.tracks.?[so_far..next_chunk_len];
            for (chunk) |track| {
                const string = track.tracks.items[0].href;
                try queue.append(string);
                try queue.append(",");
            }
            const payload = try std.fmt.allocPrint(self.allocator, "uris=", queue);
            const tokener = try SerializedToken.init(self.allocator);
            const token = try tokener.retrieve();
            const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
            const url = try std.fmt.allocPrint(self.allocator, "https://api.spotify.com/v1/playlists/{s}", .{self.id.?});
            const uri = try std.Uri.parse(url);
            var storage = std.ArrayList(u8).init(self.allocator);
            const options = std.http.Client.FetchOptions{
                .headers = .{
                    .authorization = .{ .override = bearer },
                },
                .method = .POST,
                .location = .{ .uri = uri },
                .payload = payload,
                .response_storage = .{ .dynamic = &storage },
            };
            var client = std.http.Client{ .allocator = self.allocator };
            const response = client.fetch(options);
            _ = response;
            so_far += next_chunk_len;
            next_chunk_len = @min(100, remainder);
            remainder -= next_chunk_len;
        }
    }
};
