/*
 * DummyBot.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey@evolve-os.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */


public class DummyBot
{
    IrcIdentity ident;
    IrcCore irc;

    static string BOT_PREFIX = "~";
    private MainLoop loop;

    public DummyBot(MainLoop loop)
    {
        string default_channel = "#evolveos";

        ident = IrcIdentity() {
            nick = "ikeytestbot",
            username = "TestBot",
            gecos = "Test Bot",
            mode = 0
        };
        irc = new IrcCore(ident);

        irc.disconnected.connect(()=> {
            stdout.printf("Disconnected\n");
            loop.quit();
            Process.exit(1);
        });

        /* Autojoin */
        irc.established.connect(()=> {
            irc.join_channel(default_channel);
            irc.send_names("#evolveos");
        });

        irc.messaged.connect(on_messaged);

        /* Lambdas .. ftw ? */
        irc.user_quit.connect((u,q)=>{
                stdout.printf("=> %s has quit IRC (%s)\n", u.nick, q);
        });

        irc.joined_channel.connect((u,c)=>{
            if (u.nick == ident.nick) {
                /* For now just spam folks. */
                irc.send_message(c, "Let\'s not stand on ceremony here, Mr. Wayne..");
            } else {
                irc.send_message(c, @"Welcome, $(u.nick)!");
            }
        });

        irc.parted_channel.connect((u,c,r)=> {
            /* i.e. we didn't leave.. */
            if (u.nick != ident.nick) {
                if (r == null) {
                    irc.send_message(c, @"Sorry to see $(u.nick) go for no reason..");
                } else {
                    irc.send_message(c, @"Sorry to see $(u.nick) go .. ($(r))");
                }
            }
        });

        irc.names_list.connect((c,l)=> {
            message("%s has %u users", c, l.length());
            foreach (var u in l) {
                message("User on %s: %s", c, u);
            }
        });
        this.loop = loop;
    }

    public void on_messaged(IrcUser user, string target, string message)
    {
        // DEMO: Send message back (PM or channel depending on target)
        if (target == ident.nick) {
            irc.send_message(user.nick, @"Hello, and thanks for the PM $(user.nick)");
        } else {
            /* Only if we got mentioned.. */
            if (ident.nick in message) {
                irc.send_message(target, @"Wha? Who dere? Whatcha want $(user.nick)??");
            } else if (message.has_prefix(BOT_PREFIX)) {
                if (message.length <= 1) {
                    irc.send_message(target, "Eh, need a proper command broski..");
                    return;
                }
                string command = message.split(" ")[0].substring(1);

                switch (command) {
                    case "quit":
                        irc.quit("OK OK, I\'m going");
                        break;
                    case "ping":
                        irc.send_message(target, @"$(user.nick): PONG!");
                        break;
                    case "forums":
                        irc.send_message(target, "Evolve OS Forums: https://evolve-os.com/forums/");
                        break;
                    case "wiki":
                        irc.send_message(target, "Evolve OS Wiki: https://evolve-os.com/wiki");
                        break;
                    default:
                        irc.send_message(target, @"LOL $(user.nick) thought we was a real bot.");
                        break;
                }
            }
        }
    }

    
    public void run_bot()
    {
        irc.connect.begin("localhost", 6667, false, ()=> {
            stdout.printf("Loop quit\n");
            loop.quit();
        });
    }
}

public static void main(string[] args)
{
    MainLoop loop = new MainLoop();
    DummyBot b = new DummyBot(loop);
    b.run_bot();
    loop.run();
}
