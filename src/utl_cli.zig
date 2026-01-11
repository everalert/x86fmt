//! Command line parsing utility.
const CLI = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;

const BLAND = @import("utl_branchless.zig").BLAND;

// NOTE: most of the 'business logic' of app_settings.zig should end up here, since
//  a lot of it is strictly generic parsing
// TODO: migrate the "business logic" of app_settings.zig to here, where such
//  logic is not specific to the app; i.e. generalize the cli-specific stuff
// TODO: clean up "value" vs "option" nomenclature; stop using them interchangeably
//  for the sake of clarity, update variable/function names if necessary.
// TODO: some way of associating help documentation with each option, so that
//  help docs can be updated "for free".
// TODO: convert setup workflow to be as comptime-biased as possible, so user can
//  precalculate the cli options and only do minimal setup at runtime.
// FIXME: add tests, particularly cases not necessarily covered by app_settings.zig
// FIXME: add docs comments for the module itself (//!)

// FIXME: this was meant to be for flags specifically, and the intent was that a
//  flag processor will specifically use this list; need to fix nomenclature/usage
//  so that this stops being conflated with general options conceptually.
options: []const Option,

// TODO: ?? RepeatedOption, if going to always show error message on malformed cli
pub const Error = error{ MissingFlagOption, UnknownFlag };

// FIXME: add tests
/// Interface used to implement the logic to process an argument.
///
/// For common use-cases of getting values from flags, wrap the value with a
/// `FlagContext` and use it to generate its associated `Option`.
pub const Option = struct {
    parent: *anyopaque,
    fn_check: *const fn (*const anyopaque, []const []const u8) Error!usize,

    /// Returns the number of arguments consumed by this function. If the return
    /// value is 0, the argument did not match the flag. If the return value is 1
    /// or more, processing for the current argument should short-circuit, and the
    /// argument iterator should be advanced as many times as the return value.
    pub fn Check(self: Option, args: []const []const u8) Error!usize {
        return try self.fn_check(self.parent, args);
    }
};

