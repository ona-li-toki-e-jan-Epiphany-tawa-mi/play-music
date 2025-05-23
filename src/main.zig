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
const debug = std.debug;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const process = std.process;
const time = std.time;
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const AutoHashMapUnmanaged = std.hash_map.AutoHashMapUnmanaged;
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

const exre = @import("zig-exre/exre.zig");
const RegexMatchConfig = exre.RegexMatchConfig;
const Regex = exre.Regex(.{});

////////////////////////////////////////////////////////////////////////////////
// CLI                                                                        //
////////////////////////////////////////////////////////////////////////////////

pub fn main() !void {
    var stderr = bufferedFileWriter(io.getStdErr().writer());
    defer stderr.flush() catch {};
    var stdout = bufferedFileWriter(io.getStdOut().writer());
    defer stdout.flush() catch {};

    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    ParsedArguments.init(
        allocator,
        &stderr,
        &stdout,
    ) catch |err| switch (err) {
        error.ExitSuccess => return,
        else => return err,
    };
    defer ParsedArguments.deinit();

    var prng = RandomPrng.init(@as(u64, @bitCast(time.milliTimestamp())));
    const random = prng.random();

    try SoundSystem.init(allocator);
    defer SoundSystem.deinit();

    const regex: ?Regex = if (ParsedArguments.match) |pattern|
        Regex.compile(allocator, pattern) catch |err| {
            switch (err) {
                error.RegexInvalid => try stderr.writer().print(
                    "ERROR: Match pattern '{s}' is invalid (no more information, sorry)\n",
                    .{pattern},
                ),
                error.RegexTooComplex => try stderr.writer().print(
                    "ERROR: Match pattern '{s}' is too complex (no more information, sorry.)\n",
                    .{pattern},
                ),
                error.OutOfMemory => {},
            }
            return err;
        }
    else
        null;
    defer if (regex) |r| r.deinit();

    var playlist = Playlist.init(allocator);
    defer playlist.deinit();
    for (ParsedArguments.directories.items) |directory| {
        const songs_loaded = playlist.appendFromDirectory(
            &stderr,
            regex,
            directory,
        ) catch |err| {
            switch (err) {
                error.FileNotFound => try stdout.writer().print(
                    "ERROR: Directory does not exist: {s}\n",
                    .{directory},
                ),
                else => {},
            }
            return err;
        };
        try stdout.writer().print(
            "INFO: {d} song(s) loaded from directory: {s}\n",
            .{ songs_loaded, directory },
        );
    }
    if (ParsedArguments.shuffle) playlist.shuffle(random);

    {
        const songs_loaded = playlist.songs.items.len;
        if (0 == songs_loaded) {
            try stderr.writer().print("ERROR: No songs were found\n", .{});
            return error.NoSongsLoaded;
        }
        try stdout.writer().print(
            "INFO: {d} song(s) loaded in total\n",
            .{songs_loaded},
        );
    }

    while (true) {
        for (playlist.songs.items) |song| {
            try stdout.writer().print("INFO: Now playing: {s}\n", .{song.file_path});
            try stderr.flush();
            try stdout.flush();
            try SoundSystem.playSong(song);
        }

        if (!ParsedArguments.repeat) break;
    }
}

fn printVersion(to: *BufferedFileWriter) !void {
    try to.writer().print("{s} 0.2.0\n", .{ParsedArguments.program_name});
}

fn printLicensing(to: *BufferedFileWriter) !void {
    try to.writer().print(
        \\Copyright (c) 2025 ona-li-toki-e-jan-Epiphany-tawa-mi
        \\
        \\play-music is free software: you can redistribute it and/or modify it
        \\under the terms of the GNU General Public License as published by the
        \\Free Software Foundation, either version 3 of the License, or (at your
        \\option) any later version.
        \\
        \\play-music is distributed in the hope that it will be useful, but
        \\WITHOUT ANY WARRANTY; without even the implied warranty of
        \\MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
        \\General Public License for more details.
        \\
        \\You should have received a copy of the GNU General Public License
        \\along with play-music. If not, see <https://www.gnu.org/licenses/>.
        \\
        \\Source (paltepuk):
        \\  Clearnet - https://paltepuk.xyz/cgit/play-music.git/about/
        \\  I2P - http://oytjumugnwsf4g72vemtamo72vfvgmp4lfsf6wmggcvba3qmcsta.b32.i2p/cgit/play-music.git/about/
        \\  Tor - http://4blcq4arxhbkc77tfrtmy4pptf55gjbhlj32rbfyskl672v2plsmjcyd.onion/cgit/play-music.git/about/
        \\Source (GitHub): https://github.com/ona-li-toki-e-jan-Epiphany-tawa-mi/play-music/
        \\
        \\--------------------
        \\
        \\Includes zig-exre, which is licensed under the Mozilla Public License
        \\version 2.0.
        \\
        \\Included in play-music source.
        \\Original source (sourcehut): https://sr.ht/~leon_plickat/zig-exre/
        \\
    , .{});
}

