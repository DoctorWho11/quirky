/*
 * IrcCore.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey@solus-project.com>
 *
 * This example is provided for an initial proof-of-concept of blocking I/O
 * on IRC in Vala. It will survive here a little longer to ensure we never
 * actually end up with an end project looking anything like this.
 *
 * Updated note: Various utility functions will be developed here first before
 * being split into something more intelligent.
 *
 * Cue rant:
 *
 * Down below you may still see (depending on how much I alter this file) fixed
 * handling of certain numerics, which is increasingly common in newer IRC libraries,
 * clients and bots. "if 0001 in line" is wrong, people.
 * In fact many clients I've seen don't even take a line-buffered approach. While
 * I admit in C we'd read in a buffer, you should still be using a rotating buffer
 * and pulling lines from it, processing them one at a time.
 *

    /* HOW NOT TO IRC. See? Its evil. Imagine, PRIVMSG with a 001 .. -_- 
    if ("001" in line) {
        write_socket("JOIN %s\r\n", ident.default_channel);
    }
    if ("JOIN" in line) {
        write_socket("PRIVMSG %s :%s\r\n", ident.default_channel, ident.hello_prompt);
    }
    if ("PING" in line && !("PRIVMSG" in line)) {
        write_socket("PONG\r\n");
    }
 *
 * End Rant.
 *
 * We'll actually end up with extensive numerics support, tracking of state, and
 * eventually IRCv3 support, along with SASL, multi-prefix, and all that sexy
 * goodness.
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public enum AuthenticationMode
{
    NONE,
    NICKSERV,
    SASL
}

public struct IrcIdentity {
    string username;
    string gecos;
    string nick;
    int mode;
    string password;
    string account_id;
    AuthenticationMode auth;
}

public struct IrcUser {
    string nick;
    string username;
    string hostname;
    bool op;
    bool voice;
}

public enum IrcMessageType {
    PRIVATE = 1 << 0,
    CHANNEL = 1 << 1,
    ACTION  = 1 << 2,
}

public enum IrcConnectionStatus {
    RESOLVING,
    CONNECTING,
    REGISTERING
}

public enum IrcNickError {
    NO_NICK,
    INVALID,
    IN_USE,
    COLLISION,
    UNAVAILABLE,
    RESTRICTED /* We don't use this.. */
}

/**
 * Simple info from a server using RPL_ISUPPORT
 */
public struct ServerInfo {
    int away_length;
    int kick_length;
    int nick_length;
    int topic_length;
    string network;
    bool monitor; /**<Whether the ircd supports the monitor (ircv3) extension*/
    int monitor_max;
}

const string TLS_BANNER = """
@@@@ WARNING @@@@
STARTTLS negotiation failed, this is *still* a plaintext connection!!!
@@@@         @@@@
""";

private struct _olock { int x; }

public class IrcCore : Object
{
    SocketClient? client;
    SocketConnection? conn;
    public IrcIdentity ident;
    Cancellable cancel;

    private ServerInfo sinfo;

    public static int64 sid = 0;
    public int64 id;

    /**
     * 500ms for first read, otherwise force sending of nick to begin negotiation.
     * Basically ensures we work when CAP LS failed.
     */
    const uint READ_TIMEOUT = 500;
    bool got_line = false;

    /* State tracking. */
    private string _motd;

    private HashTable<string,Channel> channels;
    /* Enable query for /NAMES, i.e. channels we're not in yet. */
    private HashTable<string,Channel> channel_cache;

    public signal void joined_channel(IrcUser user, string channel);
    public signal void user_quit(IrcUser user, string quit_msg);
    public signal void messaged(IrcUser user, string target, string message, IrcMessageType type);
    public signal void noticed(IrcUser user, string target, string message, IrcMessageType type);
    public signal void parted_channel(IrcUser user, string channel, string? reason);

    public signal void connecting(IrcConnectionStatus status, string host, int port, string message);

    public signal void topic(string channel, string topic);
    public signal void topic_who(string channel, IrcUser who, int64 timestamp);

    /**
     * Emitted when a known extension is enabled
     */
    public signal void extension_enabled(string extension);

    public signal void user_online(IrcUser user);
    public signal void user_offline(IrcUser user);

    /* All this is to ensure we perform valid non-blocking queued output. Phew. */
    private Queue<string> out_q;
    private uint out_s;
    private _olock outm;
    private IOChannel ioc;
    private DataOutputStream dos;

    bool registered = false;
    InetSocketAddress sock_addr;
    bool tls_pending = false;

    private string[] capabilities;
    private string[] cap_requests;
    private string[] cap_denied;
    private string[] cap_granted;
    private bool to_tls = false;

