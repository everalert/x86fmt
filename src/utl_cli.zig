//! Command line parsing utility. This module provides a structured way of converting
//! the content of an argument list into application values and behaviours.
//!
//! `Option`
//! Interface for implementing argument behaviours. Helper types ("contexts")
//! that implement common parsing behaviours are provided.
//!
//! `flags`
//! Flag-based options denoted by `-` or `--`. Use `FlagContext` for implementation of
//! common usage patterns, such as setting a pre-set value and taking user input.
//! Add the actual `Option`s using `AddFlag` and `AddFlags`.
//!
//! `default_option`
//! Standard option for unscoped arguments. For an `Option` that pipes a freestanding
//! argument to an upstream value, use `UserOptionContext`.
//!
//! General workflow:
//!
//!  1. Instantiate the CLI via `empty` or `initCapacity`.
//!  2. Implement any behaviours using `Option` or its helpers (see above).
//!  3. Populate `flags` and `default_option` (see above).
//!  4. Process the arguments with `ParseArguments`.
//!  5. If needed, free memory. The preferred way is to use an arena,
//!     but `Deinit` is provided for completeness.
//!
//! For further details on functionality of individual pieces and other such
//! notes, see the comments throughout the implementation.
const CLI = @This();

// TODO: "command" functionality that simply associates a keyword argument with a
//  child CLI. using the same CLI type as a child means that each command can have
//  all the same functionality with its own scope. if going with this, there will
//  need to be a way for a CLI to communicate to the parent that its scope is done.
// TODO: some way of associating help documentation with each option, so that
//  help docs can be updated "for free".
// TODO: convert setup workflow to be as comptime-biased as possible, so user can
//  precalculate the cli options and only do minimal setup at runtime.

// NOTE: nomenclature
//  - "option" refers to an atomic user-provided input, i.e. a single argument
//  - "value" refers to any upstream variable affected by the cli input
//  - "flag" refers to a customization that only affects one or two values, or
//    an otherwise self-contained and preferably trivial value scope

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;

// TODO: reconsider how/if stuff going into this should have enforced "flag shape"
/// Flag-based options.
///
/// Flags are assumed to have a form similar to `-flg` or `--flag-name`. During
/// parsing, only arguments starting with `-` will actually be processed by this
/// list.
///
/// For common flag use-cases and inbuilt checking of the expected flag form,
/// use `FlagContext` to generate `Option`s for this list. For comptime checking
/// that a flag is using a standardized context, use the `AddFlag` and `AddFlags`
/// helpers to add the `Option`s to this list.
flags: ArrayList(*const Option),

/// `Option` for handling any arguments that aren't caught by other handlers. Use
/// this to deal with any freestanding arguments that aren't meant to be scoped
/// by a label.
default_option: *const Option,

pub const Error = error{
    // flags
    FlagUnknown,
    FlagConflict,
    FlagOptionMissing,
    // custom input
    OptionRepeated,
    OptionInvalid,
    // misc
    AllocationError,
};

pub const empty: CLI = .{
    .flags = .empty,
    .default_option = &.stub,
};

pub inline fn initCapacity(alloc: Allocator, amt_flags: usize) Error!CLI {
    var cli: CLI = .empty;
    cli.flags.ensureUnusedCapacity(alloc, amt_flags) catch return error.AllocationError;
    return cli;
}

/// Must be called if adding `Option`s to `flags`.
pub fn Deinit(self: *CLI, alloc: Allocator) void {
    self.default_option = &.stub;
    self.flags.clearAndFree(alloc);
}

pub fn ParseArguments(self: *CLI, args: []const []const u8) Error!void {
    var arg_i: usize = 0;
    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        const args_remaining = args[arg_i..];

        // flags
        if (arg[0] == '-') {
            if (opt: {
                for (self.flags.items) |opt| {
                    const n = try opt.Check(args_remaining);
                    if (n > 0) {
                        arg_i += n - 1;
                        break :opt true;
                    }
                }
                break :opt false;
            }) continue;
            return error.FlagUnknown;
        }

        // default option
        const n = try self.default_option.Check(args_remaining);
        arg_i += n -| 1;
    }
}