fn printHelp(to: *BufferedFileWriter) !void {
    try to.writer().print(
        \\Usages:
        \\  {s} [OPTION...] [--] DIRECTORY...
        \\
        \\Plays the music files located in DIRECTORY.
        \\
        \\Available play strategies (in order of priority):
        \\  1. With mpv, if present.
        \\  2. With cvlc, if present.
        \\
        \\Options:
        \\  -h, --help       Display help and exit.
        \\  -v, --version    Display version and exit.
        \\  -l, --license    Display license(s) and source and exit.
        \\
        \\  -m, --match REGEX
        \\    Only plays songs whose file name matches REGEX. REGEX is not case
        \\    sensitive and succeeds on a partial match. Uses zig-exre
        \\    <https://sr.ht/~leon_plickat/zig-exre/>.
        \\
        \\  --no-shuffle
        \\    Plays the songs in the order they appear in the directory,
        \\    instead of randomly shuffling them.
        \\
        \\  --no-repeat
        \\    Exits once all the songs have been played, instead of repeating
        \\    them in an endless loop.
        \\
        \\  --no-skip-unplayable
        \\    Exits if some of the songs cannot be played, instead of skipping
        \\    them.
        \\
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
    var skip_unplayable: bool = undefined;

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
        skip_unplayable = true;
        errdefer deinit();

        initialized = true;
        try parseArguments(stderr, stdout);
    }

    fn deinit() void {
        debug.assert(initialized);

        for (directories.items) |directory| allocator.free(directory);
        directories.deinit(allocator);
        if (match) |pattern| allocator.free(pattern);

        initialized = false;
    }

    fn appendDirectory(path: []const u8) !void {
        debug.assert(initialized);

        const path_copy = try allocator.dupe(u8, path);
        errdefer allocator.free(path_copy);
        try directories.append(allocator, path_copy);
    }

    fn setMatch(pattern: []const u8) !void {
        debug.assert(initialized);

        const pattern_copy = try allocator.dupe(u8, pattern);
        if (match) |old_pattern| allocator.free(old_pattern);
        match = pattern_copy;
    }

    fn parseArguments(
        stderr: *BufferedFileWriter,
        stdout: *BufferedFileWriter,
    ) !void {
        debug.assert(initialized);

        var arguments = try process.argsWithAllocator(allocator);
        defer arguments.deinit();
        var has_arguments = false;

        program_name = arguments.next().?;

        while (arguments.next()) |argument| {
            has_arguments = true;

            if (0 == argument.len) continue;

            if (mem.eql(u8, argument, "--help")) {
                try printHelp(stdout);
                return error.ExitSuccess;
            } else if (mem.eql(u8, argument, "--license")) {
                try printLicensing(stdout);
                return error.ExitSuccess;
            } else if (mem.eql(u8, argument, "--version")) {
                try printVersion(stdout);
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
            } else if (mem.eql(u8, argument, "--no-skip-unplayable")) {
                skip_unplayable = false;
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
            } else if (2 < argument.len and '-' == argument[0]) {
                try parseShortOptions(stderr, stdout, argument[1..], &arguments);
            } else {
                try appendDirectory(argument);
            }
        }

        if (!has_arguments) {
            try printHelp(stdout);
            return error.ExitSuccess;
        }
    }

    fn parseShortOptions(
        stderr: *BufferedFileWriter,
        stdout: *BufferedFileWriter,
        options: []const u8, // Without the trailing `-`.
        remaining_arguments: *ArgIterator,
    ) !void {
        debug.assert(initialized);

        for (0..options.len) |i| {
            const option = options[i];

            switch (option) {
                'h' => {
                    try printHelp(stdout);
                    return error.ExitSuccess;
                },
                'l' => {
                    try printLicensing(stdout);
                    return error.ExitSuccess;
                },
                'v' => {
                    try printVersion(stdout);
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
    opus,
    vorbis,
    wav,

    const extensions_formats_map = StaticStringMap(FileFormat).initComptime(.{
        .{ ".flac", .flac },
        .{ ".mp3", .mp3 },
        .{ ".opus", .opus },
        .{ ".ogg", .vorbis },
        .{ ".wav", .wav },
    });

    // TODO: mimetypes?
    fn fromFile(path: []const u8) ?Self {
        return extensions_formats_map.get(fs.path.extension(path));
    }
};

const Song = struct {
    const Self = @This();

    file_path: []u8,
    format: FileFormat,

    /// Takes ownership of passed in `path`.
    fn initFromOwnedPath(path: []u8) !Self {
        if (FileFormat.fromFile(path)) |format| {
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

    /// Requires the sound system to be initialized (see `SoundSystem`.)
    /// If `regex` is not `null`, only files whose name match `regex` will be
    /// appended.
    fn appendFromDirectory(
        self: *Self,
        stderr: *BufferedFileWriter,
        regex: ?Regex,
        path: []const u8,
    ) !u64 {
        var songs_appended: u64 = 0;

        var directory = try fs.cwd().openDir(path, .{
            .iterate = true,
        });
        defer directory.close();

        var iterator = directory.iterate();
        while (try iterator.next()) |entry| {
            if (regex) |r| {
                const match_mode = RegexMatchConfig{
                    .mode = .substring,
                    .case = .ignore,
                };
                if (!r.match(match_mode, entry.name)) continue;
            }

            var song = blk: {
                const file = try fs.path.join(
                    self.allocator,
                    &.{ path, entry.name },
                );
                errdefer self.allocator.free(file);
                break :blk Song.initFromOwnedPath(file) catch |err| switch (err) {
                    error.NotAnAudioFile => {
                        self.allocator.free(file);
                        continue;
                    },
                    else => return err,
                };
            };
            errdefer song.deinit(self.allocator);

            if (!SoundSystem.isPlayable(song.format)) {
                if (ParsedArguments.skip_unplayable) {
                    try stderr.writer().print(
                        "WARN: No available strategy to play {s} files. Skipping: {s}\n",
                        .{ @tagName(song.format), song.file_path },
                    );
                    song.deinit(self.allocator);
                    continue;
                } else {
                    try stderr.writer().print(
                        "ERROR: No available strategy to play {s} files. Offending file: {s}\n",
                        .{ @tagName(song.format), song.file_path },
                    );
                    return error.UnplayableFormat;
                }
            }

            try self.songs.append(self.allocator, song);
            songs_appended +|= 1;
        }

        return songs_appended;
    }

    fn shuffle(self: *Self, random: Random) void {
        random.shuffle(Song, self.songs.items);
    }
};

////////////////////////////////////////////////////////////////////////////////
// Sound System                                                               //
////////////////////////////////////////////////////////////////////////////////

// TODO: develop ability to load audio from files and pass to system's sound servers/other.

const SoundSystem = struct {
    var initialized = false;
    var allocator: Allocator = undefined;

    var formats_play_strategies_map: AutoHashMapUnmanaged(
        FileFormat,
        PlayStrategy,
    ) = undefined;

    /// Deinitialize with `deinit`.
    fn init(allocatorr: Allocator) !void {
        debug.assert(!initialized);

        allocator = allocatorr;
        formats_play_strategies_map = AutoHashMapUnmanaged(
            FileFormat,
            PlayStrategy,
        ).empty;
        errdefer formats_play_strategies_map.deinit(allocator);

        // Per-format strategy selection.
        inline for (@typeInfo(FileFormat).@"enum".fields) |field| blk: {
            const format: FileFormat = @enumFromInt(field.value);

            switch (format) {
                .flac => {},
                .mp3 => {},
                .opus => {},
                .vorbis => {},
                .wav => {},
            }

            if (isProgramAvailable(allocator, &.{"mpv"})) {
                try formats_play_strategies_map.put(
                    allocator,
                    format,
                    mpvPlayStrategy,
                );
                break :blk;
            }
            if (isProgramAvailable(allocator, &.{ "cvlc", "-h" })) {
                try formats_play_strategies_map.put(
                    allocator,
                    format,
                    cvlcPlayStrategy,
                );
                break :blk;
            }
        }

        initialized = true;
    }

    fn deinit() void {
        debug.assert(initialized);

        formats_play_strategies_map.deinit(allocator);

        initialized = false;
    }

    fn isPlayable(format: FileFormat) bool {
        debug.assert(initialized);

        return formats_play_strategies_map.contains(format);
    }

    fn playSong(song: Song) !void {
        debug.assert(initialized);

        if (formats_play_strategies_map.get(song.format)) |strategy| {
            try strategy(allocator, song);
        } else {
            return error.UnplayableFormat;
        }
    }
};

// TODO: find a better way to determine if a program is available.
/// Must have program as index 0 in `arguments`, and program should exit
/// immediately with supplied `arguments`.
fn isProgramAvailable(
    allocator: Allocator,
    arguments: []const []const u8,
) bool {
    var child = Child.init(arguments, allocator);
    // Blackholes program output.
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    // If errored out, the program is *probably* not available.
    _ = child.spawnAndWait() catch return false;
    return true;
}

const PlayStrategy = *const fn (
    allocator: Allocator,
    song: Song,
) PlayStrategyError!void;

const PlayStrategyError = Child.SpawnError;

fn mpvPlayStrategy(allocator: Allocator, song: Song) PlayStrategyError!void {
    switch (song.format) {
        .flac, .mp3, .vorbis, .wav, .opus => {
            const arguments = [_][]const u8{
                "mpv",
                "--no-audio-display", // Prevents display of cover art.
                song.file_path,
            };

            var child = Child.init(&arguments, allocator);
            // TODO: handle exit code.
            _ = try child.spawnAndWait();
        },
    }
}

fn cvlcPlayStrategy(allocator: Allocator, song: Song) PlayStrategyError!void {
    switch (song.format) {
        .flac, .mp3, .vorbis, .wav, .opus => {
            const arguments = [_][]const u8{
                "cvlc",
                "--play-and-exit", // Makes exit after the song ends.
                song.file_path,
            };

            var child = Child.init(&arguments, allocator);
            // TODO: handle exit code.
            _ = try child.spawnAndWait();
        },
    }
}
