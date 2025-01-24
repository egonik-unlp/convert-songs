const std = @import("std");
const eql = std.mem.eql;
const c = @import("constants.zig");

pub fn get_song_names(path: []const u8, allocator: std.mem.Allocator) !std.ArrayList(SongMetadata) {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const dir = try std.fs.openDirAbsolute(path, .{ .access_sub_paths = true, .iterate = true });
    var walker = try dir.walk(arena.allocator());
    var songs = std.ArrayList(SongMetadata).init(allocator);
    while (try walker.next()) |pepe| {
        if (pepe.kind == .file) {
            const absolute_path = try std.fs.path.join(arena.allocator(), &.{ path, pepe.path });
            const file_handle = try std.fs.openFileAbsolute(absolute_path, .{ .mode = .read_write });
            const bytes = try file_handle.readToEndAlloc(allocator, 1e10);
            const song = SongMetadata.build(bytes);
            if (song != null) {
                try songs.append(song.?);
            }
        }
    }
    return songs;
}
const SongMetadataRanges = enum { song, album, artist, year, comment, genre };
pub const SongMetadata = struct {
    song: []u8,
    album: []u8,
    artist: []u8,
    year: []u8,
    comment: []u8,
    genre: []u8,
    pub fn build(buffer: []u8) ?SongMetadata {
        var metadata = buffer[buffer.len - c.TAG_BEGIN .. buffer.len];
        var song: SongMetadata = undefined;
        if (eql(u8, metadata[c.TAG_L..c.TAG_R], "TAG")) {
            song.song = metadata[c.SONG_L..c.SONG_R];
            song.artist = metadata[c.ARTIST_L..c.ARTIST_R];
            song.album = metadata[c.ALBUM_L..c.ALBUM_R];
            song.year = metadata[c.YEAR_L..c.YEAR_R];
            song.comment = metadata[c.COMMENT_L..c.COMMENT_R];
            song.genre = metadata[c.GENRE_L..c.GENRE_R];
            return song;
        } else {
            return null;
        }
    }
    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Track: {s} - {s} - {s} - {s}", .{ self.song, self.artist, self.album, self.year });
    }
};
