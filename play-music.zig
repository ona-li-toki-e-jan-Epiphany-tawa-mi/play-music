//! This file is part of play-music.
//!
//! Copyright (c) 2025 ona-li-toki-e-jan-Epiphany-tawa-mi
//!
//! play-music is free software: you can redistribute it and/or modify it under
//! the terms of the GNU General Public License as published by the Free
//! Software Foundation, either version 3 of the License, or (at your option)
//! any later version.
//!
//! play-music is distributed in the hope that it will be useful, but WITHOUT
//! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//! FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//! more details.
//!
//! You should have received a copy of the GNU General Public License along with
//! play-music. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const process = std.process;
const time = std.time;

const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const BufferedWriter = std.io.BufferedWriter;
const Child = std.process.Child;
const File = std.fs.File;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const Random = std.Random;
const StaticStringMap = std.StaticStringMap;

const BufferedFileWriter = BufferedWriter(4096, File.Writer);
const RandomPrng = Random.DefaultPrng;

fn bufferedFileWriter(writer: File.Writer) BufferedFileWriter {
    return .{ .unbuffered_writer = writer };
}

////////////////////////////////////////////////////////////////////////////////
// CLI                                                                        //
////////////////////////////////////////////////////////////////////////////////

pub fn main() !void {
    var stdout = bufferedFileWriter(io.getStdOut().writer());
    defer stdout.flush() catch {};
    var stderr = bufferedFileWriter(io.getStdErr().writer());
    defer stderr.flush() catch {};

    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var prng = RandomPrng.init(@as(u64, @bitCast(time.milliTimestamp())));
    const random = prng.random();

    ParsedArguments.init(
        allocator,
        &stderr,
        &stdout,
    ) catch |err| switch (err) {
        error.ExitSuccess => return,
        else => return err,
    };
    defer ParsedArguments.deinit();

    var playlist = Playlist.init(allocator);
    defer playlist.deinit();
    for (ParsedArguments.directories.items) |directory| {
        try playlist.appendFromDirectory(directory);
    }
    if (ParsedArguments.shuffle) playlist.shuffle(random);

    try stdout.writer().print(
        "INFO: {d} songs loaded\n",
        .{playlist.songs.items.len},
    );

    while (true) {
        for (playlist.songs.items) |song| {
            try stdout.writer().print("INFO: Now playing: {s}\n", .{song.file_path});
            try stdout.flush();
            try playSong(allocator, song);
        }

        if (!ParsedArguments.repeat) break;
    }
}

fn printHelp(to: *BufferedFileWriter) !void {
    try to.writer().print(
        \\Usages:
        \\  {s} [OPTION...] [--] DIRECTORY...
        \\
        \\Plays the music files located in DIRECTORY with mpv.
        \\
        \\Options:
        \\  -h, --help    Display help and exit.
        \\
        \\  -m, --match REGEX
        \\    Only plays songs whose file name matches REGEX.
        \\    REGEX is interpreted as an extended regular expression (see
        \\    regex(3).)
        \\
        \\  --no-shuffle
        \\    Plays the songs in the order they appear in the directory
        \\    instead of randomly shuffling them.
        \\
        \\  --no-repeat
        \\    Exits once all the songs have been played instead of repeating
        \\    them in an endless loop.
    , .{ParsedArguments.program_name});
}

fn printShortHelp(to: *BufferedFileWriter) !void {
    try to.writer().print(
        "Try '{s} -h' for more information\n",
        .{ParsedArguments.program_name},
    );
}

