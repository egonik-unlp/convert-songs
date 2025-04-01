const std = @import("std");
const net = std.net;
const TrackSearchResult = @import("track").TrackSearchResult;
const SerializedToken = @import("spotify-token").SerializedToken;
const token2 = "BQD4L0Y1bmwgIDQlXiq0k9w3QVmLqhsjLcauzZ-0leXGCMjjBCINR9aoRLRvupaCOpBn_J3jY5rE3BtFp78HI4EoFB5JZ7Z35SnzA4SbfsKs_5ciZHLpHUTGkPnQCFdcFCQm0VfL5zJ8-_bdHEGLshKSZC_QXzURCBOkMnAdCmauMOz2CW1wlnhYUPYjj_Sg1Dy1t1Lse9PHwpswMEuaFvimwbUXDbe0fFMPWFJaJl7ZsikoAvGFG8c2mFN_LezwgfsPdXV1SMlsjuIU";
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
    token: []const u8,
    pub fn build(allocator: std.mem.Allocator, user_name: []const u8, name: []const u8, token: []const u8) !Playlist {
        var playlist = try allocator.create(Playlist);
        playlist.allocator = allocator;
        playlist.name = name;
        playlist.user_name = user_name;
        playlist.id = null;
        playlist.tracks = null;
        playlist.token = token;
        return playlist.*;
    }
    pub fn create(self: *Playlist) !void {
        var tokener = try SerializedToken.init(self.allocator);
        const token = try tokener.retrieve();
        _ = token;
        std.debug.print("\n\n{any}\n\n", .{self});
        const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
        const body = try PlaylistRequest.build("nuevo algo", "prueba desc", true, false).stringify(self.allocator);
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
            // Esto no deberia ser necesario, pero la cuenta me esta fallando por alguna razon
            // asi anda.
            if (queue.items.len == 0) {
                break;
            }
            const pre_payload = ExtendPlaylistRequest.build(queue.items);
            const payload = try std.json.stringifyAlloc(self.allocator, pre_payload, .{});
            var tokener = try SerializedToken.init(self.allocator);
            const token = try tokener.retrieve();
            _ = token;
            const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
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
