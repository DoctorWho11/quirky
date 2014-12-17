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

    public DummyBot()
    {
        ident = IrcIdentity() {
            nick = "ikeytestbot",
            username = "TestBot",
            gecos = "Test Bot",
            default_channel = "#evolveos",
            hello_prompt = "I r testbot!",
            mode = 0
        };
        irc = new IrcCore(ident);
        irc.messaged.connect(on_messaged);

        /* Lambdas .. ftw ? */
        irc.user_quit.connect((u,q)=>{
                stdout.printf("=> %s has quit IRC (%s)\n", u.nick, q);
        });

        irc.joined_channel.connect((u,c)=>{
            if (u.nick == ident.nick) {
                /* For now just spam folks. */
                irc.send_message(c, "I come in peace");
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
            
    }

    public void on_messaged(IrcUser user, string target, string message)
    {
        // DEMO: Send message back (PM or channel depending on target)
        string who = target == ident.nick ? user.nick : target;
        irc.send_message(who, @"Hello, $(user.nick)");
    }

    
    public void run_bot()
    {
        irc.connect("localhost", 6667);
        irc.irc_loop();
    }
}

public static void main(string[] args)
{
    DummyBot b = new DummyBot();
    b.run_bot();
}
