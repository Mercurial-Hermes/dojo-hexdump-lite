const std = @import("std");

fn tempFilePath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir, name: []const u8) ![]u8 {
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    return try std.fs.path.join(allocator, &.{ dir_path, name });
}

fn runHdl(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/hdl", file_path },
    });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.UnexpectedTermination,
    }

    return result.stdout;
}

fn runHdlWithArgs(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.UnexpectedTermination,
    }

    return result.stdout;
}

test "file shorter than one row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("short.bin", .{});
    defer file.close();
    try file.writeAll("ABC");

    const file_path = try tempFilePath(allocator, &tmp, "short.bin");
    defer allocator.free(file_path);

    const output = try runHdl(allocator, file_path);
    defer allocator.free(output);

    const expected =
        \\00000000  41 42 43                                          |ABC             |
        \\
    ;
    try std.testing.expectEqualStrings(expected, output);
}

test "file exactly one row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("row.bin", .{});
    defer file.close();
    const row = [_]u8{
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    };
    try file.writeAll(&row);

    const file_path = try tempFilePath(allocator, &tmp, "row.bin");
    defer allocator.free(file_path);

    const output = try runHdl(allocator, file_path);
    defer allocator.free(output);

    const expected =
        \\00000000  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f  |................|
        \\
    ;
    try std.testing.expectEqualStrings(expected, output);
}

test "file with a partial final row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("partial.bin", .{});
    defer file.close();
    const data = [_]u8{
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
        0x10, 0x11, 0x12, 0x13,
    };
    try file.writeAll(&data);

    const file_path = try tempFilePath(allocator, &tmp, "partial.bin");
    defer allocator.free(file_path);

    const output = try runHdl(allocator, file_path);
    defer allocator.free(output);

    const expected =
        \\00000000  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f  |................|
        \\00000010  10 11 12 13                                       |....            |
        \\
    ;
    try std.testing.expectEqualStrings(expected, output);
}

test "file containing non-printable bytes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("nonprint.bin", .{});
    defer file.close();
    const data = [_]u8{ 0x00, 0x1f, 0x7f, 0xff };
    try file.writeAll(&data);

    const file_path = try tempFilePath(allocator, &tmp, "nonprint.bin");
    defer allocator.free(file_path);

    const output = try runHdl(allocator, file_path);
    defer allocator.free(output);

    const expected =
        \\00000000  00 1f 7f ff                                       |....            |
        \\
    ;
    try std.testing.expectEqualStrings(expected, output);
}

// the below set of tests where added in Act 5 Scene 1
test "--offset 0 produces identical output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll("ABCDEFGH");

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const out_default = try runHdl(allocator, path);
    defer allocator.free(out_default);

    const out_offset = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--offset", "0", path },
    );
    defer allocator.free(out_offset);

    try std.testing.expectEqualStrings(out_default, out_offset);
}

test "--offset skips bytes but preserves absolute offsets" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll("ABCDEFGHIJKLMNOP");

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--offset", "4", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000004  45 46 47 48 49 4a 4b 4c  4d 4e 4f 50              |EFGHIJKLMNOP    |
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--offset beyond EOF produces silence" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("tiny.bin", .{});
    defer file.close();
    try file.writeAll("ABC");

    const path = try tempFilePath(allocator, &tmp, "tiny.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--offset", "999", path },
    );
    defer allocator.free(output);

    try std.testing.expectEqualStrings("", output);
}
