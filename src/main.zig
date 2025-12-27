const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    var width: usize = 16;
    _ = args.next(); // consume arg[0]

    const arg1 = args.next() orelse {
        try printUsage();
        return error.InvalidUsage;
    };

    var trg_file_path: []const u8 = undefined;

    if (std.mem.eql(u8, arg1, "--width")) {
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

    const file = try std.fs.cwd().openFile(trg_file_path, .{ .mode = .read_only });
    defer file.close();

    var col: usize = 0;
    var offset: usize = 0;
    const CHUNK_SIZE = 16;
    var reader = file.reader();
    var buf: [CHUNK_SIZE]u8 = undefined;

    while (true) {
        const n = reader.read(&buf) catch |e| {
            try stderr.print("Read error: {any}\n", .{e});
            return e;
        };

        if (n == 0) break;

        for (buf[0..n]) |b| {
            if (col == 0) {
                try stdout.print("{d:8} ", .{offset});
            }

            try stdout.print("{x:0>2} ", .{b});

            offset += 1;
            col += 1;

            if (col == width) {
                try stdout.print("\n", .{});
                col = 0;
            }
        }
    }

    if (col != 0) {
        try stdout.print("\n", .{});
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: hdl <file>\n", .{});
}
