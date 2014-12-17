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
    string default_channel;
    int mode;
}

public struct IrcUser {
    string nick;
    string username;
    string hostname;
}

public class IrcCore
{
    SocketClient? client;
    SocketConnection? conn;
    DataInputStream? dis;
    DataOutputStream? dos;
    IrcIdentity ident;

    public signal void joined_channel(IrcUser user, string channel);
    public signal void user_quit(IrcUser user, string quit_msg);
    public signal void messaged(IrcUser user, string target, string message);
    public signal void parted_channel(IrcUser user, string channel, string? reason);

    public IrcCore(IrcIdentity ident)
    {
        /* Todo: Validate */
        this.ident = ident;
    }

    public void connect(string host, uint16 port)
    {
        try {
            var r = Resolver.get_default();
            var addresses = r.lookup_by_name(host, null);
            var addr = addresses.nth_data(0);

            var sock_addr = new InetSocketAddress(addr, port);
            var client = new SocketClient();

            var connection = client.connect(sock_addr, null);
            if (connection != null) {
                this.conn = connection;
                this.client = client;
            }
        } catch (Error e) {
            message(e.message);
        }
    }

    protected bool write_socket(string fmt, ...)
    {
        va_list va = va_list();
        string res = fmt.vprintf(va);

        try {
            dos.put_string(res);
        } catch (Error er) {
            message("I/O error: %s", er.message);
            return false;
        }
        return true;
    }

    public void irc_loop()
    {
        if (client == null || conn == null) {
            message("No connection!");
            return;
        }
        stdout.printf("Beginning irc_loop\n");

        dis = new DataInputStream(conn.input_stream);
        dos = new DataOutputStream(conn.output_stream);

        // Registration. Le hackeh.
        write_socket("USER %s %d * :%s\r\n", ident.username, ident.mode, ident.gecos);
        write_socket("NICK %s\r\n", ident.nick);

        string? line = null;
        size_t length; // future validation
        try {
            while ((line = dis.read_line(out length)) != null) {
                handle_line(line);
            }
        } catch (Error e) {
            message("I/O error read: %s", e.message);
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
    void handle_line(string input)
    {
        var line = input;
        if (line.has_suffix("\r")) {
            line = line.substring(0, line.length-1);
        }
        string[] segments = line.split(" ");
        if (segments.length < 2) {
            warning("IRC server appears to be on crack.");
            return;
        }
        /* Sender is a special case, can sometimes be a command.. */
        string sender = segments[0];

        /* Speed up processing elsewhere.. */
        string? remnant = segments.length > 2  ? string.joinv(" ", segments[2:segments.length]) : null;

        if (!sender.has_prefix(":")) {
            /* Special command */
            handle_command(sender, sender, line, remnant, true);
        } else {
            string command = segments[1];
            if (is_number(command)) {
                var number = int.parse(command);
                handle_numeric(sender, number, line, remnant);
            } else {
                handle_command(sender, command, line, remnant);
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
    void handle_numeric(string sender, int numeric, string line, string? remnant)
    {
        /* TODO: Support all RFC numerics */
        switch (numeric) {
            case 001:
                join_channel(ident.default_channel);
                break;
            default:
                break;
        }
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
    void handle_command(string sender, string command, string line, string? remnant, bool special = false)
    {
        if (special) {
            switch (command) {
                case "PING":
                    var send = line.replace("PING", "PONG");
                    write_socket("%s\r\n", send);
                    return;
                default:
                    /* Error, etc, not yet supported */
                    return;
            }
        }

        switch (command) {
            case "PRIVMSG":
                IrcUser user;
                string message;
                string[] params;
                parse_simple(sender, remnant, out user, out params, out message);
                if (params.length != 1) {
                    warning("Invalid PRIVMSG: more than one target!");
                    break;
                }
                messaged(user, params[0], message);
                break;
            case "JOIN":
                IrcUser user;
                string channel;
                parse_simple(sender, remnant, out user, null, out channel);
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
     */
    protected void parse_simple(string sender, string remnant, out IrcUser user, out string[]? params, out string rhs)
    {
        user = user_from_hostmask(sender);

        var i = remnant.index_of(":");
        if (i < 0 || i == remnant.length) {
            params = null;
            rhs = remnant;
            return;
        }

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
     * Quit from the IRC network.
     *
     * @param quit_msg An optional quit message
     */
    public void quit(string? quit_msg)
    {
        if (quit_msg != null) {
            write_socket("QUIT :%s\r\n", quit_msg);
        } else {
            write_socket("QUIT\r\n");
        }
    }
}
