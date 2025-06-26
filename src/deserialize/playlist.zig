const std = @import("std");
const net = std.net;
const TrackSearchResult = @import("track").TrackSearchResult;
const SerializedToken = @import("spotify-token").SerializedToken;
const eql = std.mem.eql;

const PlaylistRequest = struct {
    name: []const u8,
    description: []const u8,
    public: bool,
    collaborative: bool,
    pub fn build(name: []const u8, description: []const u8, public: bool, collaborative: bool) PlaylistRequest {
        return PlaylistRequest{ .name = name, .description = description, .public = public, .collaborative = collaborative };
    }
    pub fn stringify(self: PlaylistRequest, allocator: std.mem.Allocator) ![]const u8 {
        return try std.json.stringifyAlloc(allocator, self, .{});
    }
};
const ExtendPlaylistRequest = struct {
    uris: [][]const u8,

    pub fn build(uris: [][]const u8) ExtendPlaylistRequest {
        return ExtendPlaylistRequest{
            .uris = uris,
        };
    }
};

pub const Playlist = struct {
    name: []const u8,
    id: []const u8,
    tracks: [][]u8,
    allocator: std.mem.Allocator,
    token: []const u8,
    description: []const u8,
    pub fn build(allocator: std.mem.Allocator, name: []const u8, token: []const u8, description: []const u8) !Playlist {
        var playlist = try allocator.create(Playlist);
        playlist.allocator = allocator;
        playlist.name = name;
        playlist.id = undefined;
        playlist.tracks = undefined;
        playlist.token = token;
        playlist.description = description;
        return playlist.*;
    }
    pub fn create(self: *Playlist) !void {
        var tokener = try SerializedToken.init(self.allocator);
        const token = try tokener.retrieve();
        _ = token;
        const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
        const body = try PlaylistRequest.build(self.name, self.description, true, false).stringify(self.allocator);
        const user_name = try self.get_user();
        const url = try std.fmt.allocPrint(self.allocator, "https://api.spotify.com/v1/users/{s}/playlists", .{user_name});
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

        const contid = try std.json.parseFromSlice(SoloId, self.allocator, storage.items, .{ .ignore_unknown_fields = true });

        self.id = contid.value.id;
        // std.debug.print("PLAYLIST_ID:{s}\n", .{self.id});
        var writer = std.io.getStdOut().writer();
        try writer.print("{{ \"playlist_id\" : \"{s}\" }}\n", .{self.id});
    }
    pub fn populate(self: *Playlist, tracks: []TrackSearchResult, progress: std.Progress.Node) !void {
        var list = std.ArrayList([]u8).init(self.allocator);
        const loadtracks = progress.start("Loading tracks", tracks.len);
        defer loadtracks.end();
        for (tracks) |trackinfo| {
            loadtracks.completeOne();
            if (trackinfo.tracks.items.len >= 1) {
                const single_track = trackinfo.tracks.items[0];
                try list.append(single_track.uri);
            }
        }
        self.tracks = list.items;
    }
    pub fn upload(self: Playlist) !void {
        const total_tracks = self.tracks.len;
        var remainder: usize = @intCast(total_tracks);
        var next_chunk_len: usize = @min(100, remainder);
        var so_far: usize = 0;
        while (remainder > 0) {
            var queue = std.ArrayList([]const u8).init(self.allocator);
            const chunk = self.tracks[so_far..@intCast(so_far + next_chunk_len)];
            for (chunk) |track| {
                if (!eql(u8, track, " ")) {
                    try queue.append(track);
                }
            }

            const pre_payload = ExtendPlaylistRequest.build(queue.items);
            const payload = try std.json.stringifyAlloc(self.allocator, pre_payload, .{});
            var tokener = try SerializedToken.init(self.allocator);
            const token = try tokener.retrieve();
            _ = token;
            const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
            const url = try std.fmt.allocPrint(self.allocator, "https://api.spotify.com/v1/playlists/{s}/tracks", .{self.id});
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
            const file = try std.fs.cwd().createFile("dump_songs.txt", .{});
            try file.writeAll(payload);
            var client = std.http.Client{ .allocator = self.allocator };
            const response = try client.fetch(options);
            std.debug.print("{}", .{response.status});
            std.debug.print("{s}", .{storage.items});
            std.debug.print("\nBefore:\n\n {}-{}-{}\n\n\n", .{ so_far, next_chunk_len, remainder });
            so_far += next_chunk_len; // so_far = 100
            remainder -= next_chunk_len; // remainder = 53
            next_chunk_len = @min(100, remainder); // next_chunk_len = 5

            std.debug.print("\nAfter:\n\n {}-{}-{}\n\n\n", .{ so_far, next_chunk_len, remainder });
        }
    }
    pub fn get_user(self: Playlist) ![]const u8 {
        const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
        const uri = try std.Uri.parse("https://api.spotify.com/v1/me");
        var storage = std.ArrayList(u8).init(self.allocator);
        const options = std.http.Client.FetchOptions{
            .headers = .{
                .authorization = .{ .override = bearer },
            },
            .method = .GET,
            .location = .{ .uri = uri },
            .response_storage = .{ .dynamic = &storage },
        };
        var client = std.http.Client{ .allocator = self.allocator };
        _ = try client.fetch(options);
        const userdata = try std.json.parseFromSlice(User, self.allocator, storage.items, .{ .ignore_unknown_fields = true });
        std.debug.print("User {{id : {s}, display_name : {s}}}\n", .{ userdata.value.id, userdata.value.display_name });
        return userdata.value.id;
    }
};
const SoloId = struct { id: []u8 };
const User = struct { id: []const u8, display_name: []const u8 };
