/*
 * IrcCore.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey@evolve-os.com>
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

public struct IrcIdentity {
    string username;
    string gecos;
    string nick;
    int mode;
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
        cancel = new Cancellable();

        channels = new HashTable<string,Channel>(str_hash, str_equal);
        channel_cache = new HashTable<string,Channel>(str_hash, str_equal);

        out_q = new Queue<string>();
        out_s = 0;
        outm = {};
        outm.x = 0;
        this.id = IrcCore.sid;
        IrcCore.sid++;

        established.connect(()=> {
            connected = true;
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

            var resolv = addr.to_string();
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
            yield _irc_loop();
        } catch (Error e) {
            message(e.message);
            if (!cancel.is_cancelled()) {
                cancel.cancel();
            }
            disconnect();
        }
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
            return;
        }
        write_socket("CAP LS\r\n");
        write_socket("USER %s %d * :%s\r\n", ident.username, ident.mode, ident.gecos);
        write_socket("NICK %s\r\n", ident.nick);
        registered = true;
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
        }
    }

    protected bool dispatcher(IOChannel source, IOCondition cond)
    {
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
            out_q.push_tail(line);

            /* No current dispatch callback, set it up */
            if (out_s == 0) {
                out_s = ioc.add_watch(IOCondition.OUT | IOCondition.HUP, dispatcher);
            }
        }
    }

    /**
     * Determine if we have a numeric string or not
     *
     * @param input String to check
     *
     * @returns a boolean, true if the input is numeric, otherwise false
     */
    bool is_number(string input)
    {
        bool numeric = false;
        for (int i=0; i<input.length; i++) {
            char c = (char)input.get_char(i);
            numeric = c.isdigit();
            if (!numeric) {
                return numeric;
            }
        }
        return numeric;
    }

    /**
     * Pre-process line from server and dispatch for numeric or command handlers
     *
     * @param input The input line from the server
     */
    async void handle_line(string input)
    {
        var line = input;
        /* You'd surely hope so. */
        if (line.has_suffix("\r\n")) {
            line = line.substring(0, line.length-2);
        }
        /* Does sometimes happen on broken inspircd.. (RPL_NAMREPLY gives double \r) */
        if (line.has_suffix("\r")) {
            line = line.substring(0, line.length-1);
        }
        string[] segments = line.split(" ");
        if (segments.length < 2) {
            warning("IRC server appears to be on crack. %s", line);
            return;
        }
        /* Sender is a special case, can sometimes be a command.. */
        string sender = segments[0];

        /* Speed up processing elsewhere.. */
        string? remnant = segments.length > 2  ? string.joinv(" ", segments[2:segments.length]) : null;

        if (!sender.has_prefix(":")) {
            /* Special command */
            yield handle_command(sender, sender, line, remnant, true);
        } else {
            string command = segments[1];
            if (is_number(command)) {
                var number = int.parse(command);
                yield handle_numeric(sender, number, line, remnant);
            } else {
                yield handle_command(sender, command, line, remnant);
            }
        }
        stdout.printf("%s\n", line);
    }

    /**
     * Handle a numeric response from the server
     *
     * @param sender Originator of message
     * @param numeric The numeric from the server
     * @param line The unprocessed line
     * @param remnant Remainder of processed line
     */
    async void handle_numeric(string sender, int numeric, string line, string? remnant)
    {
        /* NOTE: Doesn't need to be async *yet* but will in future.. */
        /* TODO: Support all RFC numerics */
        switch (numeric) {
            case IRC.RPL_WELCOME:
                string[] params;
                parse_simple(sender, remnant, null, out params, null);
                /* If we changed nick during registration, we resync here. */
                ident.nick = params[0];
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
                message("SASL auth success");
                write_socket("CAP END\r\n");
                if (to_tls) {
                    write_socket("STARTTLS\r\n");
                    to_tls = false;
                }
                break;
            case IRC.ERR_NICKLOCKED:
            case IRC.ERR_SASLFAIL:
            case IRC.ERR_SASLTOOLONG:
            case IRC.ERR_SASLABORTED:
            case IRC.ERR_SASLALREADY:
                /* SASL failed, basically. */
                warning("SASL authentication failed with numeric: %d", numeric);
                write_socket("CAP END\r\n");
                if (to_tls) {
                    write_socket("STARTTLS\r\n");
                    to_tls = false;
                }
                break;
            /* Server info parsing, goodie! */
            case IRC.RPL_ISUPPORT:
                string[] params;
                parse_simple(sender, remnant, null, out params, null, true);
                if (params.length == 1) {
                    /* Not yet handled. */
                    debug("Got RPL_BOUNCE, not RPL_ISUPPORT");
                    break;
                }
                string[] seps = { "=", ":" };
                for (int i = 1; i < params.length; i++) {
                    string key = null;
                    string val = null;
                    foreach (var sep in seps) {
                        if (sep in params[i]) {
                            var splits = params[i].split(sep);
                            key = splits[0];
                            if (splits.length > 1) {
                                val = string.joinv(sep, splits[1:splits.length]);
                            } else {
                                /* made a booboo */
                                key = params[i];
                            }
                            break;
                        }
                    }
                    if (key == null) {
                        key = params[i];
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
                string msg;
                parse_simple(sender, remnant, null, null, out msg);
                foreach (var u in msg.strip().split(",")) {
                    var user = user_from_hostmask(u);
                    if (numeric == IRC.RPL_MONONLINE) {
                        user_online(user);
                    } else {
                        user_offline(user);
                    }
                }
                break;
            /* Names handling.. */
            case IRC.RPL_NAMREPLY:
                string[] params; /* nick, mode, channel */
                string msg;
                unowned Channel? cc;

                parse_simple(sender, remnant, null, out params, out msg, true);
                if (params.length != 3) {
                    warning("Invalid NAMREPLY parameter length!");
                    break;
                }

                if (!channel_cache.contains(params[2])) {
                    channel_cache[params[2]] = new Channel(params[2], params[1]);
                }
                cc = channel_cache[params[2]];
                /* New names reply, reset cached version.. */
                if (cc.final) {
                    cc.reset_users();
                }
                foreach (var user in msg.strip().split(" ")) {
                   cc.add_user(user);
                }
                break;
            case IRC.RPL_ENDOFNAMES:
                string[] params;
                string msg; /* End of /NAMES, not really interesting. */
                unowned Channel? cc;
                parse_simple(sender, remnant, null, out params, out msg, true);
                if (!channel_cache.contains(params[1])) {
                    warning("Got RPL_ENDOFNAMES without cached list!");
                    break;
                }
                cc = channel_cache[params[1]];
                names_list(params[1], cc.get_users());
                channel_cache.remove(params[1]);
                break;

            /* Motd handling */
            case IRC.RPL_MOTDSTART:
                _motd = ""; /* Reset motd */
                string msg;
                parse_simple(sender, remnant, null, null, out msg);
                motd_start(msg);
                break;
            case IRC.RPL_MOTD:
                string msg;
                parse_simple(sender, remnant, null, null, out msg);
                motd_line(msg);
                _motd += "\n" + msg;
                break;
            case IRC.RPL_ENDOFMOTD:
                string msg;
                parse_simple(sender, remnant, null, null, out msg);
                if (!_motd.has_suffix("\n")) {
                    _motd += "\n";
                }
                motd(_motd, msg);
                break;

            /* Nick error handling */
            case IRC.ERR_NICKNAMEINUSE:
                string msg;
                string[] params;
                parse_simple(sender, remnant, null, out params, out msg);
                nick_error(params.length > 1 ? params[1] : ident.nick , IrcNickError.IN_USE, msg);
                break;
            case IRC.ERR_NONICKNAMEGIVEN:
                string msg;
                string[] params;
                parse_simple(sender, remnant, null, out params, out msg);
                nick_error(params.length > 1 ? params[1] : ident.nick, IrcNickError.NO_NICK, msg);
                break;
            case IRC.ERR_ERRONEUSNICKNAME:
                string msg;
                string[] params;
                parse_simple(sender, remnant, null, out params, out msg);
                nick_error(params.length > 1 ? params[1] : ident.nick, IrcNickError.INVALID, msg);
                break;
            case IRC.ERR_NICKCOLLISION:
                string msg;
                string[] params;
                parse_simple(sender, remnant, null, out params, out msg);
                nick_error(params.length > 1 ? params[1] : ident.nick, IrcNickError.COLLISION, msg);
                break;
            case IRC.RPL_TOPIC:
                string msg;
                string[] params;
                parse_simple(sender, remnant, null, out params, out msg);
                topic(params[1], msg);
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
        /*
        var send = sasl_plain("jimbob", "jimbob", "somepass"");
        write_socket("AUTHENTICATE %s\r\n", send); */
    }

    /**
     * Handle a command from the server (string)
     *
     * @param sender Originator of message
     * @param command The command name
     * @param line The unprocessed line
     * @param remnant Remainder of processed line
     * @param special Whether this is a special case, like PING or ERROR
     */
    async void handle_command(string sender, string command, string line, string? remnant, bool special = false)
    {
        if (special) {
            switch (command) {
                case "PING":
                    var send = line.replace("PING", "PONG");
                    write_socket("%s\r\n", send);
                    return;
                case "AUTHENTICATE":
                    yield sasl_auth();
                    break;
                default:
                    /* Error, etc, not yet supported */
                    return;
            }
        }

        switch (command) {
            /* caps handling */
            case "CAP":
                string msg;
                string[] params;
                parse_simple(sender, remnant, null, out params, out msg);

                /* currently we don't support dynamic (post-reg) changes */
                if (params[1] == "LS") {
                    /* CAP LS response */
                    msg = msg.strip();
                    capabilities = msg.split(" ");
                    /** Note, we don't actually request any CAPS yet. */

                    if (cap_requests.length > 0) {
                        write_socket("CAP REQ :%s\r\n", string.joinv(" ", cap_requests));
                    }
                } else if (params[1] == "ACK") {
                    /* Got a requested capability */
                    foreach (var ack in msg.split(" ")) {
                        if (ack.strip() == "") {
                            continue;
                        }
                        cap_granted += ack;
                    }
                } else if (params[1] == "NAK") {
                    /* Denid a requested capability */
                    foreach (var nack in msg.split(" ")) {
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
                IrcUser user;
                string message;
                string[] params;
                parse_simple(sender, remnant, out user, out params, out message);
                if (params.length != 1) {
                    warning(@"Invalid $(command): more than one target!");
                    break;
                }
                string ctcp_command;
                string ctcp_string;
                IrcMessageType type;
                if (params[0] == ident.nick) {
                    type = IrcMessageType.PRIVATE;
                } else {
                    type = IrcMessageType.CHANNEL;
                }
                if (parse_ctcp(message, out ctcp_command, out ctcp_string)) {
                    if (ctcp_command == "ACTION") {
                        type |= IrcMessageType.ACTION;
                        message = ctcp_string;
                    } else {
                        /* Send off to ctcp handlers instead. */
                        ctcp(user, ctcp_command, ctcp_string, command == "PRIVMSG");
                        break;
                    }
                }
                if (command == "PRIVMSG") {
                    messaged(user, params[0], message, type);
                } else {
                    noticed(user, params[0], message, type);
                }
                break;
            case "JOIN":
                IrcUser user;
                string channel;
                parse_simple(sender, remnant, out user, null, out channel, true);
                joined_channel(user, channel);
                break;
            case "PART":
                IrcUser user;
                string rhs;
                string[] params;
                string channel;
                string? reason = null;
                /* Long story short:
                 * PART #somechannel
                 * PART #somechannel :Reason
                 */
                parse_simple(sender, remnant, out user, out params, out rhs);
                if (params.length > 1) {
                    warning("Invalid PART: more than one target!");
                    break;
                }
                if (params.length == 1) {
                    channel = params[0];
                    reason = rhs;
                } else {
                    channel = rhs;
                }
                parted_channel(user, channel, reason);
                break;
            case "KICK":
                IrcUser user;
                string? reason = null;
                string[] params;
                parse_simple(sender, remnant, out user, out params, out reason);

                if (params.length != 2) {
                    warning("Invalid KICK: Wrong parameter count!");
                    break;
                }

                user_kicked(user, params[0], params[1], reason);
                break;
            case "NICK":
                IrcUser user = user_from_hostmask(sender);
                var new_nick = remnant.strip().replace(":", "");
                /* Le sigh for standards. Some send :, some don't */
                /* Update our own nick */
                if (user.nick == ident.nick) {
                    ident.nick = new_nick;
                    nick_changed(user, new_nick, true);
                } else {
                    nick_changed(user, new_nick, false);
                }
                break;
            case "QUIT":
                IrcUser user;
                string quit_msg;
                parse_simple(sender, remnant, out user, null, out quit_msg);
                user_quit(user, quit_msg);
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
            nick = "user",
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
