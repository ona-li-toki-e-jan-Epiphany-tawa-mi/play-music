#define _POSIX_C_SOURCE 199309L
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// POSIX.
#include <dirent.h>
#include <regex.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
// From include/.
#include <anal.h>

////////////////////////////////////////////////////////////////////////////////
// Utilities                                                                  //
////////////////////////////////////////////////////////////////////////////////

#define ARRAY_SIZE(array) (sizeof(array)/sizeof((array)[0]))

// Logging message prefixes.
#define INFO  "INFO: "
#define WARN  "WARN: "
#define ERROR "ERROR:"

// Deinitialize with free().
NONNULL static char* cstrCopy(const char *const cstr) {
    assert(cstr);

    char *const result = calloc(1 + strlen(cstr), 1);
    if (NULL == result) {
        perror(ERROR" Failed to allocate memory. Buy more RAM lol");
        exit(1);
    }
    return strcpy(result, cstr);
}

// TODO: check exit status.
NONNULL static void runCommand(
    const char *const        program,
    const char *const *const arguments,
    const size_t             arguments_length
) {
    assert(program);
    assert(arguments);
#ifndef NDEBUG
    for (size_t i = 0; i < arguments_length; ++i) assert(arguments[i]);
#endif

    const pid_t pid = fork();
    if (-1 == pid) {
        perror(ERROR" Failed to spawn child process");
        exit(1);
    }

    if (0 != pid) {
        wait(NULL);
        return;
    }

    // int execvp(const char *file, char *const argv[]);
    //                              ^
    // Who the FUCK wrote this type signature?

    // Create argv.
    const size_t argc = 1 + arguments_length;
    char*        argv[1 + argc];
    argv[0] = cstrCopy(program); // Must free().
    for (size_t i = 0; i < arguments_length; ++i) {
        argv[1 + i] = cstrCopy(arguments[i]); // Must free().
    }
    argv[argc] = NULL;

    // Display program to run.
    printf(INFO" Running command '%s", argv[0]);
    for (size_t i = 1; i < argc; ++i) {
        printf(" %s", argv[i]);
    }
    printf("'\n");

    // Finally run program. Sheeeeesh.
    if (-1 == execvp(program, argv)) {
        perror(ERROR" Failed to run command");
        exit(1);
    }

    for (size_t i = 0; i < argc; ++i) {
        free(argv[i]);
        argv[i] = NULL;
    };
}

static const char *const music_file_extensions[] = {
    ".mp3",
    ".flac",
    ".wav",
    ".ogg"
};

NONNULL static bool isMusicFile(const char *const path) {
    assert(path);

    const size_t path_length = strlen(path);

    const char* file_extension  = path + path_length - 1;
    size_t      characters_left = path_length;
    while (0 < characters_left) {
        if ('.' == *file_extension || '/' == *file_extension) break;
        --file_extension;
        --characters_left;
    }

    for (size_t i = 0; i < ARRAY_SIZE(music_file_extensions); ++i) {
        if (0 == strcmp(file_extension, music_file_extensions[i])) {
            return true;
        }
    }
    return false;
}

////////////////////////////////////////////////////////////////////////////////
// Playlists                                                                  //
////////////////////////////////////////////////////////////////////////////////

// Zero initialized.
// Deinitialize with playlist_deinit().
typedef struct {
    size_t size;
    size_t count;
    char** songs; // File paths.
} Playlist;

static const size_t playlist_initial_size = 50;

NONNULL static void playlistDeinit(Playlist *const playlist) {
    assert(playlist);

    for (size_t i = 0; i < playlist->count; ++i) free(playlist->songs[i]);
    free(playlist->songs);
}

// Takes ownership of passed in path.
NONNULL static void playlistAppendOwnedSong(
    Playlist *const playlist,
    char *const     path
) {
    assert(playlist);
    assert(path);

    if (playlist->count == playlist->size) {
        if (0 == playlist->size) {
            playlist->size = playlist_initial_size;
        } else {
            playlist->size *= 2;
        }
        playlist->songs =
            realloc(playlist->songs, playlist->size * sizeof(const char*));
    }

    playlist->songs[playlist->count] = path;
    ++playlist->count;
}

// If match is not NULL, only songs whose filename matches the regex will be
// added to the playlist.
// Returns the number of songs appended.
NONNULL_ARGUMENTS(1,2) static size_t playlistAppendFromDirectory(
    Playlist *const   playlist,
    const char *const path,
    regex_t *const    match
) {
    assert(playlist);
    assert(path);

    size_t songs_appended = 0;

    DIR* dir = opendir(path); // Must closedir();
    if (NULL == dir) {
        perror(ERROR" Unable to open directory");
        exit(1);
    }
    while (true) {
        const struct dirent *const entry = readdir(dir);
        if (NULL == entry) break;

        if (!isMusicFile(entry->d_name)) continue;

        if (match && 0 != regexec(match, entry->d_name, 0, NULL, 0)) {
            continue;
        }

        char* file = // Must free(). 1 for null terminator, 1 for '/'.
            calloc(1 + 1 + strlen(path) + strlen(entry->d_name), 1);
        strcat(strcat(strcat(file, path), "/"), entry->d_name);
        playlistAppendOwnedSong(playlist, file);

        ++songs_appended;
    }
    closedir(dir);
    dir = NULL;

    return songs_appended;
}