/// Add a single `Option` to the flags list, via an option context.
pub fn AddFlag(self: *CLI, alloc: Allocator, comptime ContextT: type, context: *const ContextT) Error!void {
    comptime assert(@hasField(ContextT, "option"));
    comptime assert(@FieldType(ContextT, "option") == Option);
    self.flags.append(alloc, &context.option) catch return error.AllocationError;
}

/// Add an array of `Option`s to the flags list, via an array of option contexts.
pub fn AddFlags(self: *CLI, alloc: Allocator, comptime ContextT: type, context: []const ContextT) Error!void {
    comptime assert(@hasField(ContextT, "option"));
    comptime assert(@FieldType(ContextT, "option") == Option);
    self.flags.ensureUnusedCapacity(alloc, context.len) catch return error.AllocationError;
    for (context) |*ctx|
        self.flags.appendAssumeCapacity(&ctx.option);
}

/// Interface used to implement the logic to process an argument.
///
/// For common use-cases of getting values from flags, wrap the value with a
/// `FlagContext` and use it to generate an `Option`.
///
/// For non-flag use-cases that simply read a user value, wrap the output value
/// with a `UserOptionContext` and use it to generate an `Option`.
pub const Option = struct {
    check: *const fn (*const Option, []const []const u8) Error!usize,

    /// Option that does nothing, for use as a harmless default behaviour.
    pub const stub: Option = .{ .check = null_fn_check };

    /// Returns the number of arguments consumed by this function. If the return
    /// value is 0, the argument did not match the flag. If the return value is 1
    /// or more, processing for the current argument should short-circuit, and the
    /// argument iterator should be advanced as many times as the return value.
    pub fn Check(o: *const Option, args: []const []const u8) Error!usize {
        assert(args.len > 0);
        return try o.check(o, args);
    }

    fn null_fn_check(o: *const Option, args: []const []const u8) Error!usize {
        _ = o;
        _ = args;
        return 1;
    }
};

// ------------------------------------
// "batteries included" option contexts
// ------------------------------------

