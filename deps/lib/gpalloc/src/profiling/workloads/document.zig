const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn run(allocator: std.mem.Allocator) void {
    var fonts: [parameters.document_trace_font_count]?[]u8 = @as([parameters.document_trace_font_count]?[]u8, @splat(null));

    {
        const font_phase = bench.phaseAt("gpalloc.phase.document_trace.font_cache", @src());
        defer font_phase.end();

        for (&fonts, 0..) |*font, index| {
            const bytes = allocator.alloc(u8, 1024 + (index % 7) * 256) catch @panic("allocation failed");
            bytes[0] = @truncate(index);
            font.* = bytes;
        }
    }

    var page: usize = 0;
    while (page < parameters.document_trace_page_count) : (page += 1) {
        var glyphs: [parameters.document_trace_glyph_count]Record = undefined;
        var images: [parameters.document_trace_image_count]Record = undefined;

        {
            const layout_phase = bench.phaseAt("gpalloc.phase.document_trace.layout", @src());
            defer layout_phase.end();

            for (&glyphs, 0..) |*glyph, index| {
                const bytes = allocator.alloc(u8, 32 + ((index + page) % 6) * 16) catch @panic("allocation failed");
                bytes[0] = @truncate(index + page);
                glyph.* = .{ .bytes = bytes };
            }
        }

        {
            const raster_phase = bench.phaseAt("gpalloc.phase.document_trace.raster", @src());
            defer raster_phase.end();

            for (&images, 0..) |*image, index| {
                const bytes = allocator.alloc(u8, imageSize(index, page)) catch @panic("allocation failed");
                bytes[0] = @truncate(index + page);
                image.* = .{ .bytes = bytes };
            }
        }

        {
            const compose_phase = bench.phaseAt("gpalloc.phase.document_trace.compose", @src());
            defer compose_phase.end();

            const page_buffer = allocator.alloc(u8, 48 * 1024 + page * 2048) catch @panic("allocation failed");
            page_buffer[0] = @truncate(page);
            std.mem.doNotOptimizeAway(page_buffer.ptr);
            allocator.free(page_buffer);
        }

        {
            const release_phase = bench.phaseAt("gpalloc.phase.document_trace.release", @src());
            defer release_phase.end();

            for (images) |image| {
                std.mem.doNotOptimizeAway(image.bytes.ptr);
                allocator.free(image.bytes);
            }
            for (glyphs) |glyph| {
                std.mem.doNotOptimizeAway(glyph.bytes.ptr);
                allocator.free(glyph.bytes);
            }
        }

        coz.progressNamed("gpalloc.phase.document_trace.page");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.document_trace.drain", @src());
        defer drain_phase.end();

        for (&fonts) |*font| {
            const bytes = font.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            font.* = null;
        }
    }
}

fn imageSize(index: usize, page: usize) usize {
    const sizes = [_]usize{
        8 * 1024,
        16 * 1024,
        32 * 1024,
        64 * 1024,
        96 * 1024,
        128 * 1024,
    };
    return sizes[(index + page * 2) % sizes.len];
}