    /* Does the grunt work of ensuring input is valid */
    private IrcParser parser;

    const unichar CTCP_PREFIX = '\x01';

    /** Allows tracking of connected state.. */
    public bool connected { public get; private set; }

    /**
     * Emitted when we start recieving the MOTD
     */
    public signal void motd_start(string msg);

    /**
     * Emitted for each line of the MOTD
     */
    public signal void motd_line(string line);

    /**
     * Emitted when we get RPL_ENDOFMOTD, with the complete MOTD
     */
    public signal void motd(string motd, string end);

    /* Emitted when we get the names list (complete) */
    public signal void names_list(string channel, IrcUser[] users);
    public signal void disconnected();

    /**
     * Someone (possibly you) was kicked from an IRC channel
     *
     * @param user The user who issued the kick
     * @param channel The channel they were booted from
     * @param whom The unlucky soul who was booted
     * @param reason The reason they were booted
     */
    public signal void user_kicked(IrcUser user, string channel, string whom, string reason);

    /**
     * Recieved a CTCP request
     * @param user The originator of the request
     * @param command The command name
     * @param text Any remaining text (not always present)
     * @param privmsg Whether this was a privmsg (i.e. not NOTICE)
     */
    public signal void ctcp(IrcUser user, string command, string text, bool privmsg);

    /**
     * Issued upon a nick error
     *
     * @param nick The nick that caused the issue
     * @param error Reason for the nick error
     * @param human Human readable reason for the error
     */
    public signal void nick_error(string nick, IrcNickError error, string human);

    /**
     * Emitted when a nickname is changed
     *
     * @param user The user who nick-changed
     * @param nick The new nick they are known by
     * @param us Whether we changed nick
     */
    public signal void nick_changed(IrcUser user, string nick, bool us);

    /**
     * Indicates we've established our connection to the IRC network, and have
     * recieved our welcome response
     */
    public signal void established();

    public signal void logging_in();
    public signal void login_success(string account_name, string message);
    public signal void login_failed(string message);

    /**
     * May be emitted multiple times as we recieve more RPL_ISUPPORT data from
     * the server.
     *
     * @param info Currently built serverinfo object
     */
    public signal void server_info(ServerInfo info);

    public IrcCore(IrcIdentity ident)
    {
        /* Todo: Validate */
        this.ident = ident;
        this.ident.account_id = this.ident.nick;
        cancel = new Cancellable();

        channels = new HashTable<string,Channel>(str_hash, str_equal);
        channel_cache = new HashTable<string,Channel>(str_hash, str_equal);

        parser = new IrcParser();

        out_q = new Queue<string>();
        out_s = 0;
        outm = {};
        outm.x = 0;
        this.id = IrcCore.sid;
        IrcCore.sid++;

        established.connect(()=> {
            connected = true;
            if (ident.auth == AuthenticationMode.NICKSERV) {
                logging_in();
                send_message("NickServ", "IDENTIFY %s %s".printf(this.ident.account_id, this.ident.password));
            }
            this.ident.password = null;
        });

        sinfo = ServerInfo();
    }

    private bool parse_ctcp(string msg, out string cmd, out string content)
    {
        cmd = "";
        content = "";

        if (!(msg.get_char(0) == '\x01' && msg.get_char(msg.length-1) == '\x01')) {
            return false;
        }
        if (msg.length < 4) {
            return false;
        }
        int index = msg.index_of_char(' ', 1);
        if (index < 0) {
            index = msg.length-1;
        }
        if (index < 1) {
            return false;
        }
        cmd = msg.substring(1,index-1);
        if (index+1 < msg.length) {
            content = msg.substring(index+1, (msg.length-2)-index);
        }
        return true;
    }

