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

    var reader = file.reader();

    while (true) {
        const b = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| {
                try stderr.print("Read error: {any}\n", .{e});
                return e;
            },
        };

        try stdout.print("{x:0>2} ", .{b});
    }

    try stdout.print("\n", .{});
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: hdl <file>\n", .{});
}
