const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    _ = args.next(); // consume arg[0]

    const trg_file_path = args.next() orelse {
        try printUsage();
        return error.InvalidUsage;
    };

    const file = try std.fs.cwd().openFile(trg_file_path, .{ .mode = .read_only });
    defer file.close();

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
            try stdout.print("{d:8} {x:0>2}\n", .{ offset, b });
            offset += 1;
        }
    }

    try stdout.print("\n", .{});
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: hdl <file>\n", .{});
}
