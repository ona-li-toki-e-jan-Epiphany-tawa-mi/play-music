# play-music

A simple command-line music player.

Currently depends on mpv to play the songs, but this will be integrated into
play-music in the future.

## How to Build

Dependencies

- A C compiler supporting c11. Clang or GCC recommended.
- POSIX system.
- mpv - [https://mpv.io/](https://mpv.io/)

There is a `flake.nix` you can use with `nix develop` to get them.

Then, run the following command(s):

```shell
./build.sh
```

To enable optimizations, you can add one or more of the following arguments to
the EXTRA_CFLAGS enviroment variable:

- `-O3` - general optimizations.
- `-DNDEBUG` - disable safety checks. Performance > safety.

I.e.:

```sh
EXTRA_CFLAGS='-O3 -DNDEBUG' ./build.sh
```

The executable will be named `play-music`.
