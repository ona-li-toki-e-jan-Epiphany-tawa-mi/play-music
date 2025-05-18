const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const process = std.process;

const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const BufferedWriter = std.io.BufferedWriter;
const File = std.fs.File;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const StaticStringMap = std.StaticStringMap;

const BufferedFileWriter = BufferedWriter(4096, File.Writer);

fn bufferedFileWriter(writer: File.Writer) BufferedFileWriter {
    return .{ .unbuffered_writer = writer };
}

////////////////////////////////////////////////////////////////////////////////
// CLI                                                                        //
////////////////////////////////////////////////////////////////////////////////

pub fn main() !void {
    var stdout_writer = bufferedFileWriter(io.getStdOut().writer());
    defer stdout_writer.flush() catch {};
    // const stdout = stdout_writer.writer();
    var stderr_writer = bufferedFileWriter(io.getStdErr().writer());
    defer stderr_writer.flush() catch {};
    //const stderr = stderr_writer.writer();

    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    ParsedArguments.init(
        allocator,
        &stderr_writer,
        &stdout_writer,
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
        allocator = allocatorr;
        directories = ArrayListUnmanaged([]u8).empty;
        match = null;
        shuffle = true;
        repeat = true;
        errdefer deinit();

        try parseArguments(stderr, stdout);
    }

    fn deinit() void {
        for (directories.items) |directory| allocator.free(directory);
        directories.deinit(allocator);
        if (match) |pattern| allocator.free(pattern);
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
// Playlist                                                                   //
////////////////////////////////////////////////////////////////////////////////

const Playlist = struct {
    const Self = @This();

    allocator: Allocator,
    song_files: ArrayListUnmanaged([]u8),

    /// Deinitialize with `deinit`.
    fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .song_files = ArrayListUnmanaged([]u8).empty,
        };
    }

    fn deinit(self: *Self) void {
        for (self.song_files.items) |file| self.allocator.free(file);
        self.song_files.deinit(self.allocator);
    }

    // TODO: add regex matching.
    fn appendFromDirectory(self: *Self, path: []const u8) !void {
        var directory = try fs.cwd().openDir(path, .{
            .iterate = true,
        });
        defer directory.close();

        var iterator = directory.iterate();
        while (try iterator.next()) |entry| {
            if (!isMusicFile(entry.name)) continue;

            const file = try fs.path.join(
                self.allocator,
                &.{ path, entry.name },
            );
            errdefer self.allocator.free(file);
            try self.song_files.append(self.allocator, file);
        }
    }
};

const music_file_extensions = StaticStringMap(void).initComptime(.{
    .{ ".flac", {} },
    .{ ".mp3", {} },
    .{ ".ogg", {} },
    .{ ".wav", {} },
});

fn isMusicFile(path: []const u8) bool {
    const extension = fs.path.extension(path);
    return music_file_extensions.has(extension);
}
