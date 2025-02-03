const std = @import("std");
const TrackSearchResult = @import("track").TrackSearchResult;
const SerializedToken = @import("spotify-token").SerializedToken;
const token2 = "BQCUirNZeebzqGtPJ7YqRQ6GLyEtBDM62_PyVzfF0QrzTabZllajWxgR6ogNIhKoHbXUxGZcvtIPzz15Rxm7RcOQrjIGfeLy_J1gDfkjLNNT-CCQ_iq_cgbhUYlBphS9B1SvvjdzmQAQ9MIdZyEgDN65yl7jErCN_sRke31wN8x9GKEIIxvRNC6C9SMgX15Zx_q3WmYPjLGvLv7IG4nQ2TefGQYKLrzNrABG56WHuL053-kU5Ybu4wEhgzCvunHGt5heRtx5ttKTSuaW";
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
    user_name: []const u8,
    name: []const u8,
    id: ?[]const u8,
    tracks: ?[][]u8,
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
        _ = token;
        const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token2});
        const body = try PlaylistRequest.build("culo", "prueba desc", true, false).stringify(self.allocator);
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
        std.debug.print("response code = {any}\nbody={s}", .{ response.status, storage.items });
        const contid = try std.json.parseFromSlice(SoloId, self.allocator, storage.items, .{ .ignore_unknown_fields = true });

        self.id = contid.value.id;
        std.debug.print("{s}", .{storage.items});
    }
    pub fn populate(self: *Playlist, tracks: []TrackSearchResult) !void {
        var list = std.ArrayList([]u8).init(self.allocator);
        for (tracks) |trackinfo| {
            const single_track = trackinfo.tracks.items[0];
            try list.append(single_track.uri);
        }
        self.tracks = list.items;
    }
    pub fn upload(self: Playlist) !void {
        const total_tracks = self.tracks.?.len;
        var remainder: usize = @intCast(total_tracks);
        var next_chunk_len: usize = @min(100, remainder);
        var so_far: usize = 0;
        while (remainder > 0) {
            var queue = std.ArrayList([]const u8).init(self.allocator);
            const chunk = self.tracks.?[so_far..@intCast(next_chunk_len)];
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
            const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token2});
            const url = try std.fmt.allocPrint(self.allocator, "https://api.spotify.com/v1/playlists/{s}/tracks", .{self.id.?});
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
            std.debug.print("\nPL=\n{s}\n", .{payload});
            var client = std.http.Client{ .allocator = self.allocator };
            const response = try client.fetch(options);
            std.debug.print("{}", .{response.status});
            std.debug.print("{s}", .{storage.items});
            std.debug.print("\n\n\n {}{}{}\n\n\n", .{ so_far, next_chunk_len, remainder });
            so_far += next_chunk_len;
            remainder -= next_chunk_len;
            next_chunk_len = @min(100, remainder);
        }
    }
};
const SoloId = struct { id: []u8 };
