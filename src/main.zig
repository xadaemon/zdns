const std = @import("std");
const network = @import("network");
const Allocator = std.mem.Allocator;
const Thead = std.Thread;
const log = std.log;

pub const io_mode = .evented;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const ip = std.process.getEnvVarOwned(alloc, "ZDNS_BIND_ADDR") catch "127.0.0.1";
    const port = try std.fmt.parseInt(u16, std.process.getEnvVarOwned(alloc, "ZDNS_BIND_PORT") catch "5000", 10);

    try network.init();
    defer network.deinit();

    var server = try network.Socket.create(.ipv4, .udp);

    try server.bind(.{ .address = .{ .ipv4 = try network.Address.IPv4.parse(ip) }, .port = port });

    log.info("Listening at {any} \n", .{server.getLocalEndPoint()});

    while (true) {
        log.debug("Waiting for client messages\n", .{});
        const client = try Client.new(alloc, server);
        errdefer client.deinit();
        const recv = try server.receiveFrom(client.buf[0..]);
        client.set_received(recv.sender, recv.numberOfBytes);
        try client.handle();
        client.deinit();
    }

    server.close();
}

const SyncRingBuff = struct {
    mutex: Thead.RwLock,
    ring: std.RingBuffer


};

const Client = struct {
    alloc: Allocator,
    conn: network.Socket,
    buf: []u8,
    recvep: network.EndPoint,
    recvnb: usize,

    fn new(alloc: Allocator, conn: network.Socket) !*Client {
        const client = try alloc.create(Client);
        client.buf = try alloc.alloc(u8, 255);
        client.alloc = alloc;
        client.conn = conn;
        return client;
    }

    fn deinit(self: *Client) void {
        self.alloc.free(self.buf);
        self.alloc.destroy(self);
    }

    fn set_received(self: *Client, recvep: network.EndPoint, recvnb: usize) void {
        self.recvep = recvep;
        self.recvnb = recvnb;
    }

    fn handle(self: *Client) !void {
        log.debug("Received {any} bytes from peer @ {any}", .{ self.recvnb, self.recvep });

        const renb = try self.conn.sendTo(self.recvep, self.buf[0..self.recvnb]);
        log.debug("Replied with {any} bytes\n", .{renb});
    }
};
