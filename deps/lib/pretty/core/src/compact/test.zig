const namespace = @import("root.zig");
const std = @import("std");

const cap = @import("cap.zig");
const table_mod = @import("table.zig");

const Align = namespace.Align;
const Column = namespace.Column;
const Table = namespace.Table;
const TableLimits = namespace.TableLimits;
const TableCapacity = namespace.TableCapacity;
const TableRenderError = namespace.TableRenderError;
const table = namespace.table;
const cap16kb = namespace.cap16kb;
const truncation_line = namespace.truncation_line;
const full_cap = namespace.full_cap;
const body_budget = namespace.body_budget;
test "compact namespace" {
    std.testing.refAllDecls(table_mod);
    std.testing.refAllDecls(cap);
}
