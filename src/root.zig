//! C-ABI surface for the convert-songs Zig library, consumed by the
//! `convert-ffi` Rust crate. The layouts below must stay in sync with the
//! `#[repr(C)]` structs in `convert-ffi/src/ffi.rs`.
const std = @import("std");
const base64 = std.base64;
const http = std.http;
const SerializedToken = @import("spotify-token").SerializedToken;
const TrackSearch = @import("track").TrackSearchResult;
const Playlist = @import("playlist").Playlist;
const env = @import("server/env.zig");

/// Long-lived allocator: everything returned across the FFI boundary must
/// outlive the call, so we deliberately leak (the Rust side copies it out
/// immediately). TODO: expose free functions if a caller needs to release it.
const gpa = std.heap.page_allocator;

/// Mirrors Rust's `#[repr(C)] struct Str { ptr: *const u8, len: usize }`.
const Str = extern struct {
    ptr: [*]const u8,
    len: usize,

    fn fromSlice(slice: []const u8) Str {
        return .{ .ptr = slice.ptr, .len = slice.len };
    }

    fn asSlice(self: Str) []const u8 {
        return self.ptr[0..self.len];
    }

    /// Copy a slice into the leaked allocator and wrap it.
    fn dupe(slice: []const u8) Str {
        const copy = gpa.dupe(u8, slice) catch return fromSlice("");
        return fromSlice(copy);
    }
};

const empty_str = Str.fromSlice("");

/// Mirrors Rust's `#[repr(C)] struct Query`.
const Query = extern struct {
    name: Str,
    album: Str,
    artist: Str,
};

/// Mirrors Rust's `#[repr(C)] struct Candidate` — one possible Spotify match.
const Candidate = extern struct {
    name: Str,
    album: Str,
    artist: Str,
    uri: Str,
    image: Str,
};

/// Candidates for a single input track.
const CandidateList = extern struct {
    ptr: [*]Candidate,
    len: usize,
};

/// One `CandidateList` per input query, index-aligned with the input.
const TrackResults = extern struct {
    ptr: [*]CandidateList,
    len: usize,
};

/// Borrowed slice of queries from Rust.
const QueryList = extern struct {
    ptr: [*]const Query,
    len: usize,
};

/// Borrowed slice of strings from Rust (e.g. track URIs).
const StrList = extern struct {
    ptr: [*]const Str,
    len: usize,
};

const empty_candidate_list = CandidateList{ .ptr = undefined, .len = 0 };
const max_candidates = 5;

/// Resolve a whole batch of tracks in one call, returning up to `max_candidates`
/// Spotify matches per track. The token is fetched/refreshed exactly once and
/// reused for every search — one authentication, N searches.
export fn query_songs(list: QueryList) TrackResults {
    const out = gpa.alloc(CandidateList, list.len) catch {
        return .{ .ptr = undefined, .len = 0 };
    };
    @memset(out, empty_candidate_list);

    var tokener = SerializedToken.init(gpa) catch |err| {
        std.debug.print("query_songs token init failed: {s}\n", .{@errorName(err)});
        return .{ .ptr = out.ptr, .len = out.len };
    };
    _ = tokener.retrieve() catch |err| {
        std.debug.print("query_songs token retrieval failed: {s}\n", .{@errorName(err)});
        return .{ .ptr = out.ptr, .len = out.len };
    };

    const queries = list.ptr[0..list.len];
    for (queries, 0..) |query, i| {
        out[i] = candidatesFor(&tokener, query) catch |err| {
            std.debug.print("query_songs entry {d} failed: {s}\n", .{ i, @errorName(err) });
            continue;
        };
    }
    return .{ .ptr = out.ptr, .len = out.len };
}

