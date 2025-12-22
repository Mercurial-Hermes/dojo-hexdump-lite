const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    const program_name = args.next() orelse "error";

    const trg_file_path = args.next() orelse {
        try printUsage();
        return error.InvalidUsage;
    };

    const file = try std.fs.cwd().openFile(trg_file_path, .{ .mode = .read_only });
    defer file.close();

    stdout.print("Correct call.  Arg[0] {s} Arg[1] {s}\n", .{ program_name, trg_file_path }) catch |err| {
        try stderr.print("Error: {any}\n", .{err});
        return error.FileReadError;
    };
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: hdl <file>\n", .{});
}
