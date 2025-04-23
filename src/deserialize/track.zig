const std = @import("std");
const SerializedToken = @import("spotify-token").SerializedToken;
const eql = std.mem.eql;

pub const TrackSearchResult = struct {
    tracks: struct {
        href: []u8,
        limit: i32,
        next: ?[]u8,
        offset: i32,
        total: i32,
        items: []struct {
            album: struct {
                album_type: []u8,
                total_tracks: i32,
                available_markets: [][]u8,
                external_urls: struct {
                    spotify: []u8,
                },
                href: []u8,
                id: []u8,
                images: []struct {
                    url: []u8,
                    height: i32,
                    width: i32,
                },
                name: []u8,
                release_date: []u8,
                release_date_precision: []u8,
                type: []u8,
                uri: []u8,
                artists: []struct {
                    external_urls: struct {
                        spotify: []u8,
                    },
                    href: []u8,
                    id: []u8,
                    name: []u8,
                    type: []u8,
                    uri: []u8,
                },
                is_playable: bool,
            },
            artists: []struct {
                external_urls: struct {
                    spotify: []u8,
                },
                href: []u8,
                id: []u8,
                name: []u8,
                type: []u8,
                uri: []u8,
            },
            available_markets: [][]u8,
            disc_number: i32,
            duration_ms: i32,
            explicit: bool,
            external_ids: struct {
                isrc: []u8,
            },
            external_urls: struct {
                spotify: []u8,
            },
            href: []u8,
            id: []u8,
            is_playable: bool,
            name: []u8,
            popularity: i32,
            track_number: i32,
            type: []u8,
            uri: []u8,
            is_local: bool,
        },
    },
    pub fn make_request(allocator: std.mem.Allocator, tokener: *SerializedToken, track_name: []const u8, album_name: ?[]const u8, artist_name: ?[]const u8, result_count: u8) !TrackSearchResult {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        var local_arena = std.heap.ArenaAllocator.init(gpa.allocator());
        defer local_arena.deinit();
        const query_url_factory = try SearchQuery.init(
            local_arena.allocator(),
            track_name,
            album_name,
            artist_name,
            result_count,
        );
        const query_url = try query_url_factory.build();
        var client = std.http.Client{ .allocator = local_arena.allocator() };
        const token = try tokener.retrieve();
        const bearer = try std.fmt.allocPrint(local_arena.allocator(), "Bearer {s}", .{token});
        var buffer: [4096]u8 = undefined;
        var local_buffer = std.ArrayList(u8).init(allocator);
        const destination = try std.Uri.parse(query_url);

        const request = try client.fetch(.{
            .server_header_buffer = &buffer,
            .headers = .{ .authorization = .{ .override = bearer } },
            .location = .{ .uri = destination },
            .response_storage = .{ .dynamic = &local_buffer },
            .method = .GET,
        });
        _ = switch (request.status) {
            std.http.Status.ok => .{},
            std.http.Status.unauthorized => try tokener.update(),
            else => |resp| std.debug.print("No se que paso, status de request es {any}\n", .{resp}),
        };

        const response = try std.json.parseFromSlice(TrackSearchResult, allocator, local_buffer.items, .{ .ignore_unknown_fields = true });
        errdefer {
            std.debug.print("Failed with {s}\n", .{response.value});
            std.debug.print("Song params : {} {} {} ", .{ track_name, album_name, artist_name });
        }
        return response.value;
    }
};

const SearchQuery = struct {
    track_name: []const u8,
    album_name: []const u8,
    artist_name: []const u8,
    result_count: u8,
    allocator: std.mem.Allocator,
    fn init(allocator: std.mem.Allocator, track_name: []const u8, album_name: ?[]const u8, artist_name: ?[]const u8, result_count: u8) !SearchQuery {
        var query = try allocator.create(SearchQuery);
        query.track_name = track_name;
        query.album_name = album_name orelse "";
        query.artist_name = artist_name orelse "";
        query.result_count = result_count;
        query.allocator = allocator;
        return query.*;
    }
    fn build(self: SearchQuery) ![]const u8 {
        const base_pattern = "%20{s}:{s}";
        const base_url = "https://api.spotify.com/v1/search?q={s}{s}{s}{s}{s}";
        const track_name = try std.fmt.allocPrint(self.allocator, "{s}%20{s}:{s}", .{ self.track_name, "track", self.track_name });
        const album_name = if (!eql(u8, self.album_name, "")) try std.fmt.allocPrint(self.allocator, base_pattern, .{ "album", self.album_name }) else "";
        const artist_name = if (!eql(u8, self.artist_name, "")) try std.fmt.allocPrint(self.allocator, base_pattern, .{ "artist", self.artist_name }) else "";
        const limit = try std.fmt.allocPrint(self.allocator, "&limit={d}", .{self.result_count});
        const query = try std.fmt.allocPrint(self.allocator, base_url, .{ track_name, artist_name, album_name, limit, "&type=track" });
        const replaced_query = try std.mem.replaceOwned(u8, self.allocator, query, " ", "%20");
        return replaced_query;
    }
};
