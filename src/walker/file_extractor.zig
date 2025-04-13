const std = @import("std");
const eql = std.mem.eql;
const c = @import("constants.zig");

pub fn get_song_names(path: []const u8, allocator: std.mem.Allocator, progress: std.Progress.Node) !std.ArrayList(SongMetadata) {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const dir = try std.fs.openDirAbsolute(path, .{ .access_sub_paths = true, .iterate = true });
    var walker = try dir.walk(arena.allocator());
    var songs = std.ArrayList(SongMetadata).init(allocator);

    while (try walker.next()) |pepe| {
        const subnode = progress.start("caminando directorio", 200);
        defer subnode.end();
        // std.debug.print("basename {s}\n", .{pepe.basename});
        if (pepe.kind == .file) {
            subnode.completeOne();
            // std.debug.print("entering with song path {s} ", .{pepe.path});
            const absolute_path = try std.fs.path.join(arena.allocator(), &.{ path, pepe.path });
            const file_handle = try std.fs.openFileAbsolute(absolute_path, .{ .mode = .read_write });
            const bytes = try file_handle.readToEndAlloc(allocator, 1e10);
            const song = SongMetadata.build(bytes);

            if (song != null) {
                // std.debug.print("Song {s} appended with path {s}\n ", .{ song.?.song, pepe.path });
                try songs.append(song.?);
            }
        }
    }
    std.debug.print("Made it through all files", .{});
    return songs;
}

fn nullbytedetect(string: []const u8) []const u8 {
    var endpos: usize = string.len;
    for (string, 0..) |char, index| {
        if (char == 0) {
            endpos = index;
            break;
        }
    }
    return string[0..endpos];
}
pub const SongMetadata = struct {
    song: []const u8,
    album: []const u8,
    artist: []const u8,
    year: []const u8,
    comment: []const u8,
    genre: []const u8,
    pub fn build(buffer: []u8) ?SongMetadata {
        var metadata = buffer[buffer.len - c.TAG_BEGIN .. buffer.len];
        var song: SongMetadata = undefined;
        if (eql(u8, metadata[c.TAG_L..c.TAG_R], "TAG")) {
            song.song = nullbytedetect(metadata[c.SONG_L..c.SONG_R]);
            song.artist = nullbytedetect(metadata[c.ARTIST_L..c.ARTIST_R]);
            song.album = nullbytedetect(metadata[c.ALBUM_L..c.ALBUM_R]);
            song.year = nullbytedetect(metadata[c.YEAR_L..c.YEAR_R]);
            song.comment = nullbytedetect(metadata[c.COMMENT_L..c.COMMENT_R]);
            song.genre = nullbytedetect(metadata[c.GENRE_L..c.GENRE_R]);
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
