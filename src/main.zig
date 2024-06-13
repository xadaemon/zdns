const std = @import("std");
const Allocator = std.mem.Allocator;
const Thead = std.Thread;
const Mutex = Thead.Mutex;
const net = std.net;
const posix = std.posix;
const process = std.process;
const print = std.debug.print;

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    const socket = try std.posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    try set_fnctl_flag(socket, posix.SOCK.NONBLOCK, true);
    defer posix.close(socket);

    const ip = process.getEnvVarOwned(alloc, "ZDNS_BIND_ADDR") catch "127.0.0.1";
    const port = try std.fmt.parseInt(u16, process.getEnvVarOwned(alloc, "ZDNS_BIND_PORT") catch "5000", 10);

    const addr = try net.Address.parseIp4(ip, port);

    try posix.bind(socket, &addr.any, addr.getOsSockLen());

    print("Listening on {any}\n", .{addr});

    while (true) {
        try on_message(alloc, socket);
    }
}

fn set_fnctl_flag(fd: posix.fd_t, flag: usize, set: bool) posix.FcntlError!void {
    var flags = try posix.fcntl(fd, posix.F.GETFL, 0);
    flags = if (set) flags | flag else flags & ~flag;
    _ = try posix.fcntl(fd, posix.F.SETFL, flags);
}

/// Handle a client message on the sock
fn on_message(alloc: Allocator, sock: posix.socket_t) !void {
    var client_addr: posix.sockaddr = undefined;
    var client_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
    var rec_buf: [0x10000]u8 = undefined;

    const n_rd = posix.recvfrom(sock, rec_buf[0..], 0, &client_addr, &client_addr_len) catch |err| {
        if (err == posix.RecvFromError.WouldBlock) {
            return;
        } else {
            return err;
        }
    };
    const buf = try alloc.alloc(u8, 0x10000);
    std.mem.copyBackwards(u8, buf, rec_buf[0..n_rd]);
    print("Read {any} bytes\nDispatching to replier\n", .{n_rd});

    try handle_message(alloc, sock, buf, n_rd, &client_addr, client_addr_len);
    errdefer alloc.free(buf);
}

fn handle_message(alloc: Allocator, sock: posix.socket_t, buf: []const u8, read: usize, client_addr: ?*const posix.sockaddr, client_addr_len: posix.socklen_t) !void {
    const peer_addr = (client_addr orelse return posix.SendToError.AddressNotAvailable).*;
    var peer_addr_parsed: net.Address = undefined;
    if (peer_addr.family == posix.AF.INET) {
        peer_addr_parsed = net.Address.initIp4(peer_addr.data[2..6], std.mem.readInt(u16, peer_addr.data[0..2], std.builtin.Endian.big));
    }
    const n_wt = try posix.sendto(sock, buf[0..read], 0, client_addr, client_addr_len);
    print("replied with {any} bytes to client @ {any}\n", .{ n_wt, peer_addr_parsed });
    // Free the buffer that gets allocated by on_message
    defer alloc.free(buf);
}