/// Search one track and collect up to `max_candidates` matches.
fn candidatesFor(tokener: *SerializedToken, query: Query) !CandidateList {
    const track_name = query.name.asSlice();
    const album_name: ?[]const u8 = if (query.album.len == 0) null else query.album.asSlice();
    const artist_name: ?[]const u8 = if (query.artist.len == 0) null else query.artist.asSlice();

    const search = try TrackSearch.make_request(gpa, tokener, track_name, album_name, artist_name, max_candidates);
    const items = search.tracks.items;
    if (items.len == 0) return empty_candidate_list;

    const cands = try gpa.alloc(Candidate, items.len);
    for (items, 0..) |item, i| {
        const artist = if (item.artists.len > 0) item.artists[0].name else "";
        const image = if (item.album.images.len > 0) item.album.images[0].url else "";
        cands[i] = .{
            .name = Str.dupe(item.name),
            .album = Str.dupe(item.album.name),
            .artist = Str.dupe(artist),
            .uri = Str.dupe(item.uri),
            .image = Str.dupe(image),
        };
    }
    return .{ .ptr = cands.ptr, .len = cands.len };
}

/// Build the Spotify authorization URL (authorization-code flow). `redirect_uri`
/// and `state` are passed in raw; the client_id and scopes live here.
export fn spotify_authorize_url(redirect_uri: Str, state: Str) Str {
    const url = std.fmt.allocPrint(
        gpa,
        "https://accounts.spotify.com/authorize?response_type=code&client_id={s}&scope=playlist-modify-private%20playlist-modify-public&redirect_uri={s}&state={s}",
        .{ env.clientId(gpa) catch return empty_str, redirect_uri.asSlice(), state.asSlice() },
    ) catch return empty_str;
    return Str.fromSlice(url);
}

/// Exchange an authorization code for a user access token. Returns an empty
/// string on failure.
export fn exchange_code(code: Str, redirect_uri: Str) Str {
    return exchangeCodeImpl(code.asSlice(), redirect_uri.asSlice()) catch |err| {
        std.debug.print("exchange_code failed: {s}\n", .{@errorName(err)});
        return empty_str;
    };
}

const TokenResponse = struct { access_token: []u8 };

fn exchangeCodeImpl(code: []const u8, redirect_uri: []const u8) !Str {
    var client = http.Client{ .allocator = gpa };
    const body = try std.fmt.allocPrint(
        gpa,
        "grant_type=authorization_code&redirect_uri={s}&code={s}",
        .{ redirect_uri, code },
    );
    const url = try std.Uri.parse("https://accounts.spotify.com/api/token");

    var b64buf: [128]u8 = undefined;
    const pre64 = try std.fmt.allocPrint(gpa, "{s}:{s}", .{ try env.clientId(gpa), try env.clientSecret(gpa) });
    const preauth = base64.standard.Encoder.encode(&b64buf, pre64);
    const auth = try std.fmt.allocPrint(gpa, "Basic {s}", .{preauth});

    var storage = std.ArrayList(u8).init(gpa);
    _ = try client.fetch(.{
        .location = .{ .uri = url },
        .method = .POST,
        .headers = .{
            .authorization = .{ .override = auth },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .response_storage = .{ .dynamic = &storage },
        .payload = body,
    });

    const token = try std.json.parseFromSlice(TokenResponse, gpa, storage.items, .{ .ignore_unknown_fields = true });
    return Str.dupe(token.value.access_token);
}

/// Create a public playlist for the authenticated user and add the given track
/// URIs. Returns the playlist's open.spotify.com URL, or empty on failure.
export fn create_playlist(token: Str, name: Str, description: Str, uris: StrList) Str {
    return createPlaylistImpl(token.asSlice(), name.asSlice(), description.asSlice(), uris) catch |err| {
        std.debug.print("create_playlist failed: {s}\n", .{@errorName(err)});
        return empty_str;
    };
}

fn createPlaylistImpl(token: []const u8, name: []const u8, description: []const u8, uris: StrList) !Str {
    var playlist = try Playlist.build(gpa, name, token, description);
    try playlist.create();

    const incoming = uris.ptr[0..uris.len];
    const tracks = try gpa.alloc([]u8, incoming.len);
    for (incoming, 0..) |uri, i| {
        tracks[i] = @constCast(uri.asSlice());
    }
    playlist.tracks = tracks;
    try playlist.upload();

    const url = try std.fmt.allocPrint(gpa, "https://open.spotify.com/playlist/{s}", .{playlist.id});
    return Str.fromSlice(url);
}
