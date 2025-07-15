const std = @import("std");
const httpz = @import("httpz");
const base64 = std.base64;
const http = std.http;
const env = @import("env.zig");
const State = struct {
    mutex: std.Thread.Mutex,
    token: ?TokenResponse,
    allocator: std.mem.Allocator,
};
const REDIRECT_URI = "http://localhost:8888/callback";
pub const Oauth2Flow = struct {
    port: u16,
    server: httpz.Server(*State),
    allocator: std.mem.Allocator,
    state: *State,
    pub fn build(port: u16, allocator: std.mem.Allocator) !Oauth2Flow {
        var state = try allocator.create(State);
        state.token = null;
        state.mutex = .{};
        state.allocator = allocator;
        var server = try httpz.Server(*State).init(allocator, .{ .port = port }, state);
        var router = try server.router(.{});
        router.get("/", handleta, .{});
        router.get("/login", login_handler, .{});
        router.get("/callback", callback_handler, .{});
        return Oauth2Flow{ .port = port, .server = server, .allocator = allocator, .state = state };
    }
    pub fn run(self: *Oauth2Flow) !std.Thread {
        std.debug.print("\nOAuth 2 server running.\nOpen http://localhost:{d}/login to run oauth flow\n", .{self.port});
        return try self.server.listenInNewThread();
    }
};
fn handleta(_: *State, _: *httpz.Request, res: *httpz.Response) !void {
    std.debug.print("Answering request\n", .{});
    res.status = 200;
    res.body = "Para completar el flujo de autenticacion Oauth2 ir a url http://localhost:8888/login";
}

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
    fn generate_string() !void {}
};

const TokenResponse = struct {
    access_token: []u8,
    token_type: []u8,
    expires_in: i32,
    refresh_token: []u8,
    scope: []u8,
    pub fn format(
        self: @This(),
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print(
            "TokenResponse {{ access_token = {s}, token_type = {s}, expires_in = {d}, refresh_token = {s}, scope = {s}}}",
            .{ self.access_token, self.token_type, self.expires_in, self.refresh_token, self.scope },
        );
    }
};

fn login_handler(
    _: *State,
    _: *httpz.Request,
    response: *httpz.Response,
) !void {
    std.debug.print("OAuth2 flow after response flow running\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const qp = QueryParams.build(
        env.client_id,
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
    _ = headers;
    // std.debug.print("{s}", .{headers.get("Location").?});
}
fn callback_handler(state: *State, req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    if (query.get("code")) |code| {
        try request_token(code, req.arena, state);
    } else {
        const err = query.get("error").?;
        // _ = err;
        std.debug.print("ERRROR = {any}", .{err});
    }
    res.status = 200;
    res.body = "Autorizacion correcta";
}

fn request_token(code: []const u8, allocator: std.mem.Allocator, state: *State) !void {
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
    const pre64 = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ env.client_id, env.client_secret });
    const preauth = encoder.encode(&buffer, pre64);
    const auth = try std.fmt.allocPrint(allocator, "Basic {s}", .{preauth});
    var response_storage = std.ArrayList(u8).init(allocator);
    const options = http.Client.FetchOptions{
        .location = .{ .uri = url },
        .method = .POST,
        .headers = .{
            .authorization = .{ .override = auth },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .response_storage = .{ .dynamic = &response_storage },
        .payload = body,
    };
    const result = try client.fetch(options);
    _ = result;
    // std.debug.print("Result = {any}\nResponse = {s}\n", .{ result.status, response_storage.items });
    const parsed = try std.json.parseFromSlice(TokenResponse, allocator, response_storage.items, .{ .ignore_unknown_fields = true });
    std.debug.print("Retrieved token = \n{any}\n", .{parsed.value});
    var token_copy = TokenResponse{
        .access_token = try state.allocator.dupe(u8, parsed.value.access_token),
        .token_type = try state.allocator.dupe(u8, parsed.value.token_type),
        .expires_in = parsed.value.expires_in,
        .refresh_token = try state.allocator.dupe(u8, parsed.value.refresh_token),
        .scope = try state.allocator.dupe(u8, parsed.value.scope),
    };
    state.mutex.lock();
    state.token = token_copy;
    state.mutex.unlock();
}