NONNULL static void playlistShuffle(Playlist *const playlist) {
    assert(playlist);

    // https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle
    for (size_t i = 0; i < playlist->count; ++i) {
        const size_t j     = i + (size_t)rand() % (playlist->count - i);
        char *const song   = playlist->songs[i];
        playlist->songs[i] = playlist->songs[j];
        playlist->songs[j] = song;
    }
}

////////////////////////////////////////////////////////////////////////////////
// CLI                                                                        //
////////////////////////////////////////////////////////////////////////////////

// Zero intialized.
typedef struct {
    size_t              count;
    const char *const * data;
} CstrSlice;

// NULL if the cstr slice is empty.
NONNULL static const char* cstrSliceHead(CstrSlice *const slice) {
    assert(slice);

    if (0 == slice->count) return NULL;

    const char *const result = slice->data[0];
    --slice->count;
    ++slice->data;
    return result;
}

#define PARSED_ARGUMENTS_MAX_DIRECTORIES 50

// Zero initialized.
typedef struct {
    const char* program_name;
    bool        dont_shuffle;
    const char* match; // NULL for no matching.
    bool        dont_repeat;

    size_t      directory_count;
    const char* directories[PARSED_ARGUMENTS_MAX_DIRECTORIES];
} ParsedArguments;

NONNULL static void parsedArgumentsAppendDirectory(
    ParsedArguments *const parsed_arguments,
    const char *const      directory
) {
    assert(parsed_arguments);
    assert(directory);

    assert(parsed_arguments->directory_count < PARSED_ARGUMENTS_MAX_DIRECTORIES);
    parsed_arguments->directories[parsed_arguments->directory_count] = directory;
    ++parsed_arguments->directory_count;
}

NONNULL static void printHelp(const char *const program) {
    assert(program);

    printf(
        "Usages:\n"
        "  %s [OPTION...] [--] DIRECTORY...\n"
        "\n"
        "Plays the music files located in DIRECTORY with mpv.\n"
        "\n"
        "Options:\n"
        "  -h, --help    Display help and exit.\n"
        "\n"
        "  -m, --match REGEX\n"
        "    Only plays songs whose file name matches REGEX.\n"
        "    REGEX is interpreted as an extended regular expression (see\n"
        "    regex(3).)\n"
        "\n"
        "  --no-shuffle\n"
        "    Plays the songs in the order they appear in the directory\n"
        "    instead of randomly shuffling them.\n"
        "\n"
        "  --no-repeat\n"
        "    Exits once all the songs have been played instead of repeating\n"
        "    them in an endless loop.\n",
        program
    );
}

NONNULL static void printShortHelp(FILE *const to, const char *const program) {
    assert(to);
    assert(program);

    fprintf(to, "Try '%s -h' for more information\n", program);
}

// Zero initialized.
typedef enum {
    ARGUMENT_PARSER_BASE = 0,
    ARGUMENT_PARSER_END_OF_OPTIONS,
    ARGUMENT_PARSER_MATCH
} ArgumentParserState;

// options is the list of short options without the preceeding '-'.
NONNULL static void parseShortOptions(
    CstrSlice *const       arguments,
    ParsedArguments *const parsed_arguments,
    const char *const      options
) {
    assert(arguments);
    assert(parsed_arguments);
    assert(options);

    const char* next = options;
    while ('\0' != *next) {
        switch (*next) {
        case 'h': {
            printHelp(parsed_arguments->program_name);
            exit(0);
        }

        case 'm': {
            ++next;
            // If there is leftover options, it is the argument to -m.
            if ('\0' != *next) {
                parsed_arguments->match = next;
                return;
            }
            // Else, the next argument is.
            const char *const next_argument = cstrSliceHead(arguments);
            printf("got: %s\n", next_argument);
            if (NULL == next_argument) {
                fprintf(
                    stderr,
                    ERROR" Option '-m' expects a regular expression as an argument\n"
                );
                printShortHelp(stderr, parsed_arguments->program_name);
                exit(1);
            }
            parsed_arguments->match = next_argument;
            return;
        }

        default: {
            fprintf(stderr, ERROR" Unknown option '-%c'\n", *next);
            printShortHelp(stderr, parsed_arguments->program_name);
            exit(1);
        }
        }

        ++next;
    }
}