    public new async void connect(string host, uint16 port, bool use_ssl, bool starttls)
    {
        try {
            var r = Resolver.get_default();
            connecting(IrcConnectionStatus.RESOLVING, host, (int)port, @"Looking up $(host)...");

            var addresses = yield r.lookup_by_name_async(host, cancel);
            var addr = addresses.nth_data(0);

            sock_addr = new InetSocketAddress(addr, port);
            var client = new SocketClient();

            /* Attempt ssl :o */
            if (use_ssl) {
                client.set_tls(true);
                client.event.connect(on_client_event);
            }

            /* Reverse the lookup so people know *where* they're connecting (round robins) */
            string resolv = addr.to_string();
            try {
                resolv = yield r.lookup_by_address_async(addr, cancel);
            } catch (Error e) {
                warning("Failed to perform reverse lookup of %s", resolv);
            }

            connecting(IrcConnectionStatus.CONNECTING, resolv, (int)port, @"Connecting to $(host)... ($(resolv):$(port))");
            var connection = yield client.connect_async(sock_addr, cancel);
            (connection as TcpConnection).set_graceful_disconnect(true);
            if (connection != null) {
                this.conn = connection;
                this.client = client;
            }
            connection.socket.set_blocking(false);

            setup_io();
            /* Attempt identification immediately, get the ball rolling */
            connecting(IrcConnectionStatus.REGISTERING, addr.to_string(), (int)port, "Logging in...");

            /* Send TLS immediately..
             * If a server doesn't support this we'll end up with a registration
             * timeout. Better to use CAP in future :)
             */
            if (starttls && !use_ssl) {
                write_socket("STARTTLS\r\n");
                tls_pending = true;
            }

            if (!use_ssl && !starttls) {
                schedule_register();
            }
            yield _irc_loop();
        } catch (Error e) {
            message(e.message);
            if (!cancel.is_cancelled()) {
                cancel.cancel();
            }
            disconnect();
        }
    }

    void schedule_register()
    {
        Timeout.add(READ_TIMEOUT, ()=> {
            if (!got_line && !registered) {
                register();
            }
            return false;
        });
    }

    /**
     * Main IRC loop
     */
    async void _irc_loop()
    {
        try {
            InputStream? stream = tls != null ? tls.get_input_stream() : conn.input_stream;
            var dis = new DataInputStream(stream);
            /* Now we loop. */
            string line = null;

            while ((line = yield dis.read_line_async(Priority.DEFAULT, cancel)) != null) {
                yield handle_line(line);
                got_line = true;
                if (!registered) {
                    register();
                }
            }
        } catch (Error e) {
            message(e.message);
            if (!cancel.is_cancelled()) {
                cancel.cancel();
            }
            disconnect();
        }
    }

    void setup_io()
    {
        OutputStream? output = tls != null  ? tls.get_output_stream() : conn.output_stream;

        dos = new DataOutputStream(output);
        dos.set_close_base_stream(false);
#if WINDOWSBUILD
        ioc = new IOChannel.win32_socket(conn.socket.fd);
#else
        ioc = new IOChannel.unix_new(conn.socket.fd);
#endif
    }

    void register()
    {
        /* Prevent early registration with TLS enabled */
        if (tls_pending) {
#if WINDOWSBUILD
            message("TLS_PENDING");
#endif
            return;
        }
        write_socket("CAP LS\r\n");
        write_socket("USER %s %d * :%s\r\n", ident.username, ident.mode, ident.gecos);
        write_socket("NICK %s\r\n", ident.nick);
        registered = true;
#if WINDOWSBUILD
        message("REGISTERED");
#endif
    }

    TlsClientConnection? tls;

    async void setup_tls() {
        try {
            tls = TlsClientConnection.new(this.conn, this.sock_addr);
        } catch (Error e) {
            message("TLS failure %s", e.message);
            tls_pending = false;
            disconnect();
            return;
        }
        tls.set_use_ssl3(false);
        tls.accept_certificate.connect(this.accept_certificate);
        /* Stop everyone from reading. */
        cancel.cancel();
        bool success = false;
        try {
            success = yield tls.handshake_async(Priority.DEFAULT, null);
        } catch (Error e) {
            warning("TLS handshake failure: %s", e.message);
        }
        if (!success) {
            tls_pending = false;
            disconnect();
            return;
        }
        cancel.reset();
        setup_io();
        tls_pending = false;

        schedule_register();
        yield _irc_loop();
    }

    /**
     * Accepts all certificates right now, v. bad!
     */
    bool accept_certificate(TlsCertificate cert, TlsCertificateFlags flags)
    {
        return true;
    }

    public new void disconnect()
    {
        if (!tls_pending) {
            return;
        }
        try {
            if(!cancel.is_cancelled()) {
                cancel.cancel();
            }
            if (this.conn != null) {
                this.conn.close();
                this.conn = null;
            }
            this.connected = false;
        } catch (Error e) {
            warning("Error while closing IRC: %s", e.message);
        }
        disconnected();
    }

    private void on_client_event(SocketClientEvent e, SocketConnectable? s, IOStream? con)
    {
        if (e == SocketClientEvent.TLS_HANDSHAKING) {
            message("Handshaking..");
            var t = con as TlsClientConnection;
            t.set_use_ssl3(false);
            t.accept_certificate.connect(accept_certificate);
        } else if (e == SocketClientEvent.TLS_HANDSHAKED) {
            message("Handshake complete");
            schedule_register();
        }
    }