// TODO: prevent flags themselves repeating? currently, flags can technically
//  repeat if they aren't associated with a value or the value they set is the
//  same as the default, so you could actually physically repeat them, even
//  though it would have no effect in current impl. however, this is only not an
//  issue because of the current usage's (lack of) coverage
/// Creates a flag-based option type, implementing logic for common use-cases of
/// flag parsing. This type acts as the context of a flag for values of simple
/// types, hooking up the parsing logic to a value.
///
/// Use `create`, `createArg` or `createOpt` to create a flag context. Flags can
/// be specified in both a short form (`-flg`) and a long form (`--flag-name`).
/// Get the `Option` used to actually process the flag from `option`, or simply
/// pass the object into `AddFlag` or `AddFlags`.
///
/// This type can be used both to set a value when a flag is matched, and read
/// a user-given value associated with the flag. Users provide such values as
/// options across two arguments, in the form `--flag-name <value>`. If either
/// functionality is not desired, set that type to `void`.
///
/// Both argument and user-given values can only be set once. This is done by
/// checking whether the value matches the default. This way, multiple flags can
/// be associated with the same value without interfering with each other.
///
/// For cases where a default argument value is not desired (e.g. for a setting
/// that is usually derived from context, but provided as an option to the user
/// to override), the intended pattern is to use a nullable type as an intermediary.
pub fn FlagContext(comptime ArgT: type, comptime OptT: type) type {
    comptime {
        assert(ArgT != void or OptT != void);
        assert_user_option_type(OptT, true);
        assert(t: switch (@typeInfo(ArgT)) {
            .bool, .@"enum", .void => true,
            .optional => |t| if (t.child != void) continue :t @typeInfo(t.child) else false,
            else => |t| @compileError("unsupported type: " ++ @typeName(ArgT) ++ " (" ++ @tagName(t) ++ ")"),
        });
    }

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

        option: Option,

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
            return internal_create(arg, arg_val, opt, short, long);
        }

        /// Ensures creation of a valid `FlagContext(ArgT, void)`. The current value
        /// in `arg.*` is used as the default value.
        pub fn createArg(arg: *ArgT, arg_val: ArgT, short: []const u8, long: []const u8) Context {
            if (comptime OptT != void) @compileError(ValidCreateFunctionMessage);
            return internal_create(arg, arg_val, null, short, long);
        }

        /// Ensures creation of a valid `FlagContext(void, OptT)`. The current
        /// value in `opt.*` is used as the default value.
        pub fn createOpt(opt: *OptT, short: []const u8, long: []const u8) Context {
            if (comptime ArgT != void) @compileError(ValidCreateFunctionMessage);
            return internal_create(null, null, opt, short, long);
        }

        inline fn internal_create(
            arg: ?*ArgT,
            arg_val: ?ArgT,
            opt: ?*OptT,
            short: []const u8,
            long: []const u8,
        ) Context {
            assert_flag_shape(short, long);
            return Context{
                .arg = if (comptime ArgT == void) {} else arg orelse unreachable,
                .arg_default = if (comptime ArgT == void) {} else if (arg) |a| a.* else unreachable,
                .arg_value = if (comptime ArgT == void) {} else arg_val orelse unreachable,
                .opt = if (comptime OptT == void) {} else opt orelse unreachable,
                .opt_default = if (comptime OptT == void) {} else if (opt) |o| o.* else unreachable,
                .short = short,
                .long = long,
                .option = .{ .check = fn_check },
            };
        }

        fn fn_check(o: *const Option, args: []const []const u8) Error!usize {
            const self: *const Context = @alignCast(@fieldParentPtr("option", o));

            if (!eql(u8, args[0], self.short) and !eql(u8, args[0], self.long))
                return 0;

            // stage one (arg-value) step

            if (comptime ArgT != void) {
                // NOTE: at some point, a comptime switch to handle supported types
                //  should go here, but for now we use direct assignment because all
                //  currently supported types can be trivially compared. this should
                //  compile error in the event that's no longer true.
                if (self.arg.* == self.arg_default) {
                    self.arg.* = self.arg_value;
                } else {
                    return error.FlagConflict;
                }
            }

            // stage two (opt-value) step

            if (comptime OptT == void)
                return 1;

            if (!user_option_check_default(OptT, self.opt, self.opt_default))
                return error.FlagConflict;

            if (args.len == 1)
                return error.FlagOptionMissing;

            return 1 + try user_option_assign(OptT, self.opt, args[1..]);
        }

        // TODO: ?? assert args only have letters, numbers and '-'
        // TODO: ?? better assert the form of the short flag
        fn assert_flag_shape(short: []const u8, long: []const u8) void {
            assert(short.len > 0 or long.len > 0);
            assert(short.len == 0 or (short.len > 1 and startsWith(u8, short, "-")));
            assert(long.len == 0 or (long.len > 2 and startsWith(u8, long, "--")));
        }
    };
}

// FIXME: add tests
/// Context that simply takes in an argument and parses it as a value.
pub fn UserOptionContext(comptime OptT: type) type {
    comptime assert_user_option_type(OptT, false);

    return struct {
        opt: if (OptT != void) *OptT else void,
        opt_default: OptT,

        option: Option,

        const Context = @This();

        /// Ensures creation of a valid `UserOptionContext(OptT)`. The current
        /// value in `opt.*` is used as the default value.
        pub fn create(opt: *OptT) Context {
            return Context{
                .opt = opt,
                .opt_default = opt.*,
                .option = .{ .check = fn_check },
            };
        }

        fn fn_check(o: *const Option, args: []const []const u8) Error!usize {
            const self: *const Context = @alignCast(@fieldParentPtr("option", o));
            if (!user_option_check_default(OptT, self.opt, self.opt_default))
                return error.OptionRepeated;
            return try user_option_assign(OptT, self.opt, args);
        }
    };
}

// -----------------------
// user option common logic
// -----------------------

