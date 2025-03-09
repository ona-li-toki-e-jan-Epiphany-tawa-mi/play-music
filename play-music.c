#define _POSIX_C_SOURCE 199309L
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// POSIX.
#include <dirent.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

////////////////////////////////////////////////////////////////////////////////
// Utilities                                                                  //
////////////////////////////////////////////////////////////////////////////////

#define ARRAY_SIZE(array) (sizeof(array)/sizeof((array)[0]))

/*
 * Checks that all pointer parameters to a function are not NULL.
 * Works in GCC and clang.
 */
#ifdef __GNUC__
#  define NONNULL __attribute__ ((nonnull))
#else // __GNUC__
#  define NONNULL
#endif

// Deinitialize with free();
NONNULL static char* cstrCopy(const char *const cstr) {
    assert(cstr);

    char *const result = calloc(1 + strlen(cstr), 1);
    if (NULL == result) {
        perror("ERROR: failed to allocate memory. Buy more RAM lol");
        exit(1);
    }
    return strcpy(result, cstr);
}

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
        perror("ERROR: Failed to spawn child process");
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
    printf("INFO: Running command '%s", argv[0]);
    for (size_t i = 1; i < argc; ++i) {
        printf(" %s", argv[i]);
    }
    printf("'\n");

    // Finally run program. Sheeeeesh.
    if (-1 == execvp(program, argv)) {
        perror("ERROR: failed to run command");
        exit(1);
    }

    for (size_t i = 0; i < argc; ++i) {
        free(argv[i]);
        argv[i] = NULL;
    };
}

// TODO: support more extensions.
static const char *const music_file_extensions[] = {
    ".mp3"
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

// Deinitialize with playlistDeinit().
NONNULL static Playlist playlistInitFromDirectory(const char *const path) {
    assert(path);

    Playlist playlist = {0};

    DIR* dir = opendir(path); // Must closedir();
    if (NULL == dir) {
        perror("ERROR: Unable to open directory");
        exit(1);
    }
    while (true) {
        const struct dirent *const entry = readdir(dir);
        if (NULL == entry) break;

        if (!isMusicFile(entry->d_name)) continue;

        char* file = // Must free(). 1 for null terminator, 1 for '/'.
            calloc(1 + 1 + strlen(path) + strlen(entry->d_name), 1);
        strcat(strcat(strcat(file, path), "/"), entry->d_name);
        playlistAppendOwnedSong(&playlist, file);
    }
    closedir(dir);
    dir = NULL;

    return playlist;
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

NONNULL static void display_help(const ParsedArguments *const parsed_arguments) {
    assert(parsed_arguments);

    assert(parsed_arguments->program_name);
    printf(
        "Usages:\n"
        "  %s [OPTION...] DIRECTORY...\n"
        "\n"
        "Plays the music files located in DIRECTORY with mpv.\n"
        "\n"
        "Options:\n"
        "  --help    Display help and exit\n"
        "\n"
        "  --no-shuffle\n"
        "    Plays the songs in the order they appear in the directory\n"
        "    instead of randomly shuffling them.\n",
        parsed_arguments->program_name
    );
}

// Zero initialized.
typedef enum {
    ARGUMENT_PARSER_BASE = 0,
    ARGUMENT_PARSER_END_OF_OPTIONS
} ArgumentParserState;

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
                display_help(&parsed_arguments);
                exit(0);
            }
            if (0 == strcmp("--no-shuffle", next)) {
                parsed_arguments.dont_shuffle = true;
                break;
            }
            if (0 == strcmp("--", next)) {
                state = ARGUMENT_PARSER_END_OF_OPTIONS;
                break;
            }
            if (0 == strncmp("--", next, 2)) {
                fprintf(stderr, "ERROR: Unknown option '%s'\n", next);
                exit(1);
            }
            if ('-' == next[0]) {
                assert(false && "TODO: handle short options");
                exit(1);
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

        default: {
            assert(false && "unreachable");
            exit(1);
        }
        }
    }
largument_parser_end:

    return parsed_arguments;
}

// TODO: add way to filter found songs by name.
// TODO: add configuration file.
// TODO: add way to specify arguments for mpv.

int main(const int argc, const char *const *const argv) {
    // Intialize random number generator.
    struct timespec time;
    if (-1 == clock_gettime(CLOCK_MONOTONIC, &time)) {
        perror("Failed to read from monotonic clock");
        exit(1);
    }
    srand((unsigned int)time.tv_sec);

    const ParsedArguments arguments = parseArguments(argc, argv);

    if (0 == arguments.directory_count) {
        fprintf(stderr, "ERROR: No directories specified\n");
        fprintf(
            stderr,
            "Try '%s --help' for more information\n",
            arguments.program_name
        );
    }

    for (size_t i = 0; i < arguments.directory_count; ++i) {
        const char *const directory = arguments.directories[i];
        printf("INFO: Loading music from directory '%s'\n", directory);
        Playlist playlist = playlistInitFromDirectory(directory);

        if (!arguments.dont_shuffle) playlistShuffle(&playlist);

        for (size_t song = 0; song < playlist.count; ++song) {
            static const char* args[1];
            args[0] = playlist.songs[song];
            runCommand("mpv", args, ARRAY_SIZE(args));
        }

        playlistDeinit(&playlist);
    }

    return 0;
}