    protected bool dispatcher(IOChannel source, IOCondition cond)
    {
#if WINDOWSBUILD
        message("ENTER_dispatcher");
#endif
        if (cond == IOCondition.HUP) {
            lock (outm) {
                out_s = 0;
            }
            disconnect();
            return false;
        }
        /* Kill this dispatch.. */
        if (out_q.get_length() < 1) {
            lock (outm) {
                out_s = 0;
            }
            return false;
        }
        while (true)
        {
            unowned string? next;
            if (out_q.get_length() < 1) {
                break;
            }
            lock (outm) {
                next = out_q.peek_head();
            }
            bool remove = false;
            try {
                remove = dos.put_string(next);
#if WINDOWSBUILD
                message("FLUSHED(%s): %s", next, remove ? "YES" : "NO");
#endif
                dos.flush();
            } catch (Error e) {
                warning("Encountered I/O Error!");
                break;
            }
            if (remove) {
                lock (outm) {
                    out_q.remove(next);
                }
            }
        }
        /* killing ourselves again */
        lock (outm) {
            out_s = 0;
        }
        return false;
    }

    protected void write_socket(string fmt, ...)
    {
        va_list va = va_list();
        string line = fmt.vprintf(va);

        lock (outm) {
#if WINDOWSBUILD
            message("PUSHING: %s", line);
            try {
                dos.put_string(line);
            } catch (Error e) {
                warning("Encountered I/O Error!");
            }
#else
            out_q.push_tail(line);
            /* No current dispatch callback, set it up */
            if (out_s == 0) {
                out_s = ioc.add_watch(IOCondition.OUT | IOCondition.HUP, dispatcher);
            }
#endif
        }
    }

    /**
     * Pre-process line from server and dispatch for numeric or command handlers
     *
     * @param input The input line from the server
     */
    async void handle_line(string input)
    {
        IrcParserContext context;

        var line = input;
        /* You'd surely hope so. */
        if (line.has_suffix("\r\n")) {
            line = line.substring(0, line.length-2);
        }
        /* Does sometimes happen on broken inspircd.. (RPL_NAMREPLY gives double \r) */
        if (line.has_suffix("\r")) {
            line = line.substring(0, line.length-1);
        }

        if (!parser.parse(line, out context)) {
            warning("Dropping invalid line: %s", input);
            return;
        }

        stdout.printf("%s\n", line);
        stdout.printf("C: %s, N: %d, P: %s\n", context.command, context.numeric, context.prefix);

        /* bit hacky, but lets port numerics first */
        if (context.numeric > 0) {
            yield handle_numeric(context);
        } else {
            yield handle_command(context);
        }
    }

    /**
     * Handle a numeric response from the server
     *
     * @param sender Originator of message
     * @param numeric The numeric from the server
     * @param line The unprocessed line
     * @param remnant Remainder of processed line
     */
    async void handle_numeric(IrcParserContext context)
    {

        /* NOTE: Doesn't need to be async *yet* but will in future.. */
        /* TODO: Support all RFC numerics */
        switch (context.numeric) {
            case IRC.RPL_WELCOME:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS, 1, 1, -1)) {
                        break;
                }
                /* If we changed nick during registration, we resync here. */
                ident.nick = context.params[0];
                established();
                break;
            case IRC.TLS_BEGIN:
                yield setup_tls();
                break;
            case IRC.TLS_FAIL:
                warning(TLS_BANNER);
                break;

