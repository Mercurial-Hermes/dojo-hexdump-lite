const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    const stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    var width: usize = 16;
    var start_offset: usize = 0;
    var max_len: ?usize = null;
    var trg_file_path: ?[]const u8 = null;

    _ = args.next(); // argv[0]

    // allow up to two flag-value pairs
    var flags_seen: usize = 0;
    var seen_width = false;
    var seen_offset = false;
    var seen_length = false;

    while (true) {
        const arg = args.next() orelse break;

        if (std.mem.eql(u8, arg, "--width")) {
            if (seen_width) return error.InvalidUsage;
            seen_width = true;

            const v = args.next() orelse return error.InvalidUsage;
            width = try std.fmt.parseInt(usize, v, 10);
            if (width == 0) return error.InvalidUsage;

            flags_seen += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--offset")) {
            if (seen_offset) return error.InvalidUsage;
            seen_offset = true;

            const v = args.next() orelse return error.InvalidUsage;
            start_offset = try std.fmt.parseInt(usize, v, 10);

            flags_seen += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--length")) {
            if (seen_length) return error.InvalidUsage;
            seen_length = true;

            const v = args.next() orelse return error.InvalidUsage;
            max_len = try std.fmt.parseInt(usize, v, 10);

            flags_seen += 1;
            continue;
        }

        // first non-flag is the file path
        trg_file_path = arg;
        break;
    }

    const path = trg_file_path orelse {
        try printUsage();
        return error.InvalidUsage;
    };

    if (path.len == 0) {
        try printUsage();
        return error.InvalidUsage;
    }

    // no trailing arguments allowed
    if (args.next() != null) {
        try printUsage();
        return error.InvalidUsage;
    }

    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    try file.seekTo(start_offset);
    var remaining: ?usize = max_len;
    var offset: usize = start_offset;

    const CHUNK_SIZE = 16;
    var reader = file.reader();
    var buf: [CHUNK_SIZE]u8 = undefined;

    var row_buf = try std.heap.page_allocator.alloc(u8, width);
    defer std.heap.page_allocator.free(row_buf);

    var row_len: usize = 0;

    while (true) {
        const n = blk: {
            if (remaining) |r| {
                if (r == 0) break :blk 0;

                const to_read = @min(buf.len, r);
                const read_n = reader.read(buf[0..to_read]) catch |e| {
                    try stderr.print("Read error: {any}\n", .{e});
                    return e;
                };
                break :blk read_n;
            } else {
                const read_n = reader.read(&buf) catch |e| {
                    try stderr.print("Read error: {any}\n", .{e});
                    return e;
                };
                break :blk read_n;
            }
        };

        if (remaining) |*r| {
            r.* -= n;
        }

        if (n == 0) break;

        for (buf[0..n]) |b| {
            std.debug.assert(row_len < width);
            row_buf[row_len] = b;
            row_len += 1;

            if (row_len == width) {
                try emitRow(stdout, offset, row_buf[0..row_len], width);
                offset += row_len;
                row_len = 0;
            }
        }
    }

    if (row_len != 0) {
        try emitRow(stdout, offset, row_buf[0..row_len], width);
    }
}

fn emitRow(
    stdout: anytype,
    offset: usize,
    row: []const u8,
    width: usize,
) !void {
    // Offset: 8 hex digits, zero-padded
    try stdout.print("{x:0>8}  ", .{offset});

    // Hex region with padding
    var i: usize = 0;
    while (i < width) : (i += 1) {
        if (i < row.len) {
            try stdout.print("{x:0>2}", .{row[i]});
        } else {
            try stdout.print("  ", .{});
        }

        if (i == 7) {
            try stdout.print("  ", .{});
        } else {
            try stdout.print(" ", .{});
        }
    }

    // ASCII gutter
    try stdout.print(" |", .{});
    i = 0;
    while (i < width) : (i += 1) {
        if (i < row.len) {
            const b = row[i];
            const ch: u8 = if (b >= 0x20 and b <= 0x7e) b else '.';
            try stdout.print("{c}", .{ch});
        } else {
            try stdout.print(" ", .{});
        }
    }
    try stdout.print("|\n", .{});
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: hdl <file>\n", .{});
}
