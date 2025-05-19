# play-music

A simple command-line music player.

Currently depends on mpv to play the songs, but this will be integrated into
play-music in the future.

## How to Build

Dependencies

- zig 0.14.0 (other versions may work) - [https://ziglang.org](https://ziglang.org/).
- mpv - [https://mpv.io/](https://mpv.io/)

There is a `flake.nix` you can use with `nix develop` to get them.

Then, run the following command(s):

```shell
zig build-exe play-music.zig
```

You can append the following arguments for different optimizations:

- `-O ReleaseSafe` - Faster.
- `-O ReleaseFast` - Fasterer, no safety checks.
- `-O ReleaseSmall` - Faster, smaller binaries, no safety checks.

I.e.:

```sh
zig build-exe play-music.zig -O ReleaseFast
```

The executable will be named `play-music`.

## Installation

You can install it with Nix from my personal package repository
[https://paltepuk.xyz/cgit/epitaphpkgs.git/about](https://paltepuk.xyz/cgit/epitaphpkgs.git/about).
