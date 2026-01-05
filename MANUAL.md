# Manual

`x86fmt` is a utility for formatting assembly source files. It is designed to
work with NASM syntax.

The primary intended use is in conjunction with editors such as `Neovim` in a 
code action context, and it is therefore written for piped I/O as the base case.
However, it is designed with I/O flexibility in mind. Users are able to freely 
mix and match file and stdio modes for input and output.

## Contents

- [Sample Usage](#sample-usage)
- [General Usage Notes](#general-usage-notes)
- [Command Line Options](#command-line-options)
- [Zig Module](#zig-module)
- [Known Issues](#known-issues)

## Sample Usage

### Command Line

|Command|Input|Output
|:---|:---|:---|
|`x86fmt (none)`               |`<stdin>` |`<stdout>`
|`x86fmt source.s`             |`source.s`|`source.s`
|`x86fmt source.s -co`         |`source.s`|`<stdout>`
|`x86fmt source.s -fo output.s`|`source.s`|`output.s`
|`x86fmt -fo output.s`         |`<stdin>` |`output.s`

### Code Editors

For an example format-on-save code action setup using `Neovim` and `conform.nvim`, 
see my nvimconf at [this commit](https://github.com/everalert/nvimconf/tree/cc54304c54cc4ddca5933f4629f4888d85060a6a) (search for `conform`).

## General Usage Notes

- Labels must have the `:` postfix to be formatted as a label, i.e. `label:`
- In order of priority, comments align with
    1. the previous line's comment,
    2. the previous line's first non-whitespace character, and
    3. the first column, when following a blank line.
- Input data must be in UTF-8 or ASCII.
- Input containing the UTF byte order mark will be rejected.
- Lines with invalid UTF-8 will be passed through unformatted.
- Command line options are accepted in any order.
- Duplicate or conflicting options are ignored.
- Diagnostic error messages are available via `stderr`.

## Command Line Options

### Default Behaviour

When no command line arguments are given,
- input will be taken from the stdin pipe,
- output will be written to the stdout pipe, and
- truncated help text will be shown if attempting to run it in a terminal emulator.

The actual default I/O semantics are as follows:

- Input mode = Console `<stdin>` (piped)
- Output mode = match input setting
    - i.e. If the input mode is File and the output mode is not specified, the 
      output mode will also be File

### Basic Options

|Flag|Long Flag|Note|
|:---|:---|:---|
|`[file]`    |&nbsp;       |Input mode = File, reading from `[file]`
|`-fo [file]`|&nbsp;       |Output mode = File, writing to `[file]`
|`-co`       |&nbsp;       |Output mode = Console `<stdout>`
|`-tty`      |`--allow-tty`|Accept non-piped input for `<stdin>`; use like a REPL (or a RFPL, I guess)
|`-h`        |`--help`     |Show detailed usage information

### Cosmetic Options

- `text-*` options apply to any `.text`-like section, including `<other>` (any 
  non-data section other than the initial unspecified one).
- `data-*` options apply to any `.data`-like section such as `.bss`, including 
  `<none>` (the initial unspecified section).
- `section-*` options have similar semantics to `text-*` and `data-*`, but `<none>` 
  and `<other>` are considered separately.

|Flag|Long Flag|Default|
|:---|:---|:---|
|`-ts [num]` |`--tab-size [num]`                |`4`
|`-mbl [num]`|`--max-blank-lines [num]`         |`2`
|`-tcc [num]`|`--text-comment-column [num]`     |`40`
|`-tia [num]`|`--text-instruction-advance [num]`|`12`
|`-toa [num]`|`--text-operands-advance [num]`   |`8`
|`-dcc [num]`|`--data-comment-column [num]`     |`60`
|`-dia [num]`|`--data-instruction-advance [num]`|`16`
|`-doa [num]`|`--data-operands-advance [num]`   |`32`
|`-sin [num]`|`--section-indent-none [num]`     |`0`
|`-sid [num]`|`--section-indent-data [num]`     |`0`
|`-sit [num]`|`--section-indent-text [num]`     |`0`
|`-sio [num]`|`--section-indent-other [num]`    |`0`

## Zig Module

Zig users can import the formatter core as a module via the Zig package manager.
As of `v1.0.0`, normal usage of the module should only require `x86fmt.Fmt` and
`x86fmt.Settings`. The other components are made public primarily for the curious.

The module uses the package manager semantics introduced in `zig 0.14.0`. Use the 
following command to add it to your `build.zig.zon`:

```batch
zig fetch --save git+https://github.com/everalert/x86fmt#v1.0.0
```

In your `build.zig`, add `x86fmt` as a dependency to your compile step. Here is 
a minimal example:

```zig
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bin = _; // setup `bin` using `b.addExecutable` or similar here

    const x86fmt_dependency = b.dependency("x86fmt", .{ .target = target, .optimize = optimize });
    const x86fmt_module = x86fmt_dependency.module("x86fmt");
    bin.root_module.addImport("x86fmt", x86fmt_module);
```

The module should now be importable as `x86fmt`.

## Known Issues

Things to be aware of such as bugs, unfinished features and esoteric/opinionated 
design decisions.

- `v1.0.0`: Complex alignment involving nested structures such as macros and struc
  implementations are not yet well handled.
- `v1.0.0`: The `section` directive itself also gets indented using that section's 
  indentation setting.
- `v1.0.0`: Cases where comments may want to align with a property of the following
  line rather than the previous line, such as first line after a label or the line
  immediately following a heavily indented comment, are not yet handled.
- `v1.0.0`: When using `stdin` via terminal emulator with the `-tty` flag, the tty 
  pipe must be closed manually before the text will be formatted; use `ctrl-c` 
  after a newline.
- `v1.0.0`: Full length of NASM identifiers is not supported. However, the 
  limitations in place should be more than generous for normal use. At the time 
  of writing, per-line limitations are: 4095 bytes, 1024 tokens, 1024 lexemes 
  (token chunks), 256 bytes per token. If these limits are exceeded, formatting 
  will be aborted and only formatted lines before that point will be returned. 
  These limits are chosen more or less arbitrarily, and are intended to be mostly 
  removed in a future rewrite of the formatter core.