            /* SASL magicks. */
            case IRC.RPL_LOGGEDIN:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS |
                    IrcParserFlags.REQUIRES_VALUE, 3, 3, -1)) {
                    break;
                }
                message("SASL auth success");
                write_socket("CAP END\r\n");
                if (to_tls) {
                    write_socket("STARTTLS\r\n");
                    to_tls = false;
                }
                login_success(context.params[2], context.text);
                break;
            case IRC.ERR_NICKLOCKED:
            case IRC.ERR_SASLFAIL:
            case IRC.ERR_SASLTOOLONG:
            case IRC.ERR_SASLABORTED:
            case IRC.ERR_SASLALREADY:
                /* SASL failed, basically. */
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE, -1, -1, -1)) {
                    break;
                }
                warning("SASL authentication failed with numeric: %d", context.numeric);
                write_socket("CAP END\r\n");
                if (to_tls) {
                    write_socket("STARTTLS\r\n");
                    to_tls = false;
                }
                login_failed(context.text);
                break;
            /* Server info parsing, goodie! */
            case IRC.RPL_ISUPPORT:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS, 1, -1, -1)) {
                    break;
                }
                if (context.params.length == 1) {
                    /* Not yet handled. */
                    debug("Got RPL_BOUNCE, not RPL_ISUPPORT");
                    break;
                }
                string[] seps = { "=", ":" };
                for (int i = 1; i < context.params.length; i++) {
                    string key = null;
                    string val = null;
                    foreach (var sep in seps) {
                        if (sep in context.params[i]) {
                            var splits = context.params[i].split(sep);
                            key = splits[0];
                            if (splits.length > 1) {
                                val = string.joinv(sep, splits[1:splits.length]);
                            } else {
                                /* made a booboo */
                                key = context.params[i];
                            }
                            break;
                        }
                    }
                    if (key == null) {
                        key = context.params[i];
                    }
                    /* all require vals */
                    if (val == null) {
                        continue;
                    }
                    switch (key) {
                        case "NETWORK":
                            sinfo.network = val;
                            break;
                        case "AWAYLEN":
                            sinfo.away_length = int.parse(val);
                            break;
                        case "KICKLEN":
                            sinfo.kick_length = int.parse(val);
                            break;
                        case "NICKLEN":
                            sinfo.nick_length = int.parse(val);
                            break;
                        case "TOPICLEN":
                            sinfo.topic_length = int.parse(val);
                            break;
                        case "MONITOR":
                            sinfo.monitor = true;
                            sinfo.monitor_max = int.parse(val);
                            extension_enabled(key);
                            break;
                        default:
                            break;
                    }
                }
                server_info(this.sinfo);
                break;
            case IRC.RPL_MONONLINE:
            case IRC.RPL_MONOFFLINE:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE, -1, -1, -1)) {
                    break;
                }
                foreach (var u in context.text.strip().split(",")) {
                    var user = user_from_hostmask(u);
                    if (context.numeric == IRC.RPL_MONONLINE) {
                        user_online(user);
                    } else {
                        user_offline(user);
                    }
                }
                break;
            /* Names handling.. */
            case IRC.RPL_NAMREPLY:
                unowned Channel? cc;

                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE | IrcParserFlags.REQUIRES_PARAMS, 3, 3, -1)) {
                    warning("Invalid NAMREPLY parameter length!");
                    break;
                }

                if (!channel_cache.contains(context.params[2])) {
                    channel_cache[context.params[2]] = new Channel(context.params[2], context.params[1]);
                }
                cc = channel_cache[context.params[2]];
                /* New names reply, reset cached version.. */
                if (cc.final) {
                    cc.reset_users();
                }
                foreach (var user in context.text.strip().split(" ")) {
                   cc.add_user(user);
                }
                break;
            case IRC.RPL_ENDOFNAMES:
                unowned Channel? cc;
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS | IrcParserFlags.REQUIRES_PARAMS, 2, 2, -1)) {
                    break;
                }
                if (!channel_cache.contains(context.params[1])) {
                    warning("Got RPL_ENDOFNAMES without cached list!");
                    break;
                }
                cc = channel_cache[context.params[1]];
                names_list(context.params[1], cc.get_users());
                channel_cache.remove(context.params[1]);
                break;

            /* Motd handling */
            case IRC.RPL_MOTDSTART:
                _motd = ""; /* Reset motd */
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 1, 1, -1)) {
                    break;
                }
                motd_start(context.text);
                break;
            case IRC.RPL_MOTD:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 1, 1, -1)) {
                    break;
                }

                motd_line(context.text);
                _motd += "\n" + context.text;
                break;
            case IRC.RPL_ENDOFMOTD:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 1, 1, -1)) {
                    break;
                }
                if (!_motd.has_suffix("\n")) {
                    _motd += "\n";
                }
                motd(_motd, context.text);
                break;

            /* Nick error handling */
            case IRC.ERR_NICKNAMEINUSE:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 2, 2, -1)) {
                    break;
                }
                nick_error(context.params[1] , IrcNickError.IN_USE, context.text);
                break;
            case IRC.ERR_NONICKNAMEGIVEN:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 2, 2, -1)) {
                    break;
                }
                nick_error(context.params[1], IrcNickError.NO_NICK, context.text);
                break;
            case IRC.ERR_ERRONEUSNICKNAME:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 2, 2, -1)) {
                    break;
                }
                nick_error(context.params[1], IrcNickError.INVALID, context.text);
                break;
            case IRC.ERR_NICKCOLLISION:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 2, 2, -1)) {
                    break;
                }
                nick_error(context.params[1], IrcNickError.COLLISION, context.text);
                break;
            case IRC.RPL_TOPIC:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE |
                    IrcParserFlags.REQUIRES_PARAMS, 2, 2, -1)) {
                    break;
                }
                topic(context.params[1], context.text);
                break;
            case IRC.RPL_TOPICWHOTIME:
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS, 4, 4, -1)) {
                    break;
                }
                IrcUser who;
                who = user_from_hostmask(context.params[2]);
                int64 stamp = int64.parse(context.params[3]);
                topic_who(context.params[1], who, stamp);
                break;
            default:
                break;
        }
    }

    /*
     * Very simple, construct PLAIN mechanism string for SASL auth
     */
    string sasl_plain(string authid, string authcd, string passwd)
    {
        uchar[] data = authid.data;
        data += '\0';
        for (int i=0; i < authcd.length; i++) {
            data += authcd.data[i];
        }
        data += '\0';
        for (int i=0; i < passwd.length; i++) {
            data += passwd.data[i];
        }
        return Base64.encode(data);
    }

    async void sasl_auth()
    {
        var sasl = sasl_plain(ident.account_id, ident.account_id, ident.password);
        write_socket("AUTHENTICATE %s\r\n", sasl);
        ident.password = null;
    }

    /**
     * Handle a command from the server (string)
     *
     * @param context Initialised IrcParserContext
     */
    async void handle_command(IrcParserContext context)
    {
        if (context.special) {
            switch (context.command) {
                case "PING":
                    if (!parser.valid(context, IrcParserFlags.REQUIRES_VALUE, -1, -1, -1)) {
                        break;
                    }
                    write_socket("PONG :%s\r\n", context.text);
                    return;
                case "AUTHENTICATE":
                    if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS, 1, 1, -1)) {
                        message("TELL ME LIES TELL ME SWEET LITTLE LIES");
                        break;
                    }
                    message("LOGGING IN :D");
                    logging_in();
                    yield sasl_auth();
                    break;
                default:
                    /* Error, etc, not yet supported */
                    return;
            }
        }

        IrcUser? user = user_from_hostmask(context.prefix);

        switch (context.command) {
            /* caps handling */
            case "CAP":
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS |
                    IrcParserFlags.REQUIRES_VALUE, 2, 2, -1)) {
                    break;
                }

                /* currently we don't support dynamic (post-reg) changes */
                if (context.params[1] == "LS") {
                    /* CAP LS response */
                    var msg = context.text.strip();
                    capabilities = msg.split(" ");
                    /** Note, we don't actually request any CAPS yet. */

                    if (ident.auth == AuthenticationMode.SASL && "sasl" in capabilities) {
                        stdout.printf("debug: requesting sasl\n");
                        cap_requests += "sasl";
                    }

                    if (cap_requests.length > 0) {
                        write_socket("CAP REQ :%s\r\n", string.joinv(" ", cap_requests));
                    }
                } else if (context.params[1] == "ACK") {
                    /* Got a requested capability */
                    foreach (var ack in context.text.split(" ")) {
                        if (ack.strip() == "") {
                            continue;
                        }
                        cap_granted += ack;
                    }
                } else if (context.params[1] == "NAK") {
                    /* Denid a requested capability */
                    foreach (var nack in context.text.split(" ")) {
                        if (nack.strip() == "") {
                            continue;
                        }
                        cap_denied += nack;
                    }
                }

                /* If we req'd and ack'd tls, schedule starttls. */
                if ("tls" in cap_granted && "tls" in cap_requests) {
                    to_tls = true;
                }

                if (cap_requests.length == cap_denied.length + cap_granted.length) {
                    /* Permit completion of SASL auth */
                    if (!("sasl" in cap_granted)) {
                        write_socket("CAP END\r\n");
                        if (to_tls) {
                            write_socket("STARTTLS\r\n");
                            to_tls = false;
                        }
                    }
                }

                /* Deal with SASL auth. */
                if ("sasl" in cap_granted) {
                    /* For now we only support PLAIN */
                    write_socket("AUTHENTICATE PLAIN\r\n");
                }
                break;
            case "PRIVMSG":
            case "NOTICE":
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS |
                    IrcParserFlags.REQUIRES_VALUE, 1, 1, -1)) {
                    break;
                }
                string ctcp_command;
                string ctcp_string;
                string message = context.text;
                IrcMessageType type;

                if (context.params[0] == ident.nick) {
                    type = IrcMessageType.PRIVATE;
                } else {
                    type = IrcMessageType.CHANNEL;
                }
                if (parse_ctcp(context.text, out ctcp_command, out ctcp_string)) {
                    if (ctcp_command == "ACTION") {
                        type |= IrcMessageType.ACTION;
                        message = ctcp_string;
                    } else {
                        /* Send off to ctcp handlers instead. */
                        ctcp(user, ctcp_command, ctcp_string, context.command == "PRIVMSG");
                        break;
                    }
                }
                if (context.command == "PRIVMSG") {
                    messaged(user, context.params[0], message, type);
                } else {
                    noticed(user, context.params[0], message, type);
                }
                break;
            case "JOIN":
                /* More fucking standards. Some send JOIN :#channel. Some send JOIN #channel. */
                if (!parser.valid(context, IrcParserFlags.NONE, 0, 1, -1)) {
                    break;
                }
                if (context.text == null && context.params == null) {
                    /* ircfuzzed. */
                    break;
                }
                joined_channel(user, context.text != null ? context.text : context.params[0]);
                break;
            case "PART":
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS, 1, 2, -1)) {
                    break;
                }
                parted_channel(user, context.params != null ? context.params[0] : context.text, context.text);
                break;
            case "KICK":
                if (!parser.valid(context, IrcParserFlags.REQUIRES_PARAMS |
                    IrcParserFlags.REQUIRES_VALUE, 2, 2, -1)) {
                    break;
                }

                user_kicked(user, context.params[0], context.params[1], context.text);
                break;
            case "NICK":
                if (!parser.valid(context, IrcParserFlags.NONE, 0, 1, -1)) {
                    break;
                }
                if (context.text == null && context.params == null) {
                    /* ircfuzzed. */
                    break;
                }
                var new_nick = context.text != null ? context.text : context.params[0];
                if (user.nick == ident.nick) {
                    ident.nick = new_nick;
                    nick_changed(user, new_nick, true);
                } else {
                    nick_changed(user, new_nick, false);
                }
                break;
            case "QUIT":
                if (!parser.valid(context, IrcParserFlags.VALUE_ONLY, -1, -1, -1)) {
                    break;
                }
                user_quit(user, context.text);
                break;
            default:
                break;
        }
        /* TODO: Support all RFC commands */
    }

    /**
     * Simplest route to parse IRC command remnants that use ":" notation
     *
     * @param sender The sender of the message (hostmask)
     * @param remnant incoming remnant
     * @param user Where to store the IrcUser info
     * @param params Where to store any parameters (if wanted.)
     * @param rhs Where to store right-hand-side portion of ":" message
     * @param last_colon Whether to use the last_colon as the separator, needed for some numerics
     */
    protected void parse_simple(string sender, string remnant, out IrcUser user, out string[]? params, out string rhs, bool last_colon = false)
    {
        user = user_from_hostmask(sender);

        int i;
        if (last_colon) {
            i = remnant.last_index_of(" :");
        } else {
            i = remnant.index_of(" :");
        }

        if (i < 0 || i+1 == remnant.length ) {
            params = null;
            rhs = remnant;
            if (rhs.has_prefix(":")) {
                rhs = remnant.substring(1);
            }
            return;
        }
        i++;

        /* For now, space separated. May expand in future to suit API */
        string pms = remnant.substring(0, i);
        pms = pms.strip(); // because we end up with wrong lengths..
        params = pms.split(" ");

        /* implementation dependent */
        rhs = remnant.substring(i+1);
    }

    /**
     * Parse an IRC hostmask and structure it
     *
     * @param hostmask Input hostmask (nick!user@host)
     *
     * @returns An IrcUser if the hostmask is valid, or a dummy ircuser
     */
    protected IrcUser? user_from_hostmask(string hostmaskin)
    {
        IrcUser ret = IrcUser() {
            nick = null,
            username = "user",
            hostname = "host"
        };

        string hostmask = hostmaskin;
        if (hostmask.has_prefix(":")) {
            hostmask = hostmask.substring(1);
        }

        int bi, ba;
        if ((bi = hostmask.index_of("!")) < 0) {
            return ret;
        }
        if ((ba = hostmask.index_of("@")) < 0) {
            return ret;
        }
        if (bi > ba || bi+1 > hostmask.length || ba+1 > hostmask.length) {
            return ret;
        }

        ret.nick = hostmask.substring(0, bi);
        ret.username = hostmask.substring(bi+1, (ba-bi)-1);
        ret.hostname = hostmask.substring(ba+1);
        return ret;
    }

    /**
     * Attempt to join the given IRC channel
     * 
     * @note No password support yet
     * @param channel The channel to join
     */
    public void join_channel(string channel)
    {
        write_socket("JOIN %s\r\n", channel);
    }

    /**
     * Part the given channel with an optional reason.
     * 
     * @param channel The channel to leave
     * @param reason The reason for leaving
     */
    public void part_channel(string channel, string? reason)
    {
        write_socket("PART %s%s\r\n", channel, reason != null ? " :" + reason :  "");
    }

    /**
     * Send a message to the target
     *
     * @param target An online IRC nick, or a joined IRC channel
     * @param message The message to send
     */
    public void send_message(string target, string message)
    {
        write_socket("PRIVMSG %s :%s\r\n", target, message);
    }

    /**
     * Send a notice to the target
     *
     * @param target An online IRC nick, or a joined IRC channel
     * @param message The message to send
     */
    public void send_notice(string target, string message)
    {
        write_socket("NOTICE %s :%s\r\n", target, message);
    }

    /**
     * Send a CTCP ACTION
     *
     * @note This is the /me command in IRC clients, i.e. /me is a loser
     * @param taget An online nick, or a joined IRC channel
     * @param action The "action string" to send
     */
    public void send_action(string target, string action)
    {
        send_ctcp(target, "ACTION", action);
    }

    /**
     * Send a named CTCP command response
     *
     * @note PRIVMSG CTCP queries should be responded to with NOTICE, to avoid error loops!
     * @param target Who to send the response to
     * @param command The CTCP command (i.e. ACTION)
     * @param content Optional content to add to the message
     * @param notice Whether to use NOTICE or PRIVMSG
     */
    public void send_ctcp(string target, string command, string? content, bool notice = false)
    {
        string cmd = content != null ? @"$(command) $(content)" : "$(command)";
        string msgtype = notice ? "NOTICE" : "PRIVMSG";

        write_socket(@"%s %s :$(CTCP_PREFIX)%s$(CTCP_PREFIX)\r\n", msgtype, target, cmd);
    }

    public void add_monitor(string target)
    {
        if (!sinfo.monitor) {
            warning("Server does not support MONITOR extension");
            return;
        }
        write_socket("MONITOR + %s\r\n", target);
    }

    public void remove_monitor(string target)
    {
        if (!sinfo.monitor) {
            warning("Server does not support MONITOR extension");
        }
        write_socket("MONITOR - %s\r\n", target);
    }

    /**
     * Send a raw string to the server (i.e. no processing from library)
     *
     * @param line The line to send
     */
    public void send_quote(string line)
    {
        write_socket("%s\r\n", line);
    }

    private void _write_socket(string fmt, ...)
    {
        va_list va = va_list();
        string line = fmt.vprintf(va);
        try {
            if (dos != null) {
                dos.put_string(line, null);
                dos.flush(null);
            }
        } catch (Error e) {
            warning("Failed to skip out_q: %s", e.message);
        }
    }

    /**
     * Quit from the IRC network.
     *
     * @param quit_msg An optional quit message
     */
    public void quit(string? quit_msg)
    {
        if (quit_msg != null) {
            _write_socket("QUIT :%s\r\n", quit_msg);
        } else {
            _write_socket("QUIT\r\n");
        }
        disconnect();
    }

    public void send_names(string? channel)
    {
        if (channel != null) {
            write_socket("NAMES %s\r\n", channel);
        } else {
            write_socket("NAMES\r\n");
        }
    }

    /**
     * Attempt to change nickname
     *
     * @param nick The new nickname
     */
    public void set_nick(string nick)
    {
        write_socket("NICK %s\r\n", nick);
    }
}

