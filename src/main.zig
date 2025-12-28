const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    const stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    var width: usize = 16;
    _ = args.next(); // consume arg[0]

    const arg1 = args.next() orelse {
        try printUsage();
        return error.InvalidUsage;
    };

    var trg_file_path: []const u8 = undefined;
    var start_offset: usize = 0;

    if (std.mem.eql(u8, arg1, "--offset")) {
        const offset_str = args.next() orelse {
            try stderr.print("Missing value for --offset\n", .{});
            return error.InvalidUsage;
        };
        start_offset = try std.fmt.parseInt(usize, offset_str, 10);

        trg_file_path = args.next() orelse {
            try printUsage();
            return error.InvalidUsage;
        };
    } else if (std.mem.eql(u8, arg1, "--width")) {
        const width_str = args.next() orelse {
            try stderr.print("Missing value for --width\n", .{});
            return error.InvalidUsage;
        };
        width = try std.fmt.parseInt(usize, width_str, 10);

        trg_file_path = args.next() orelse {
            try printUsage();
            return error.InvalidUsage;
        };
    } else {
        trg_file_path = arg1;
    }

    if (args.next() != null) {
        try printUsage();
        return error.InvalidUsage;
    }

    const file = try std.fs.cwd().openFile(trg_file_path, .{ .mode = .read_only });
    defer file.close();

    try file.seekTo(start_offset);
    var offset: usize = start_offset;

    const CHUNK_SIZE = 16;
    var reader = file.reader();
    var buf: [CHUNK_SIZE]u8 = undefined;

    var row_buf = try std.heap.page_allocator.alloc(u8, width);
    defer std.heap.page_allocator.free(row_buf);

    var row_len: usize = 0;

    while (true) {
        const n = reader.read(&buf) catch |e| {
            try stderr.print("Read error: {any}\n", .{e});
            return e;
        };

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