// FIXME: add tests
/// Creates a flag-based option type, implementing logic for common use-cases of
/// flag parsing. This type acts as the context of a flag for values of simple
/// types, hooking up the parsing logic to a value.
///
/// Use `create`, `createArg` or `createOpt` to create a flag context. Flags can
/// be specified in both a short form (`-flg`) and a long form (`--flag-name`).
/// Use `option` to produce the `Option` used to actually process the flag.
///
/// This type can be used both to set a value when a flag is matched, and read
/// a user-given value associated with the flag. Users provide such values as
/// options across two arguments, in the form `--flag-name <value>`. If either
/// functionality is not desired, set that type to `void`.
///
/// Both argument and user-given values can only be set once, by checking whether
/// the value matches the default. This way, multiple flags can be associated with
/// the same value without interfering with each other during parsing.
///
/// For cases where a default argument value is not desired (e.g. for a setting
/// that is usually derived from context, but provided as an option to the user
/// to override), the intended pattern is to use a nullable type as an intermediary.
pub fn FlagContext(comptime ArgT: type, comptime OptT: type) type {
    comptime assert(ArgT != void or OptT != void);
    comptime assert(t: switch (@typeInfo(ArgT)) {
        .bool, .@"enum", .void => true,
        .optional => |t| if (t.child != void) continue :t @typeInfo(t.child) else false,
        else => |t| @compileError("unsupported type: " ++ @typeName(ArgT) ++ " (" ++ @tagName(t) ++ ")"),
    });
    comptime assert(switch (@typeInfo(OptT)) {
        .pointer => OptT == []const u8,
        .int => |t| t.signedness == .unsigned,
        .void => true,
        else => |t| @compileError("unsupported type: " ++ @typeName(OptT) ++ " (" ++ @tagName(t) ++ ")"),
    });

    return struct {
        short: []const u8, // -<opt>
        long: []const u8, // --<opt>

        /// A value that gets set if you get a match on the flag. Useful for
        /// managing multiple flags that are competing for the same value.
        /// If not needed, set `ArgT` to `void`.
        arg: if (ArgT != void) *ArgT else void,
        arg_default: ArgT,
        arg_value: ArgT, // sets `arg` to this when option called, if still default

        /// The value of a user-selected option. If not needed, set `OptT` to `void`.
        opt: if (OptT != void) *OptT else void,
        opt_default: OptT,

        const Context = @This();
        const ValidCreateFunctionMessage = blk: {
            if (OptT == void) break :blk "use `createArg` function instead";
            if (ArgT == void) break :blk "use `createOpt` function instead";
            break :blk "use `create` function instead";
        };

        /// Ensures creation of a valid `FlagContext(ArgT, OptT)`. Default values
        /// are taken from the current values of `arg.*` and `opt.*`.
        pub fn create(arg: *ArgT, arg_val: ArgT, opt: *OptT, short: []const u8, long: []const u8) Context {
            if (comptime ArgT == void) @compileError(ValidCreateFunctionMessage);
            if (comptime OptT == void) @compileError(ValidCreateFunctionMessage);
            assert_flags(short, long);
            return Context{
                .short = short,
                .long = long,
                .arg = arg,
                .arg_default = arg.*,
                .arg_value = arg_val,
                .opt = opt,
                .opt_default = opt.*,
            };
        }

        /// Ensures creation of a valid `FlagContext(ArgT, void)`. The current value
        /// in `arg.*` is used as the default value.
        pub fn createArg(arg: *ArgT, arg_val: ArgT, short: []const u8, long: []const u8) Context {
            if (comptime OptT != void) @compileError(ValidCreateFunctionMessage);
            assert_flags(short, long);
            return Context{
                .short = short,
                .long = long,
                .arg = arg,
                .arg_default = arg.*,
                .arg_value = arg_val,
                .opt = {},
                .opt_default = {},
            };
        }

        /// Ensures creation of a valid `FlagContext(void, OptT)`. The current
        /// value in `opt.*` is used as the default value.
        pub fn createOpt(opt: *OptT, short: []const u8, long: []const u8) Context {
            if (comptime ArgT != void) @compileError(ValidCreateFunctionMessage);
            assert_flags(short, long);
            return Context{
                .short = short,
                .long = long,
                .opt = opt,
                .opt_default = opt.*,
                .arg = {},
                .arg_default = {},
                .arg_value = {},
            };
        }

        /// Create `Option` for this instance, to be used in the CLI's option
        /// list.
        pub fn option(self: *Context) Option {
            return .{
                .parent = @ptrCast(self),
                .fn_check = fn_check,
            };
        }

        fn fn_check(parent: *const anyopaque, args: []const []const u8) Error!usize {
            assert(args.len > 0);
            const self: *const Context = @ptrCast(@alignCast(parent));

            if (!eql(u8, args[0], self.short) and !eql(u8, args[0], self.long))
                return 0;

            // stage one (arg-value) step

            // NOTE: at some point, a comptime switch to handle supported types
            //  should go here, but for now we use direct assignment because all
            //  currently supported types can be trivially compared. this should
            //  compile error in the event that's no longer true.
            if ((comptime ArgT != void) and self.arg.* == self.arg_default)
                self.arg.* = self.arg_value;

            // stage two (opt-value) step

            if (comptime OptT == void)
                return 1;

            if (args.len == 1)
                return error.MissingFlagOption;

            const b_value_is_default: bool = switch (comptime @typeInfo(OptT)) {
                .pointer => BLAND(
                    self.opt.*.len == self.opt_default.len,
                    self.opt.*.ptr == self.opt_default.ptr,
                ),
                .int => self.opt.* == self.opt_default,
                else => unreachable, // already asserted, void dealt with
            };

            if (b_value_is_default) switch (comptime @typeInfo(OptT)) {
                .pointer => self.opt.* = args[1],
                .int => self.opt.* = std.fmt.parseUnsigned(u32, args[1], 0) catch self.opt_default,
                else => unreachable, // already asserted, void dealt with
            };

            return 2;
        }

        // TODO: ?? assert args only have letters, numbers and '-'
        // TODO: ?? better assert the form of the short flag
        fn assert_flags(short: []const u8, long: []const u8) void {
            assert(short.len > 0 or long.len > 0);
            assert(short.len == 0 or (short.len > 1 and startsWith(u8, short, "-")));
            assert(long.len == 0 or (long.len > 2 and startsWith(u8, long, "--")));
        }
    };
}
