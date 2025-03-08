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

// Must free();
NONNULL static char* cstrCopy(const char *const cstr) {
    assert(cstr);

    char *const result = calloc(1 + strlen(cstr), 1);
    if (NULL == result) {
        perror("ERROR: failed to allocate memory. Buy more RAM lol");
        exit(1);
    }
    return strcpy(result, cstr);
}

NONNULL static void run(
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
    printf("+ %s", argv[0]);
    for (size_t i = 1; i < argc; ++i) {
        printf(" %s", argv[i]);
    }
    printf("\n");

    // Finally run program. Sheeeeesh.
    if (-1 == execvp(program, argv)) {
        perror("TODO: do proper error message");
        exit(1);
    }

    for (size_t i = 0; i < argc; ++i) {
        free(argv[i]);
        argv[i] = NULL;
    };
}

NONNULL static bool isMusicFile(const char *const path) {
    assert(path);
    // TODO.
    return true;
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

    playlist->songs[playlist->count]  = path;
    playlist->count                  += 1;
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

        if (0 == strncmp(".", entry->d_name, 1))  continue;
        if (0 == strncmp("..", entry->d_name, 1)) continue;
        if (!isMusicFile(entry->d_name))        continue;

        char* file = // Must free().
            calloc(1 + strlen(path) + strlen(entry->d_name), 1);
        strcat(strcat(file, path), entry->d_name);
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
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

int main(int argc, char** argv) {
    struct timespec tp;
    if (-1 == clock_gettime(CLOCK_MONOTONIC, &tp)) {
        perror("Failed to read from monotonic clock");
        exit(1);
    }
    srand((unsigned int)tp.tv_sec);

    // 1 - skip program name.
    for (int directory = 1; directory < argc; ++directory) {
        Playlist playlist = playlistInitFromDirectory(argv[directory]);
        playlistShuffle(&playlist);

        for (size_t song = 0; song < playlist.count; ++song) {
            static const char* args[1];
            args[0] = playlist.songs[song];
            run("mpv", args, ARRAY_SIZE(args));
        }

        playlistDeinit(&playlist);
    }

    return 0;
}