inline fn assert_user_option_type(comptime T: type, comptime allow_void: bool) void {
    assert(switch (@typeInfo(T)) {
        .pointer => T == []const u8,
        .int => |t| t.signedness == .unsigned,
        .void => allow_void,
        else => |t| @compileError("unsupported type: " ++ @typeName(T) ++ " (" ++ @tagName(t) ++ ")"),
    });
}

inline fn user_option_check_default(comptime T: type, opt: *T, def: T) bool {
    return switch (comptime @typeInfo(T)) {
        .pointer => eql(u8, opt.*, def), // .pointer should always be []const u8
        .int => opt.* == def,
        else => unreachable, // already asserted, void dealt with
    };
}

// FIXME: need to error if argument cannot be interpreted as the expected type
/// Attempt to assign user value. Assumes `user_option_check_default` already
/// used to assert that the value should be set.
inline fn user_option_assign(comptime T: type, opt: *T, args: []const []const u8) Error!usize {
    assert(args.len > 0);
    switch (comptime @typeInfo(T)) {
        .pointer => opt.* = args[0], // .pointer should always be []const u8
        .int => opt.* = std.fmt.parseUnsigned(u32, args[0], 0) catch return error.OptionInvalid,
        else => unreachable, // already asserted, void dealt with
    }
    return 1;
}

// -------
// testing
// -------

