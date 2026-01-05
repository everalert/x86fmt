const Settings = @This();

TabSize: usize,

/// Maximum number of consecutive blank lines; large gaps will be folded to
/// this number. Lines with comments do not count toward blanks.
MaxBlankLines: usize,

/// Comment column, when line is not a standalone comment.
TextComCol: usize,

/// Columns to advance from start of label to instruction. Lines without a
/// label will ignore this setting and inset the instruction by TabSize.
TextInsMinAdv: usize,

/// Columns to advance from start of instruction to operands.
TextOpsMinAdv: usize,

/// Alternate values for ComCol, InsMinGap and OpsMinGap, used only in the
/// data-type section context (e.g. ".data", ".bss", ".tls").
DataComCol: usize,
DataInsMinAdv: usize,
DataOpsMinAdv: usize,

/// Base indentation for different section contexts (e.g. "section .data").
/// Other offsets are added to these depending on the section type.
SecIndentNone: usize,
SecIndentData: usize,
SecIndentText: usize,
SecIndentOther: usize,

pub const default: Settings = .{
    .TabSize = 4,
    .MaxBlankLines = 2,
    .TextComCol = 40,
    .TextInsMinAdv = 12,
    .TextOpsMinAdv = 8,
    .DataComCol = 60,
    .DataInsMinAdv = 16,
    .DataOpsMinAdv = 32,
    .SecIndentNone = 0,
    .SecIndentData = 0,
    .SecIndentText = 0,
    .SecIndentOther = 0,
};
