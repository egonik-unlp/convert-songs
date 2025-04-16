const std = @import("std");
const eql = std.mem.eql;
const c = @import("constants.zig");
pub fn get_song_names(path: []const u8, allocator: std.mem.Allocator, progress: std.Progress.Node) !std.ArrayList(SongMetadata) {
    var dir = try std.fs.cwd().openDir(path, .{ .access_sub_paths = true, .iterate = true });
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var songs = std.ArrayList(SongMetadata).init(allocator);
    while (try walker.next()) |pepe| {
        const subnode = progress.start("caminando directorio", 200);
        defer subnode.end();
        // std.debug.print("basename {s}\n", .{pepe.basename});
        if (pepe.kind == .file) {
            subnode.completeOne();
            var ext_iter = std.mem.splitScalar(u8, pepe.path, '.');
            _ = ext_iter.next().?;
            if (ext_iter.next() == null) {
                continue;
            }

            const file_handle = try dir.openFile(pepe.path, .{ .mode = .read_write });
            defer file_handle.close();
            const bytes = try file_handle.readToEndAlloc(allocator, 1e10);
            defer allocator.free(bytes);
            const song = try SongMetadata.build(bytes, allocator);

            if (song != null) {
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
    pub fn build(buffer: []u8, allocator: std.mem.Allocator) !?SongMetadata {
        var metadata = buffer[buffer.len - c.TAG_BEGIN .. buffer.len];
        var song: SongMetadata = undefined;
        if (eql(u8, metadata[c.TAG_L..c.TAG_R], "TAG")) {
            song.song = try allocator.dupe(u8, nullbytedetect(metadata[c.SONG_L..c.SONG_R]));
            song.artist = try allocator.dupe(u8, nullbytedetect(metadata[c.ARTIST_L..c.ARTIST_R]));
            song.album = try allocator.dupe(u8, nullbytedetect(metadata[c.ALBUM_L..c.ALBUM_R]));
            song.year = try allocator.dupe(u8, nullbytedetect(metadata[c.YEAR_L..c.YEAR_R]));
            song.comment = try allocator.dupe(u8, nullbytedetect(metadata[c.COMMENT_L..c.COMMENT_R]));
            song.genre = try allocator.dupe(u8, nullbytedetect(metadata[c.GENRE_L..c.GENRE_R]));
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