// TODO: test UserOptionContext; punted because logic is currently implicitly
//  already tested via FlagContext (calls same functions for opts) and seems
//  like a pita, but should get around to it eventually.
//  -> all opt types
//  -> conflicts between opts sharing same target value
//  -> error case: opts being written to twice
//  -> error case: invalid user values for all types
// TODO: ?? test other error cases? allocation errors? stuff to do with default
//  opts, like args remaining when no default opt to handle it? etc. (idk if
//  that default opts stuff should be enforced by the cli system)
// TODO: ?? test option contexts and other parts of the cli structure individually,
//  rather than by setting up a full pipeline, so that all the pieces are tested
//  without any unnecessary co-dependencies at the individual test level?
test "CLI" {
    // stripped-down usage implementation modeled after x86fmt/src/app_settings.zig
    const TestTarget = struct {
        const TestTarget = @This();

        val_string: []const u8,
        val_enum: TestEnum,
        val_u32: u32,
        val_u64: u64,
        val_bool: bool,
        val_nullable_enum: ?TestEnum,

        pub const empty: TestTarget = .{
            .val_string = &.{},
            .val_enum = .no,
            .val_u32 = 0,
            .val_u64 = 0,
            .val_bool = false,
            .val_nullable_enum = null,
        };

        const TestEnum = enum { no, yes, maybe };

        /// Test API
        /// basic flags:
        /// -ae     --arg-enum-val                  --> val_enum
        /// -ab     --arg-bool-val                  --> val_bool
        /// -ane    --arg-nullenum-val              --> val_nullable_enum
        /// -os     --opt-string-val                --> val_string
        /// -ou     --opt-u32-val                   --> val_u32
        /// -aoes   --argopt-enum-string-val        --> val_enum, val_string
        /// -aobu   --argopt-bool-u32-val           --> val_bool, val_u32
        /// -aoneu  --argopt-nullenum-u64-val       --> val_nullable_enum, val_u64
        /// second set of flags for checking opts competing for values:
        /// -ae2    --arg-enum-val-2                --> val_enum
        /// -ab2    --arg-bool-val-2                --> val_bool
        /// -ane2   --arg-nullenum-val-2            --> val_nullable_enum
        /// -os2    --opt-string-val-2              --> val_string
        /// -ou2    --opt-u32-val-2                 --> val_u32
        pub fn ParseArguments(
            self: *TestTarget,
            alloc: Allocator,
            args: []const []const u8,
        ) Error!void {
            const FlagArgEnumT = CLI.FlagContext(TestEnum, void);
            const FlagArgBoolT = CLI.FlagContext(bool, void);
            const FlagArgNullableEnumT = CLI.FlagContext(?TestEnum, void);
            const FlagOptStrT = CLI.FlagContext(void, []const u8);
            const FlagOptU32T = CLI.FlagContext(void, u32);
            const FlagArgEnumOptStrT = CLI.FlagContext(TestEnum, []const u8);
            const FlagArgBoolOptU32T = CLI.FlagContext(bool, u32);
            const FlagArgNullableEnumOptU64T = CLI.FlagContext(?TestEnum, u64);
            const amt_flags: usize = 13;

            const ctx_enum = [_]FlagArgEnumT{
                .createArg(&self.val_enum, .yes, "-ae", "--arg-enum-val"),
                .createArg(&self.val_enum, .yes, "-ae2", "--arg-enum-val-2"),
            };
            const ctx_bool = [_]FlagArgBoolT{
                .createArg(&self.val_bool, true, "-ab", "--arg-bool-val"),
                .createArg(&self.val_bool, true, "-ab2", "--arg-bool-val-2"),
            };
            const ctx_nullable_enum = [_]FlagArgNullableEnumT{
                .createArg(&self.val_nullable_enum, .yes, "-ane", "--arg-nullenum-val"),
                .createArg(&self.val_nullable_enum, .yes, "-ane2", "--arg-nullenum-val-2"),
            };
            const ctx_string = [_]FlagOptStrT{
                .createOpt(&self.val_string, "-os", "--opt-string-val"),
                .createOpt(&self.val_string, "-os2", "--opt-string-val-2"),
            };
            const ctx_u32 = [_]FlagOptU32T{
                .createOpt(&self.val_u32, "-ou", "--opt-u32-val"),
                .createOpt(&self.val_u32, "-ou2", "--opt-u32-val-2"),
            };
            const ctx_enum_str: FlagArgEnumOptStrT =
                .create(&self.val_enum, .yes, &self.val_string, "-aoes", "--argopt-enum-string-val");
            const ctx_bool_u32: FlagArgBoolOptU32T =
                .create(&self.val_bool, true, &self.val_u32, "-aobu", "--argopt-bool-u32-val");
            const ctx_nullable_enum_u64: FlagArgNullableEnumOptU64T =
                .create(&self.val_nullable_enum, .yes, &self.val_u64, "-aoneu", "--argopt-nullenum-u64-val");

            var cli: CLI = try .initCapacity(alloc, amt_flags);
            defer cli.Deinit(alloc);
            //cli.default_option = void;
            try cli.AddFlags(alloc, FlagArgEnumT, &ctx_enum);
            try cli.AddFlags(alloc, FlagArgBoolT, &ctx_bool);
            try cli.AddFlags(alloc, FlagArgNullableEnumT, &ctx_nullable_enum);
            try cli.AddFlags(alloc, FlagOptStrT, &ctx_string);
            try cli.AddFlags(alloc, FlagOptU32T, &ctx_u32);
            try cli.AddFlag(alloc, FlagArgEnumOptStrT, &ctx_enum_str);
            try cli.AddFlag(alloc, FlagArgBoolOptU32T, &ctx_bool_u32);
            try cli.AddFlag(alloc, FlagArgNullableEnumOptU64T, &ctx_nullable_enum_u64);
            assert(cli.flags.items.len == amt_flags);

            try cli.ParseArguments(args);
        }
    };

    const TestCase = struct {
        in: []const [:0]const u8,
        ex: TestTarget = .empty,
        err: ?Error = null,
    };

    const test_cases = [_]TestCase{
        // FlagContext: all arg types functional
        .{
            .in = &.{ "-ae", "-ab", "-ane" },
            .ex = blk: {
                var ex: TestTarget = .empty;
                ex.val_enum = .yes;
                ex.val_bool = true;
                ex.val_nullable_enum = .yes;
                break :blk ex;
            },
        },
        .{
            .in = &.{ "--arg-enum-val", "--arg-bool-val", "--arg-nullenum-val" },
            .ex = blk: {
                var ex: TestTarget = .empty;
                ex.val_enum = .yes;
                ex.val_bool = true;
                ex.val_nullable_enum = .yes;
                break :blk ex;
            },
        },
        // FlagContext: all opt types functional
        .{
            .in = &.{ "-os", "str", "-ou", "10" },
            .ex = blk: {
                var ex: TestTarget = .empty;
                ex.val_string = "str";
                ex.val_u32 = 10;
                break :blk ex;
            },
        },
        .{
            .in = &.{ "--opt-string-val", "str", "--opt-u32-val", "10" },
            .ex = blk: {
                var ex: TestTarget = .empty;
                ex.val_string = "str";
                ex.val_u32 = 10;
                break :blk ex;
            },
        },
        // FlagContext: all arg-opt types functional (all transitioned from and to)
        .{
            .in = &.{ "-aoes", "str", "-aobu", "10", "-aoneu", "20" },
            .ex = blk: {
                var ex: TestTarget = .empty;
                ex.val_string = "str";
                ex.val_enum = .yes;
                ex.val_bool = true;
                ex.val_u32 = 10;
                ex.val_u64 = 20;
                ex.val_nullable_enum = .yes;
                break :blk ex;
            },
        },
        .{
            .in = &.{
                "--argopt-enum-string-val",  "str",
                "--argopt-bool-u32-val",     "10",
                "--argopt-nullenum-u64-val", "20",
            },
            .ex = blk: {
                var ex: TestTarget = .empty;
                ex.val_string = "str";
                ex.val_enum = .yes;
                ex.val_bool = true;
                ex.val_u32 = 10;
                ex.val_u64 = 20;
                ex.val_nullable_enum = .yes;
                break :blk ex;
            },
        },
        // FlagContext: all arg types detect reuse of output value
        .{ .in = &.{ "-ae", "--arg-enum-val" }, .err = error.FlagConflict }, // same contexts
        .{ .in = &.{ "-ab", "--arg-bool-val" }, .err = error.FlagConflict },
        .{ .in = &.{ "-ane", "--arg-nullenum-val" }, .err = error.FlagConflict },
        .{ .in = &.{ "-ae", "-ae2" }, .err = error.FlagConflict }, // different contexts
        .{ .in = &.{ "-ab", "-ab2" }, .err = error.FlagConflict },
        .{ .in = &.{ "-ane", "-ane2" }, .err = error.FlagConflict },
        // FlagContext: all opt types confirm presence of user input
        .{ .in = &.{"-os"}, .err = error.FlagOptionMissing },
        .{ .in = &.{"-ou"}, .err = error.FlagOptionMissing },
        // FlagContext: all opt types confirm valid user input
        // NOTE: no check for string; never invalid at the single-flag level
        .{ .in = &.{ "-ou", "not-a-number" }, .err = error.OptionInvalid },
        // FlagContext: all opt types detect reuse of output value
        .{ .in = &.{ "-os", "str", "--opt-string-val", "str" }, .err = error.FlagConflict }, // same ctx
        .{ .in = &.{ "-ou", "10", "--opt-u32-val", "10" }, .err = error.FlagConflict },
        .{ .in = &.{ "-os", "str", "-os2", "str" }, .err = error.FlagConflict }, // dif ctx
        .{ .in = &.{ "-ou", "10", "-ou2", "10" }, .err = error.FlagConflict },
        // FlagContext: all opt types prioritize confirming value reuse over checking input
        .{ .in = &.{ "-os", "str", "--opt-string-val" }, .err = error.FlagConflict },
        .{ .in = &.{ "-ou", "10", "--opt-u32-val" }, .err = error.FlagConflict },
        // FlagContext: invalid/unknown flag
        .{ .in = &.{"--will-never-be-a-real-flag-surely"}, .err = error.FlagUnknown },
    };

    const alloc = std.testing.allocator;
    std.testing.log_level = .debug;
    for (test_cases, 0..) |t, i| {
        errdefer {
            const input = std.mem.join(alloc, " ", t.in) catch |err| @errorName(err);
            defer alloc.free(input);
            std.debug.print("FAILED {d:0>2} :: \x1B[33m{s}\x1B[0m\n\n", .{ i, input });
        }

        var target: TestTarget = .empty;
        const result = target.ParseArguments(alloc, t.in);

        try std.testing.expectEqual(t.err orelse {}, result);
        if (t.err == null) try std.testing.expectEqualDeep(t.ex, target);
    }
}
