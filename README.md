# play-music

A simple command-line music player.

Currently depends on mpv to play the songs, but this will be integrated into
play-music in the future.

## How to Build

Dependencies

- A C compiler supporting c11. Clang, GCC, or Zig recommended.
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

## Installation

You can install it with Nix from my personal package repository
[https://paltepuk.xyz/cgit/epitaphpkgs.git/about](https://paltepuk.xyz/cgit/epitaphpkgs.git/about).
