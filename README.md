# x86fmt

x86fmt is an auto-formatter for x86 assembly source code. It is a streaming
formatter with an opinionated style written for NASM syntax.

This program is intended to be used in a code action context, such as format-on-save. 
Opinionated automatic formatting is valuable for two reasons. First, it lets you 
stop fiddling and get on with it by reducing choice (opinionated). Second, it reduces 
the friction of getting code to look consistent (automatic). There seemed to be 
no reasonably good standalone assembly formatter that just works for this use case, 
so I made one for myself.

## Installation

1. Download a release, or compile with `zig build -Doptimize=ReleaseFast`. 
   Compilation requires `zig 0.14.1`.
2. Move the binary to a location accessible to your `PATH`.
3. (Optional) Configure your code editor to run `x86fmt` in a code action, such
   as format-on-save. Refer to [Usage](#usage) and the [MANUAL](MANUAL.md) for 
   configuration options.

## Usage

x86fmt can operate on any combination of files and standard IO for input and output. 
See below for basic usage. For more details and advanced usage, refer to `x86fmt --help` 
and the [MANUAL](MANUAL.md).

```batch
:: With no command line arguments, input is taken from the 
:: stdin pipe and formatted to the stdout pipe. By default, 
:: stdin input is not accepted from a tty.
x86fmt

:: Format a file by adding it to the command:
x86fmt source.s

:: To write the formatted output to a different file, use 
:: the -fo flag:
x86fmt source.s -fo output.s

:: The -fo flag can also specify the output file when 
:: taking input from stdin:
x86fmt -fo output.s

:: Similarly, the -co flag can be used to format a file 
:: to stdout:
x86fmt source.s -co
```

### Zig Module

Zig users can also import the formatter core as a module via the Zig package manager. 

The module uses the package manager semantics introduced in `zig 0.14.0`. Use the 
following command to add it to your `build.zig.zon`:

```
zig fetch --save git+https://github.com/everalert/x86fmt#v1.0.0
```

## Additional Notes

Some caveats and things to be aware of that don't quite fit in their own
section:

- Full length of NASM identifiers is not supported. At the time of writing, per-line
  limitations are: 4095 bytes, 1024 tokens, 1024 lexemes, 256 bytes per token.
	- If these limits are exceeded, formatting will be aborted and only formatted 
      lines before that point will be returned. This behaviour will likely change
      in future to be less user-hostile.
    - These limits are chosen more or less arbitrarily, and are intended to be 
      mostly removed in a future rewrite of the formatter core.
- Minimal semantic analysis. In particular, instructions and most directives are
  not identified by keyword.
    - Token semantics are differentiated primarily by form, and no attempt is made 
      to validate the correctness of the assembly itself.
    - Labels are identified by a trailing colon. Therefore, labels without the
      trailing colon will be formatted as instructions. e.g. `text1: text2` will 
      format `text1` as a label, but `text1 text2` will not.
- Some more complicated formatting situations still look weird, particularly to 
  do with nested indentation such as `struc` instancing. This will be addressed
  in a future rewrite of the formatter core.
- UTF-8 input is enforced, to match NASM requirements. Individual lines with invalid 
  UTF-8 will be passed through unformatted. If the input contains the byte order 
  mark, formatting will be aborted (this will likely change to just passing through 
  the whole input unformatted too). 
- When using `stdin` via terminal emulator with the `-tty` flag, the tty pipe must 
  be closed manually before the text will be formatted; use `ctrl-c` after a newline.
- The formatter will likely be suitable for any Intel-like syntax such as MASM,
  but note that this is not a guarantee.

## Contributing

I will gladly consider any bug reports, documentation feedback and feature requests. 
Feel free to submit them as issues.

Pull requests are NOT welcome. This is in part because I want the experience of 
working on this program as an educational exercise, and in part because I don't 
want to bother managing open source contributions for a project this small. 

## License

[MIT](https://choosealicense.com/licenses/mit/)
