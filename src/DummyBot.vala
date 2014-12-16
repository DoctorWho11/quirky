/*
 * dummybot.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey@evolve-os.com>
 *
 * This example is provided for an initial proof-of-concept of blocking I/O
 * on IRC in Vala. It will survive here a little longer to ensure we never
 * actually end up with an end project looking anything like this.
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
    string hello_prompt;
    int mode;
}

public class DummyBot
{
    SocketClient? client;
    SocketConnection? conn;
    DataInputStream? dis;
    DataOutputStream? dos;

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

        /* Ported from my C version. Structs are lighter anyway */
        IrcIdentity ident = IrcIdentity() {
            nick = "ikeytestbot",
            username = "TestBot",
            gecos = "Test Bot",
            default_channel = "#evolveos",
            hello_prompt = "I r testbot!",
            mode = 0
        };

        // Registration. Le hackeh.
        write_socket("USER %s %d * :%s\r\n", ident.username, ident.mode, ident.gecos);
        write_socket("NICK %s\r\n", ident.nick);

        string? line = null;
        size_t length; // future validation
        try {
            while ((line = dis.read_line(out length)) != null) {
                stdout.printf("Line: %s\n", line);

                /* HOW NOT TO IRC. See? Its evil. Imagine, PRIVMSG with a 001 .. -_- */
                if ("001" in line) {
                    write_socket("JOIN %s\r\n", ident.default_channel);
                }
                if ("JOIN" in line) {
                    write_socket("PRIVMSG %s :%s\r\n", ident.default_channel, ident.hello_prompt);
                }
                if ("PING" in line && !("PRIVMSG" in line)) {
                    write_socket("PONG\r\n");
                }
                // still prefer printf formatting.
                if (@"PRIVMSG $(ident.default_channel)" in line && "GOHOME" in line) {
                    write_socket("QUIT :Buggering off\r\n");
                }
            }
        } catch (Error e) {
            message("I/O error read: %s", e.message);
        }
    }
}

public static void main(string[] args)
{
    DummyBot b = new DummyBot();
    b.connect("localhost", 6667);
    b.irc_loop();
}
