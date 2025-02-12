const std = @import("std");
const httpz = @import("httpz");
const base64 = std.base64;
const http = std.http;
const env = @import("env.zig");

const REDIRECT_URI = "http://localhost:8888/callback";

pub const Oauth2Flow = struct {
    port: u16,
    server: httpz.ServerCtx(void, void),
    allocator: std.mem.Allocator,
    pub fn build(port: u16, allocator: std.mem.Allocator) !Oauth2Flow {
        var server = try httpz.Server().init(
            allocator,
            .{ .port = port },
        );
        const router = server.router();
        router.get("/", handleta);

        return Oauth2Flow{ .port = port, .server = server, .allocator = allocator };
    }
    pub fn run(self: *Oauth2Flow) !std.Thread {
        return try self.server.listenInNewThread();
    }
};
fn handleta(_: *httpz.Request, res: *httpz.Response) !void {
    std.debug.print("Answering request\n", .{});
    res.status = 200;
    res.body = "ANDA ESTO";
}

const StateWrapper = struct {
    lock: std.Thread.Mutex,
    data: ?TokenResponse,
    pub fn build() StateWrapper {
        return TokenResponse{
            .lock = std.Thread.Mutex{},
            .data = null,
        };
    }
    pub fn update(self: *StateWrapper, token: TokenResponse) !void {
        self.lock.lock();
        defer self.lock.unlock();
        self.data = token;
    }
    pub fn isDefined(self: *StateWrapper) bool {
        if (self.data != null) true else false;
    }
};
const TokenQueryParams = struct {
    grant_type: []const u8,
    code: []const u8,
    redirect_uri: []const u8,
    pub fn format(
        self: @This(),
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("grant_type={s}&redirect_uri={s}&code={s}", .{ self.grant_type, self.redirect_uri, self.code });
    }
};
const QueryParams = struct {
    client_id: []const u8,
    scope: []const u8,
    redirect_uri: []const u8,
    state: []const u8,
    pub fn format(
        self: @This(),
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("https://accounts.spotify.com/authorize?response_type=code&client_id={s}&scope={s}&redirect_uri={s}&state={s}", .{ self.client_id, self.scope, self.redirect_uri, self.state });
    }
    pub fn build(cid: []const u8, scope: []const u8, redirect_uri: []const u8, state: []const u8) QueryParams {
        return QueryParams{ .client_id = cid, .scope = scope, .state = state, .redirect_uri = redirect_uri };
    }
};

const TokenResponse = struct {
    access_token: []u8,
    token_type: []u8,
    expires_in: i32,
    refresh_token: []u8,
    scope: []u8,
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    server = try httpz.Server().init(arena.allocator(), .{ .port = 8888 });
    var router = server.router();
    router.get("/login", login_handler);
    router.get("/callback", callback_handler);
    try server.listen();
    const thread = try server.listenInNewThread();
    defer thread.join();
}

fn login_handler(_: *httpz.Request, response: *httpz.Response) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const qp = QueryParams.build(
        client_id,
        "playlist-modify-private playlist-modify-public",
        "http://localhost:8888/callback",
        "llllllllllllll",
    );

    const url = try std.fmt.allocPrint(response.arena, "{s}", .{qp});
    response.header("Location", url);
    response.status = 303;
    // response.headers.add("Location", url);
    response.header("Content-Type", "text/html; charset=UTF-8");
    const headers = response.*.headers;
    std.debug.print("{s}", .{headers.get("Location").?});
}
fn callback_handler(req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    if (query.get("code")) |code| {
        std.debug.print("state = {s}", .{query.get("state").?});
        try request_token(code, req.arena);
    } else {
        const err = query.get("error").?;
        // _ = err;
        std.debug.print("ERRROR = {any}", .{err});
    }
    res.status = 200;
    res.body = "HOLA";
    defer server_stop();
}

fn request_token(code: []const u8, allocator: std.mem.Allocator) !void {
    var client = http.Client{ .allocator = allocator };
    const body_ = TokenQueryParams{
        .code = code,
        .grant_type = "authorization_code",
        .redirect_uri = REDIRECT_URI,
    };
    var buffer: [100]u8 = undefined;
    const encoder = base64.standard.Encoder;
    const body = try std.fmt.allocPrint(allocator, "{s}", .{body_});
    const url = try std.Uri.parse("https://accounts.spotify.com/api/token");
    const pre64 = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ client_id, client_secret });
    // const pre64 = client_id ++ ":" ++ client_secret;
    const preauth = encoder.encode(&buffer, pre64);
    const auth = try std.fmt.allocPrint(allocator, "Basic {s}", .{preauth});
    var response_storage = std.ArrayList(u8).init(allocator);
    const options = http.Client.FetchOptions{ .location = .{ .uri = url }, .method = .POST, .headers = .{
        .authorization = .{ .override = auth },
        .content_type = .{ .override = "application/x-www-form-urlencoded" },
    }, .response_storage = .{ .dynamic = &response_storage }, .payload = body };
    const result = try client.fetch(options);
    std.debug.print("Result = {any}\nResponse = {s}\n", .{ result.status, response_storage.items });
}

pub fn server_stop() void {
    server.stop();
}