const ParsedArguments = struct {
    var initialized = false;
    var allocator: Allocator = undefined;

    var program_name: []const u8 = undefined;
    var directories: ArrayListUnmanaged([]u8) = undefined;
    var match: ?[]u8 = undefined;
    var shuffle: bool = undefined;
    var repeat: bool = undefined;

    /// Deinitialize with `deinit`.
    fn init(
        allocatorr: Allocator,
        stderr: *BufferedFileWriter,
        stdout: *BufferedFileWriter,
    ) !void {
        debug.assert(!initialized);

        allocator = allocatorr;
        directories = ArrayListUnmanaged([]u8).empty;
        match = null;
        shuffle = true;
        repeat = true;
        errdefer deinit();

        try parseArguments(stderr, stdout);

        initialized = true;
    }

    fn deinit() void {
        debug.assert(initialized);

        for (directories.items) |directory| allocator.free(directory);
        directories.deinit(allocator);
        if (match) |pattern| allocator.free(pattern);

        initialized = false;
    }

    fn appendDirectory(path: []const u8) !void {
        const path_copy = try allocator.dupe(u8, path);
        errdefer allocator.free(path_copy);
        try directories.append(allocator, path_copy);
    }

    fn setMatch(pattern: []const u8) !void {
        const pattern_copy = try allocator.dupe(u8, pattern);
        if (match) |old_pattern| allocator.free(old_pattern);
        match = pattern_copy;
    }

    fn parseArguments(
        stderr: *BufferedFileWriter,
        stdout: *BufferedFileWriter,
    ) !void {
        var arguments = try process.argsWithAllocator(allocator);
        defer arguments.deinit();

        program_name = arguments.next().?;

        while (arguments.next()) |argument| {
            if (0 == argument.len) continue;

            if (mem.eql(u8, argument, "--help")) {
                try printHelp(stdout);
                return error.ExitSuccess;
            } else if (mem.eql(u8, argument, "--no-shuffle")) {
                shuffle = false;
            } else if (mem.eql(u8, argument, "--match")) {
                if (arguments.next()) |pattern| {
                    try setMatch(pattern);
                } else {
                    try stderr.writer().print(
                        "ERROR: Option '{s}' expects a regular expression as an argument\n",
                        .{argument},
                    );
                    try printShortHelp(stderr);
                    return error.MissingMatchMattern;
                }
            } else if (mem.eql(u8, argument, "--no-repeat")) {
                repeat = false;
            } else if (mem.eql(u8, argument, "--")) {
                while (arguments.next()) |next_argument| {
                    try appendDirectory(next_argument);
                }
                return;
            } else if (2 < argument.len and mem.eql(u8, argument[0..2], "--")) {
                try stderr.writer().print(
                    "ERROR: Unknown long option '{s}'\n",
                    .{argument},
                );
                try printShortHelp(stderr);
                return error.UnknownLongOption;
            } else if ('-' == argument[0]) {
                try parseShortOptions(stderr, stdout, argument[1..], &arguments);
            } else {
                try appendDirectory(argument);
            }
        }
    }

    fn parseShortOptions(
        stderr: *BufferedFileWriter,
        stdout: *BufferedFileWriter,
        options: []const u8, // Without the trailing `-`.
        remaining_arguments: *ArgIterator,
    ) !void {
        for (0..options.len) |i| {
            const option = options[i];

            switch (option) {
                'h' => {
                    try printHelp(stdout);
                    return error.ExitSuccess;
                },
                'm' => {
                    if (i < options.len - 1) {
                        // If leftover text in options, it is the argument to -m.
                        try setMatch(options[i + 1 ..]);
                    } else if (remaining_arguments.next()) |pattern| {
                        try setMatch(pattern);
                    } else {
                        try stderr.writer().print(
                            "ERROR: Option '-{c}' expects a regular expression as an argument\n",
                            .{option},
                        );
                        try printShortHelp(stderr);
                        return error.MissingMatchMattern;
                    }
                    return;
                },
                else => {
                    try stderr.writer().print(
                        "ERROR: Unknown short option '-{c}'\n",
                        .{option},
                    );
                    try printShortHelp(stderr);
                    return error.UnknownShortOption;
                },
            }
        }
    }
};

////////////////////////////////////////////////////////////////////////////////
// Songs and Playlists                                                        //
////////////////////////////////////////////////////////////////////////////////

const FileFormat = enum {
    const Self = @This();

    flac,
    mp3,
    vorbis,
    wav,

    const extensions_formats_map = StaticStringMap(FileFormat).initComptime(.{
        .{ ".flac", .flac },
        .{ ".mp3", .mp3 },
        .{ ".ogg", .vorbis },
        .{ ".wav", .wav },
    });

    // TODO: mimetypes?
    fn formatFromFile(path: []const u8) ?Self {
        return extensions_formats_map.get(fs.path.extension(path));
    }
};

const Song = struct {
    const Self = @This();

    file_path: []u8,
    format: FileFormat,

    /// Takes ownership of passed in `path`.
    fn initFromOwnedPath(path: []u8) !Self {
        if (FileFormat.formatFromFile(path)) |format| {
            return .{
                .file_path = path,
                .format = format,
            };
        } else {
            return error.NotAnAudioFile;
        }
    }

    fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.file_path);
        self.* = undefined;
    }
};

const Playlist = struct {
    const Self = @This();

    allocator: Allocator,
    songs: ArrayListUnmanaged(Song),

    /// Deinitialize with `deinit`.
    fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .songs = ArrayListUnmanaged(Song).empty,
        };
    }

    fn deinit(self: *Self) void {
        for (self.songs.items) |*song| song.deinit(self.allocator);
        self.songs.deinit(self.allocator);
        self.* = undefined;
    }

    // TODO: add regex matching.
    fn appendFromDirectory(self: *Self, path: []const u8) !void {
        var directory = try fs.cwd().openDir(path, .{
            .iterate = true,
        });
        defer directory.close();

        var iterator = directory.iterate();
        while (try iterator.next()) |entry| {
            var song = blk: {
                const file = try fs.path.join(
                    self.allocator,
                    &.{ path, entry.name },
                );
                errdefer self.allocator.free(file);
                break :blk Song.initFromOwnedPath(file) catch |err| switch (err) {
                    error.NotAnAudioFile => continue,
                    else => return err,
                };
            };
            errdefer song.deinit(self.allocator);
            try self.songs.append(self.allocator, song);
        }
    }

    fn shuffle(self: *Self, random: Random) void {
        random.shuffle(Song, self.songs.items);
    }
};

////////////////////////////////////////////////////////////////////////////////
// TODO
////////////////////////////////////////////////////////////////////////////////

// TODO: figure out way to test and dynamically select play methods.
// fn initSoundsystem() void {}

fn playSong(allocator: Allocator, song: Song) !void {
    switch (song.format) {
        .flac, .mp3, .vorbis, .wav => {
            const arguments = [_][]const u8{
                "mpv",
                "--no-audio-display",
                song.file_path,
            };
            // const arguments = [_][]const u8{ "cvlc", path };
            var child = Child.init(&arguments, allocator);
            // TODO: handle exit code.
            _ = try child.spawnAndWait();
        },
    }
}
