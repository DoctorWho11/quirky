/*
 * DummyClient.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey@evolve-os.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */
public class DummyClient : Gtk.Window
{
    Gtk.HeaderBar header;
    Gtk.Entry input;
    Gtk.TextView main_view;
    Gtk.ScrolledWindow scroll;
    IrcIdentity ident;
    IrcCore core;

    public DummyClient()
    {
        header = new Gtk.HeaderBar();
        header.set_show_close_button(true);
        set_title("DummyClient");
        set_titlebar(header);
        header.set_title("DummyClient");

        set_icon_name("xchat");

        destroy.connect(Gtk.main_quit);

        var layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        add(layout);

        scroll = new Gtk.ScrolledWindow(null, null);
        scroll.border_width = 2;
        scroll.set_shadow_type(Gtk.ShadowType.IN);
        main_view = new Gtk.TextView();
        main_view.set_editable(false);
        scroll.add(main_view);
        layout.pack_start(scroll, true, true, 0);

        var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        bottom.border_width = 2;
        bottom.get_style_context().add_class("linked");
        layout.pack_end(bottom, false, false, 0);

        input = new Gtk.Entry();
        input.set_placeholder_text("Write a message");
        input.activate.connect(send_text);
        bottom.pack_start(input, true, true, 0);

        var send = new Gtk.Button.with_label("Send");
        send.clicked.connect(send_text);
        bottom.pack_end(send, false, false, 0);

        /* Totes evil. Make configurable */
        string channel = "#evolveos";
        ident = IrcIdentity() {
            nick = "ikeytestclient",
            username = "ikeytest",
            gecos = "Ikeys Test Client",
            mode = 0
        };

        core = new IrcCore(ident);
        core.connect.begin("localhost", 6667);
        core.messaged.connect(on_messaged);
        core.established.connect(()=> {
            core.join_channel.begin(channel);
        });

        set_size_request(600, 400);
        show_all();
    }

    protected void send_text()
    {
        if (input.text.length > 0) {
            string message = input.text;
            string target = "#evolveos";

            core.send_message.begin(target, message);

            string append = @"$(ident.nick) => $(target) : $(message)\n";
            var txt = main_view.buffer.text + append;
            main_view.buffer.set_text(txt);
            input.set_text("");
        }
    }
    protected void on_messaged(IrcUser user, string target, string message)
    {
        /* Right now we don't check PMs, etc. */
        string append = @"$(user.nick) => $(target) : $(message)\n";
        var txt = main_view.buffer.text + append;
        main_view.buffer.set_text(txt);
    }
}

public static void main(string[] args)
{
    Gtk.init(ref args);
    var c = new DummyClient();
    Gtk.main();

    c = null;
}