NONNULL static ParsedArguments parseArguments(
    const int                argc,
    const char *const *const argv
) {
    assert(argv);
#ifndef NDEBUG
    for (int i = 0; i < argc; ++i) assert(argv[i]);
#endif

    CstrSlice arguments = {
        .count = (size_t)argc,
        .data  = argv
    };
    ParsedArguments     parsed_arguments = {0};
    ArgumentParserState state            = {0};

    parsed_arguments.program_name = cstrSliceHead(&arguments);

    while (true) {
        switch (state) {
        case ARGUMENT_PARSER_BASE: {
            const char *const next = cstrSliceHead(&arguments);
            if (NULL == next)      goto largument_parser_end;
            if (0 == strlen(next)) break;

            if (0 == strcmp("--help", next)) {
                printHelp(parsed_arguments.program_name);
                exit(0);
            }
            if (0 == strcmp("--no-shuffle", next)) {
                parsed_arguments.dont_shuffle = true;
                break;
            }
            if (0 == strcmp("--match", next)) {
                state = ARGUMENT_PARSER_MATCH;
                break;
            }
            if (0 == strcmp("--no-repeat", next)) {
                parsed_arguments.dont_repeat = true;
                break;
            }
            if (0 == strcmp("--", next)) {
                state = ARGUMENT_PARSER_END_OF_OPTIONS;
                break;
            }
            if (0 == strncmp("--", next, 2)) {
                fprintf(stderr, ERROR" Unknown option '%s'\n", next);
                exit(1);
            }
            if ('-' == next[0]) {
                // + 1 to skip '-'.
                parseShortOptions(&arguments, &parsed_arguments, 1 + next);
                break;
            }

            parsedArgumentsAppendDirectory(&parsed_arguments, next);
            break;
        }

        case ARGUMENT_PARSER_END_OF_OPTIONS: {
            const char *const next = cstrSliceHead(&arguments);
            if (NULL == next) goto largument_parser_end;
            parsedArgumentsAppendDirectory(&parsed_arguments, next);
            break;
        }

        case ARGUMENT_PARSER_MATCH: {
            const char *const next = cstrSliceHead(&arguments);
            if (NULL == next) {
                fprintf(
                    stderr,
                    ERROR" Option '--match' expects a regular expression as an argument\n"
                );
                printShortHelp(stderr, parsed_arguments.program_name);
                exit(1);
            }
            parsed_arguments.match = next;
            state = ARGUMENT_PARSER_BASE;
            break;
        }

        default: {
            assert(false && "unreachable");
            exit(1);
        }
        }
    }
largument_parser_end:

    return parsed_arguments;
}

// TODO: add configuration file.
// TODO: add way to specify arguments for mpv?
// TODO: add way to override supported file extensions.

int main(const int argc, const char *const *const argv) {
    // Intialize random number generator.
    struct timespec time;
    if (-1 == clock_gettime(CLOCK_MONOTONIC, &time)) {
        perror(ERROR" Failed to read from monotonic clock");
        exit(1);
    }
    srand((unsigned int)time.tv_sec);

    const ParsedArguments arguments = parseArguments(argc, argv);

    if (0 == arguments.directory_count) {
        fprintf(stderr, ERROR" No directories specified\n");
        printShortHelp(stderr, arguments.program_name);
        exit(1);
    }

    regex_t regex;
    if (arguments.match) {
        const int result = // Must regfree().
            regcomp(&regex, arguments.match, REG_EXTENDED | REG_ICASE);

        if (0 != result) {
            const size_t error_size = regerror(result, &regex, NULL, 0);
            char error[error_size];
            regerror(result, &regex, error, error_size);
            fprintf(
                stderr,
                ERROR" Failed to compile match expression '%s': %s\n",
                arguments.match, error
            );
            exit(1);
        }
    }

    Playlist playlist = {0};

    for (size_t i = 0; i < arguments.directory_count; ++i) {
        const char *const directory = arguments.directories[i];
        printf(INFO" Loading music from directory '%s'...\n", directory);
        const size_t songs_loaded =
            playlistAppendFromDirectory(
                &playlist,
                directory,
                arguments.match ? &regex : NULL
            );

        if (0 == songs_loaded) {
            fprintf(stderr, WARN" Directory empty. Skipping...\n");
            continue;
        }
    }

    if (arguments.match) regfree(&regex);

    if (!arguments.dont_shuffle) playlistShuffle(&playlist);

    if (0 == playlist.count) {
        fprintf(stderr, ERROR" No songs loaded\n");
        exit(1);
    } else {
        printf(INFO" %zu songs loaded\n", playlist.count);
    }

    do {
        for (size_t song = 0; song < playlist.count; ++song) {
            static const char* args[1];
            args[0] = playlist.songs[song];
            runCommand("mpv", args, ARRAY_SIZE(args));
        }
    } while (!arguments.dont_repeat);

    playlistDeinit(&playlist);

    return 0;
}
