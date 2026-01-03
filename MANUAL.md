# User Manual

`x86fmt` is a utility for formatting assembly source files. It is designed to
work with NASM syntax.

The primary intended use is in conjunction with editors such as `Neovim` in a 
code action context, and it is therefore written for piped I/O as the base case.
However, it is designed with I/O flexibility in mind. Users are able to freely 
mix and match file and stdio modes for input and output.

## Contents

- [Sample Usage](#sample-usage): Quick start with concrete examples.
- [Options](#options): Explanation of all command line options.
- [Known Issues](#known-issues): Things to be aware of such as bugs, unfinished 
  features and esoteric/opinionated design decisions.

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

## Options

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

## Known Issues

- `v1.0.0`: Known Issues not written yet.
