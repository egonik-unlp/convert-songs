const std = @import("std");
const httpz = @import("httpz");
const base64 = std.base64;
const http = std.http;
const compilation_options = @import("compilation_options");
const env = @import("env.zig");
const State = struct { mutex: std.Thread.Mutex, token: ?TokenResponse, state_string: ?[14]u8, wg: std.Thread.WaitGroup };
const REDIRECT_URI = if (compilation_options.remote_compile) "http://convert-songs.work.gd:8888/callback" else "http://localhost:8888/callback";

pub const Oauth2Flow = struct {
    port: u16,
    server: httpz.Server(*State),
    allocator: std.mem.Allocator,
    state: *State,
    pub fn build(port: u16, allocator: std.mem.Allocator) !Oauth2Flow {
        var state = try allocator.create(State);
        state.token = null;
        state.mutex = .{};
        state.wg = .{};
        var server = try httpz.Server(*State).init(
            allocator,
            .{
                .port = port,
                .address = "0.0.0.0",
            },
            state,
        );
        var router = try server.router(.{});
        router.get("/", default_endpoint, .{});
        router.get("/login", login_handler, .{});
        router.get("/callback", callback_handler, .{});
        router.get("/", default_endpoint, .{});
        router.get("/get_login", login_handler, .{});
        router.get("/callback", callback_handler, .{});
        return Oauth2Flow{ .port = port, .server = server, .allocator = allocator, .state = state };
    }
    pub fn run(self: *Oauth2Flow) !std.Thread {
        std.debug.print("\nOAuth 2 server running.\nOpen {s} to run oauth flow\n", .{REDIRECT_URI});
        self.state.mutex.lock();
        defer self.state.mutex.unlock();
        self.state.wg.start();
        return self.server.listenInNewThread() catch |err| {
            std.debug.print("Error lauching server: {}", .{err});
            self.state.wg.finish();
            return err;
        };
    }
    pub fn wait_and_close(self: *Oauth2Flow) void {
        self.state.wg.wait();
        self.server.stop();
    }
};
fn default_endpoint(_: *State, req: *httpz.Request, res: *httpz.Response) !void {
    std.debug.print("Answering request\n", .{});
    res.status = 200;
    const response_body = try std.fmt.allocPrint(req.arena, "Para completar el flujo de autentificaion ir a {s}", .{REDIRECT_URI});
    res.body = response_body;
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

fn generateRandomString() ![14]u8 {
    const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    var buffer: [14]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    for (0..buffer.len) |pos| {
        const rnd_val = prng.random().intRangeAtMost(usize, 0, charset.len);
        buffer[pos] = charset[rnd_val];
    }
    return buffer;
}

fn login_handler(
    state: *State,
    _: *httpz.Request,
    response: *httpz.Response,
) !void {
    std.debug.print("OAuth2 flow after response flow running\n", .{});
    const random_state = try generateRandomString();
    state.mutex.lock();
    state.state_string = random_state;
    state.mutex.unlock();
    const qp = QueryParams.build(
        env.client_id,
        "playlist-modify-private playlist-modify-public",
        REDIRECT_URI,
        &random_state,
    );

    const url = try std.fmt.allocPrint(response.arena, "{s}", .{qp});
    std.debug.print("Full redirect to Spotify URL: {s}\n", .{url});

    response.header("Location", url);
    response.status = 303;
    // response.headers.add("Location", url);
    response.header("Content-Type", "text/html; charset=UTF-8");
    const headers = response.*.headers;
    _ = headers;
}
fn callback_handler(state: *State, req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    const string_state = lift: {
        state.mutex.lock();
        defer state.mutex.unlock();
        break :lift state.state_string orelse unreachable;
    };
    if (query.get("code")) |code| {
        const request_state = query.get("state") orelse "no anda esto";
        std.debug.print("del state viene {d} del request viene {d}\n", .{ request_state, string_state });
        try request_token(code, req.arena, state);
    } else if (query.get("error")) |err| {
        std.debug.print("ERRROR = {any}", .{err});
    } else {
        res.status = 500;
        res.body = "Esta funcion no debe ser llamada sin argumentos";
    }
    std.debug.print("Frontera de lo conocido\n", .{});
    state.mutex.lock();
    state.wg.finish();
    state.mutex.unlock();
    std.debug.print("Surpassed\n", .{});
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
    const body = try std.fmt.allocPrint(allocator, "{s}", .{body_});
    const url = try std.Uri.parse("https://accounts.spotify.com/api/token");
    var buffer: [100]u8 = undefined;
    const encoder = base64.standard.Encoder;
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
    std.debug.print("Spotify raw response:\n{s}\n", .{response_storage.items});

    _ = result;
    const token = try std.json.parseFromSlice(TokenResponse, allocator, response_storage.items, .{ .ignore_unknown_fields = true });
    std.debug.print("Retrieved token = \n{any}\n", .{token.value});
    state.mutex.lock();
    state.token = token.value;
    state.mutex.unlock();
}
