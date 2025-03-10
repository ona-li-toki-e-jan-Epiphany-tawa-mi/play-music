/*
 * This file is part of anal.
 *
 * Copyright (c) 2025 ona-li-toki-e-jan-Epiphany-tawa-mi
 *
 * anal is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 *
 * anal is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * anal. If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * anal - S(a)fety-Ta(n)t(a)mount C (L)ibrary.
 */

/*
 * Synopsis:
 *   Adds a variety of extra functions and what-not for making C a wee bit
 *   safer.
 *
 *   Currently just a couple macros to enable more compiler warnings.
 */

/*
 * Usage:
 *   Place `#define ANAL_IMPLEMENTATION` in one, and only one, C file before you
 *   include this file to create the implementation.
 *
 *   I.e.:
 *     #define ANAL_IMPLEMENTATION
 *     #include "anal.h"
 */

/*
 * SOME !!HOT!! TIPS:
 *   Enable a lot of the warnings your C compiler supports:
 *     In GCC, Clang, and zig cc:
 *     - -Wall - A bunch of warnings.
 *     - -Wextra - A bunch more warnings.
 *     - -Wpedantic - Even more warnings.
 *     - -Wconversion - Warn on narrowing type conversions.
 *     - -Wswitch-enum - Warn when a switch() on an enum does not use all enum
 *       values. Good for refactoring and large code bases.
 *     - -Wmissing-prototypes - Warn when a function does not have a prototype
 *       (i.e.: void function(void) { ... }, but no void function(void); before
 *       it,) OR is not declared static (i.e.: static void function(void)
 *       { ... }.) Good for refactoring and large code bases.
 *
 *   LISTEN TO AND FIX THE WARNINGS!!! --^
 *
 *   Set up unit/integration/whatever tests and run all of them with Valgrind's
 *   Memcheck https://valgrind.org/ to identify memory leaks.
 *
 *   Make everything you can const so you can be sure you don't modify anything
 *   you don't need to, or more importantly, shouldn't.
 *
 *   Mark any functions that allocate memory with the function to free that
 *   memory, .i.e:
 *     // Deinitialize with thing_free().
 *     void* thing_alloc(size_t bytes) { ... }
 *
 *   Mark the usages of any functions that return allocated memory with the
 *   function to free that memory, i.e.:
 *     char *const buffer = malloc(256); // Must free().
 *
 *   Set a pointer to NULL after freeing it. Many functions have defined
 *   behavior on NULL pointers, so if you accidentally use it again you'll have
 *   some protection agains use-after-frees. I.e.:
 *     free(pointer);
 *     pointer = NULL;
 *
 *   Please note that these tips are very anal ;). That is the point.
 */

/*
 * Changelog:
 *   0.1.0:
 *   - Initial release.
 */

/*
 * Source (paltepuk):
 *   Clearnet - https://paltepuk.xyz/cgit/anal.git/about/
 *   I2P - http://oytjumugnwsf4g72vemtamo72vfvgmp4lfsf6wmggcvba3qmcsta.b32.i2p/cgit/anal.git/about/
 *   Tor - http://4blcq4arxhbkc77tfrtmy4pptf55gjbhlj32rbfyskl672v2plsmjcyd.onion/cgit/anal.git/about/
 *
 * Source (GitHub):
 *   Clearnet - https://github.com/ona-li-toki-e-jan-Epiphany-tawa-mi/anal/
 */

// TODO find a way to test marcos?
// TODO add safe arithmetic functions.

////////////////////////////////////////////////////////////////////////////////
// Header                                                                     //
////////////////////////////////////////////////////////////////////////////////

#ifndef ANAL_H_
#define ANAL_H_

/*
 * Works in GCC, Clang, and zig cc.
 * Typechecks printf-like functions.
 * format - the index (1-indexed) of the argument that has the format string.
 * va_list - the index (1-indexed) argument that has the variable argument list
 * (as-in '...').
 *
 * Contrived example:
 *
 * void PRINTF_TYPECHECK(1, 2) function(const char *const format, ...) {
 *     // Do stuff...
 * }
 */
#ifdef __GNUC__
#  define PRINTF_TYPECHECK(format, va_list) \
    __attribute__ ((__format__ (printf, format, va_list)))
#else // __GNUC__
#  define PRINTF_TYPECHECK(format, va_list)
#endif

/*
 * Works in GCC, Clang, and zig cc.
 * Checks that all pointer parameters to a function are not NULL.
 *
 * Contrived example:
 *
 * NONNULL void function(const int *const nonnullable) {
 *     // Do stuff...
 * }
 */
#ifdef __GNUC__
#  define NONNULL __attribute__ ((nonnull))
#else // __GNUC__
#  define NONNULL
#endif

/*
 * Works in GCC, Clang, and zig cc.
 * Checks that the specified pointer parameters to a function are not NULL.
 * ... - a list of the indicies (1-indexed) of the arguments that are to be
 * checked.
 *
 * Contrived example:
 *
 * NONNULL_ARGUMENTS(1) void function(
 *     const int *const nonnullable,
 *     const int *const nullable
 * ) {
 *     // Do stuff...
 * }
 */
#ifdef __GNUC__
#  define NONNULL_ARGUMENTS(...) __attribute__ ((nonnull (__VA_ARGS__)))
#else // __GNUC__
#  define NONNULL_ARGUMENTS(...)
#endif

#endif // ANAL_H_

////////////////////////////////////////////////////////////////////////////////
// Implentation                                                               //
////////////////////////////////////////////////////////////////////////////////

#ifdef ANAL_IMPLEMENTATION

// Nothing here yet.

#endif // ANAL_IMPLEMENTATION
