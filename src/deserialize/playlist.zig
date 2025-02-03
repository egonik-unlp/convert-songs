const std = @import("std");
const TrackSearchResult = @import("track").TrackSearchResult;
const SerializedToken = @import("spotify-token").SerializedToken;
const token2 = "BQCO79BMaQ_lY1-tex5UVPAshTf388bnauUY-1N9c0khdfWJYZ8z3_N21-szciQF4WiEgwbRxwEarOeMkmQKqTgri7DuZRO3Izo-533uS_kvYPTsoB-ojTUODE9jYjqzqymkaxWbc9xhMwOKhlzz20Owhyk6eKKwQ8WLkP56L19KqQrHQk3KI-tOqDHrZMAfJYOfKLCa1sphnQNmXBkMJOfhCVXghiIIKdnxYQQu2En0ku7QjCQB09YVelx-Cm8ZqwwNntTdfEXdc3mp";
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
    position: u8,
    pub fn build(uris: [][]const u8, position: u8) ExtendPlaylistRequest {
        return ExtendPlaylistRequest{ .uris = uris, .position = position };
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
        const body = try PlaylistRequest.build("prueba3", "prueba desc", true, false).stringify(self.allocator);
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
                    const appendable = try std.fmt.allocPrint(self.allocator, "{s}", .{track});
                    try queue.append(appendable);
                }
            }
            const pre_payload = ExtendPlaylistRequest.build(queue.items, 0);
            const payload = try std.json.stringifyAlloc(self.allocator, pre_payload, .{});
            std.debug.print("payload = {s}", .{payload});
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
            so_far += next_chunk_len;
            next_chunk_len = @min(100, remainder);
            remainder -= next_chunk_len;
        }
    }
};
const SoloId = struct { id: []u8 };
const FullParse = struct {
    collaborative: bool,
    description: []u8,
    external_urls: External_Urls,
    followers: Followers,
    href: []u8,
    id: []u8,
    images: []Images,
    name: []u8,
    owner: Owner,
    public: bool,
    snapshot_id: []u8,
    tracks: Tracks,
    type: []u8,
    uri: []u8,
};
const External_Urls = struct {
    spotify: []u8,
};
const Followers = struct {
    href: []u8,
    total: i32,
};
const Images = struct {
    url: []u8,
    height: i32,
    width: i32,
};
const Owner = struct {
    external_urls: External_Urls,
    followers: Followers,
    href: []u8,
    id: []u8,
    type: []u8,
    uri: []u8,
    display_name: []u8,
};
const Added_By = struct {
    external_urls: External_Urls,
    followers: Followers,
    href: []u8,
    id: []u8,
    type: []u8,
    uri: []u8,
};
const Restrictions = struct {
    reason: []u8,
};
const Artists = struct {
    external_urls: External_Urls,
    href: []u8,
    id: []u8,
    name: []u8,
    type: []u8,
    uri: []u8,
};
const Album = struct {
    album_type: []u8,
    total_tracks: i32,
    available_markets: [][]u8,
    external_urls: External_Urls,
    href: []u8,
    id: []u8,
    images: []Images,
    name: []u8,
    release_date: []u8,
    release_date_precision: []u8,
    restrictions: Restrictions,
    type: []u8,
    uri: []u8,
    artists: []Artists,
};
const External_Ids = struct {
    isrc: []u8,
    ean: []u8,
    upc: []u8,
};
const Linked_From = struct {};
const Track = struct {
    album: Album,
    artists: []Artists,
    available_markets: [][]u8,
    disc_number: i32,
    duration_ms: i32,
    explicit: bool,
    external_ids: External_Ids,
    external_urls: External_Urls,
    href: []u8,
    id: []u8,
    is_playable: bool,
    linked_from: Linked_From,
    restrictions: Restrictions,
    name: []u8,
    popularity: i32,
    preview_url: []u8,
    track_number: i32,
    type: []u8,
    uri: []u8,
    is_local: bool,
};
const Items = struct {
    added_at: []u8,
    added_by: Added_By,
    is_local: bool,
    track: Track,
};
const Tracks = struct {
    href: []u8,
    limit: i32,
    next: []u8,
    offset: i32,
    previous: []u8,
    total: i32,
    items: []Items,
};