/**
 * Used to represent an IRC channel
 */
public class Channel {

    /* Known user list for this channel */
    public HashTable<string,IrcUser?> users;
    public string name { public get; private set; }
    public string mode { public get; private set; }

    public bool final { public get; public set; }

    public Channel(string name, string mode)
    {
        this.name = name;
        this.mode = mode;
        users = new HashTable<string,IrcUser?>(str_hash,str_equal);
        final = false;
    }

    public IrcUser[] get_users()
    {
        IrcUser[] ret = {};
        users.foreach((k,v)=> {
            ret += v;
        });
        return ret;
    }

    /**
     * COMPLETELY TEMPORARY.
     * Going to pull prefixes from RPL_ISUPPORT...
     */
    public void add_user(string user)
    {
        if (!(user in users)) {
            IrcUser u  = IrcUser();
            u.nick = user;
            unichar c = u.nick.get_char(0);
            if (c == '@') {
                u.op = true;
                u.nick = u.nick.substring(1);
            } else if (c == '+') {
                u.voice = true;
                u.nick = u.nick.substring(1);
            }
            users[u.nick] = u;
        }
    }

    public bool has_user(string user)
    {
        return users.contains(user);
    }

    public void rename_user(string old, string newname)
    {
        if (old in users) {
            IrcUser oldu = users[old];
            oldu.nick = newname;
            users.remove(old);
            users[newname] = oldu;
        }
    }

    public void remove_user(string user)
    {
        if (user in users) {
            users.remove(user);
        }
    }

    public void reset_users()
    {
        users.remove_all();
        final = false;
    }
}
