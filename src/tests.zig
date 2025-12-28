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
    errdefer allocator.free(result.stdout);
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
    errdefer allocator.free(result.stdout);
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

// the below set of tests where added in Act 5 Scene 2
test "--length 0 produces silence" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll("ABCDEFGH");

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--length", "0", path },
    );
    defer allocator.free(output);

    try std.testing.expectEqualStrings("", output);
}

test "--length shorter than row truncates cleanly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll("ABCDEFGH");

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--length", "3", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  41 42 43                                          |ABC             |
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--length aligns with partial final row rules" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();

    const data = [_]u8{
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09,
    };
    try file.writeAll(&data);

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--length", "9", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  00 01 02 03 04 05 06 07  08                       |.........       |
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--offset plus length exceeding EOF produces silence past EOF" {
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
        &.{ "zig-out/bin/hdl", "--offset", "1", "--length", "10", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000001  42 43                                             |BC              |
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

// the below set of tests where added in Act 5 Scene 3
test "--no-ascii omits ASCII gutter only" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll("ABCDEFGH");

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const with_ascii = try runHdl(allocator, path);
    defer allocator.free(with_ascii);

    const no_ascii = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--no-ascii", path },
    );
    defer allocator.free(no_ascii);

    const expected =
        \\00000000  41 42 43 44 45 46 47 48
        \\
    ;

    try std.testing.expectEqualStrings(expected, no_ascii);
}

test "--no-ascii preserves row width and spacing" {
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

    const path = try tempFilePath(allocator, &tmp, "row.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--no-ascii", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--no-ascii does not defeat silence" {
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
        &.{ "zig-out/bin/hdl", "--offset", "999", "--no-ascii", path },
    );
    defer allocator.free(output);

    try std.testing.expectEqualStrings("", output);
}

test "--no-ascii with partial final row preserves structural spacing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("partial.bin", .{});
    defer file.close();

    // 10 bytes → partial final row
    const data = [_]u8{
        0x00, 0x01, 0x02, 0x03,
        0x04, 0x05, 0x06, 0x07,
        0x08, 0x09,
    };
    try file.writeAll(&data);

    const path = try tempFilePath(allocator, &tmp, "partial.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--no-ascii", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  00 01 02 03 04 05 06 07  08 09
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--no-ascii preserves full hex geometry on partial row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("partial.bin", .{});
    defer file.close();

    // 10 bytes → partial final row
    const data = [_]u8{
        0x00, 0x01, 0x02, 0x03,
        0x04, 0x05, 0x06, 0x07,
        0x08, 0x09,
    };
    try file.writeAll(&data);

    const path = try tempFilePath(allocator, &tmp, "partial.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--no-ascii", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  00 01 02 03 04 05 06 07  08 09
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--no-ascii partial row preserves column alignment across rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("two_rows.bin", .{});
    defer file.close();

    // 18 bytes → first row full, second row partial
    const data = [_]u8{
        // row 0
        0x00, 0x01, 0x02, 0x03,
        0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b,
        0x0c, 0x0d, 0x0e, 0x0f,
        // row 1 (partial)
        0x10, 0x11,
    };
    try file.writeAll(&data);

    const path = try tempFilePath(allocator, &tmp, "two_rows.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--no-ascii", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f
        \\00000010  10 11
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

// the below set of tests where added in Act 5 Scene 4
test "--base dec renders offset in decimal but preserves layout" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll("ABCD");

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--base", "dec", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  065 066 067 068                                       |ABCD            |
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--base oct renders bytes in octal without altering grouping" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("row.bin", .{});
    defer file.close();

    const row = [_]u8{
        0x08, 0x09, 0x0a, 0x0b,
        0x0c, 0x0d, 0x0e, 0x0f,
    };
    try file.writeAll(&row);

    const path = try tempFilePath(allocator, &tmp, "row.bin");
    defer allocator.free(path);

    const output = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--base", "oct", path },
    );
    defer allocator.free(output);

    const expected =
        \\00000000  010 011 012 013 014 015 016 017                           |........        |
        \\
    ;

    try std.testing.expectEqualStrings(expected, output);
}

test "--base hex matches default output exactly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll("XYZ");

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const default_out = try runHdl(allocator, path);
    defer allocator.free(default_out);

    const hex_out = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--base", "hex", path },
    );
    defer allocator.free(hex_out);

    try std.testing.expectEqualStrings(default_out, hex_out);
}

test "numeric equivalence preserved across bases" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile("data.bin", .{});
    defer file.close();
    try file.writeAll(&[_]u8{ 0x10, 0x11 });

    const path = try tempFilePath(allocator, &tmp, "data.bin");
    defer allocator.free(path);

    const hex_out = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--base", "hex", path },
    );
    defer allocator.free(hex_out);

    const dec_out = try runHdlWithArgs(
        allocator,
        &.{ "zig-out/bin/hdl", "--base", "dec", path },
    );
    defer allocator.free(dec_out);

    // 0x10 == 16, 0x11 == 17
    try std.testing.expect(std.mem.containsAtLeast(u8, dec_out, 1, "16"));
    try std.testing.expect(std.mem.containsAtLeast(u8, dec_out, 1, "17"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hex_out, 1, "10"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hex_out, 1, "11"));
}

test "invalid --base value is rejected" {
    const allocator = std.testing.allocator;

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/hdl", "--base", "binary", "dummy.bin" },
    });

    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    switch (result.term) {
        .Exited => |code| try std.testing.expect(code != 0),
        else => try std.testing.expect(false),
    }
}
