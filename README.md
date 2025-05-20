# play-music

A simple command-line music player.

Currently depends on other programs to play the songs, but this will be
integrated into play-music in the future.

Available play strategies (in order of priority):

1. With mpv [https://mpv.io/](https://mpv.io/), if present.
2. With cvlc [https://www.videolan.org/vlc/](https://www.videolan.org/vlc/), if present.

## How to Build

Dependencies:

- zig 0.14.0 (other versions may work) - [https://ziglang.org](https://ziglang.org/).

There is a `flake.nix` you can use with `nix develop` to get them.

Then, run the following command(s):

```shell
zig build
```

You can append the following arguments for different optimizations:

- `-Doptimize=ReleaseSafe` - Faster.
- `-Doptimize=ReleaseFast` - Fasterer, no safety checks.
- `-Doptimize=ReleaseSmall` - Faster, smaller binaries, no safety checks.

I.e.:

```sh
zig build -Doptimize=ReleaseFast
```

The executable will appear in `zig-out/bin/`.

## Installation

You can install it with Nix from my personal package repository
[https://paltepuk.xyz/cgit/epitaphpkgs.git/about](https://paltepuk.xyz/cgit/epitaphpkgs.git/about).
