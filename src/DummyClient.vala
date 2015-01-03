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
public class DummyClient : Gtk.ApplicationWindow
{
    Gtk.HeaderBar header;
    Gtk.Entry input;
    IrcTextWidget? main_view;
    Gtk.ScrolledWindow scroll;
    IrcIdentity ident;
    IrcCore? core = null;
    IrcSidebar sidebar;
    string? target;

    HashTable<string,Gtk.TextBuffer> buffers;

    HashTable<IrcCore?,SidebarExpandable> roots;

    bool set_view = false;

    private void update_actions()
    {
        (application.lookup_action("join_channel") as SimpleAction).set_enabled(core != null && core.connected);
    }

    private void connect_server(string host, uint16 port, bool ssl)
    {
        var header = sidebar.add_expandable(host, "network-server-symbolic");
        header.activated.connect(()=> {
            IrcCore core = header.get_data("icore");
            this.core = core;
            update_actions();
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.set_buffer(buf);
            main_view.update_tabs(buf, ident.nick);
        });
        /* Need moar status in window.. */
        message("Connecting to %s:%d", host, port);

        var core = new IrcCore(ident);
        roots[core] = header;
        header.set_data("icore", core);
        core.connect.begin(host, port, false);
        core.messaged.connect(on_messaged);
        core.established.connect(()=> {
            core.join_channel("#evolveos");
            if (!set_view) {
                this.core = core;
            }
            update_actions();
        });
        core.joined_channel.connect((u,c)=> {
            update_actions();
            if (u.nick == ident.nick) {
                var root = roots[core];
                var item = root.add_item(c, "user-available-symbolic");
                item.set_data("icore", core);
                item.set_data("ichannel", c);
                item.activated.connect(()=> {
                    var buf = get_named_buffer(core, c);
                    this.core = item.get_data("icore");
                    this.target = item.get_data("ichannel");
                    main_view.set_buffer(buf);
                    main_view.update_tabs(buf, ident.nick);
                    update_actions();
                });
                var buf = get_named_buffer(core, c); /* do nothing :P */
                main_view.add_message(buf, "", @"You have joined $(c)", IrcTextType.JOIN);
            } else {
                var buf = get_named_buffer(core, c); /* do nothing :P */
                main_view.add_message(buf, u.nick, @"has joined $(c)", IrcTextType.JOIN);
            }
        });
        core.parted_channel.connect((u,c,r)=> {
            string msg = @"has left $(c)";
            if (r != null) {
                msg += @" ($(r))";
            }
            var buf = get_named_buffer(core, c);
            main_view.add_message(buf, u.nick == ident.nick ? "" : u.nick, msg, IrcTextType.PART);
        }); 
        core.motd.connect((m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, "", m, IrcTextType.MOTD);
        });
    }

    private unowned Gtk.TextBuffer get_named_buffer(IrcCore c, string name)
    {
        string compname = @"$(c.id)$(name)";
        Gtk.TextBuffer? buf;
        if (compname in buffers) {
            buf = buffers[compname];
        } else {
            buf = new Gtk.TextBuffer(main_view.tags);
            buffers[compname] = buf;
        }

        if (!set_view) {
            main_view.set_buffer(buf);
            main_view.update_tabs(buf, ident.nick);
            set_view = true;
        }

        return buffers[compname];
    }

    public DummyClient(Gtk.Application application)
    {
        Object(application: application);

        header = new Gtk.HeaderBar();
        header.set_show_close_button(true);
        set_title("DummyClient");
        set_titlebar(header);
        header.set_title("DummyClient");

        /* actions.. */
        var btn = new Gtk.MenuButton();
        var img = new Gtk.Image.from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON);
        btn.add(img);
        header.pack_start(btn);
        var menu = new Menu();
        menu.append("Connect to server", "app.connect");
        menu.append("Join channel", "app.join_channel");
        btn.set_menu_model(menu);
        btn.set_use_popover(true);

        /* connect to server.. */
        var action = new SimpleAction("join_channel", null);
        action.activate.connect(()=> {
            var dlg = new JoinChannelDialog(this);
            if (dlg.run() == Gtk.ResponseType.OK) {
                core.join_channel(dlg.response_text);
            }
            dlg.destroy();
        });
        application.add_action(action);

        update_actions();

        set_icon_name("xchat");

        var main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        add(main_layout);

        /* Sidebar.. */
        scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        sidebar = new IrcSidebar();
        scroll.add(sidebar);
        main_layout.pack_start(scroll, false, false, 0);

        buffers = new HashTable<string,Gtk.TextBuffer>(str_hash, str_equal);
        roots = new HashTable<IrcCore?,SidebarExpandable>(direct_hash, direct_equal);

        var layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        main_layout.pack_start(layout, true, true, 0);

        scroll = new Gtk.ScrolledWindow(null, null);
        scroll.border_width = 2;
        scroll.set_shadow_type(Gtk.ShadowType.IN);
        main_view = new IrcTextWidget();
        main_view.set_editable(false);
        scroll.add(main_view);
        layout.pack_start(scroll, true, true, 0);

        input = new Gtk.Entry();
        input.set_placeholder_text("Write a message");
        input.activate.connect(send_text);
        layout.pack_end(input, false, false, 0);

        /* Totes evil. Make configurable */
        ident = IrcIdentity() {
            nick = "ikeytestclient",
            username = "ikeytest",
            gecos = "Ikeys Test Client",
            mode = 0
        };

        /* Need to fix this! Make it an option, and soon! */
        connect_server("localhost", 6667, false);

        set_size_request(800, 550);
    }

    protected void send_text()
    {
        if (input.text.length < 1) {
            return;
        }
        bool action = false;
        string message = input.text;
        if (core == null) {
            warning("MISSING IRCCORE!");
            return;
        }

        /* TODO: Add command parser!! */
        if (message.down().has_prefix("/me")) {
            message = input.text.split("/me ")[1];
            action = true;
        }

        if (message.length == 0) {
            return;
        }

        if (action) {
            core.send_action(target, message);
        } else {
            core.send_message(target, message);
        }

        var buffer = get_named_buffer(core, target);
        main_view.add_message(buffer, ident.nick, message, action ? IrcTextType.ACTION : IrcTextType.MESSAGE);
        input.set_text("");
        main_view.update_tabs(buffer, ident.nick);
    }

    protected void on_messaged(IrcCore core, IrcUser user, string target, string message, IrcMessageType type)
    {
        /* Right now we don't check PMs, etc. */
        var buffer = get_named_buffer(core, target);
        if ((type & IrcMessageType.ACTION) != 0) {
            main_view.add_message(buffer, user.nick, message, IrcTextType.ACTION);
        } else {
            main_view.add_message(buffer, user.nick, message, IrcTextType.MESSAGE);
        }
    }
}

public class JoinChannelDialog : Gtk.Dialog
{

    public string response_text { public get; private set; }

    public JoinChannelDialog(Gtk.Window parent)
    {
        Object(transient_for: parent);
        response_text = "#";

        add_button("Cancel", Gtk.ResponseType.CANCEL);
        var w = add_button("Join", Gtk.ResponseType.OK);
        w.get_style_context().add_class("suggested-action");
        w.set_sensitive(false);

        var label = new Gtk.Label("Which channel do you want to join?");
        (get_content_area() as Gtk.Box).pack_start(label, false, false, 2);
        label.margin = 10;

        var entry = new Gtk.Entry();
        entry.set_text(response_text);
        entry.changed.connect(()=> {
            if (entry.text.strip() == "" || entry.text.length < 2) {
                w.set_sensitive(false);
                return;
            } else {
                w.set_sensitive(true);
            }
            response_text = entry.text;
        });
        entry.activate.connect(()=> {
            if (response_text.strip() == "" || response_text.length < 2) {
                return;
            }
            response(Gtk.ResponseType.OK);
        });

        (get_content_area() as Gtk.Box).pack_start(entry, false, false, 2);

        entry.margin = 10;
        get_content_area().show_all();
    }
}

/**
 * Enable GtkApplication/actions usage..
 */
public class DummyClientApp : Gtk.Application
{
    static DummyClient win = null;

    public DummyClientApp()
    {
        Object(application_id: "com.evolve_os.DummyIrcClient", flags: ApplicationFlags.FLAGS_NONE);
    }

    public override void activate()
    {
        if (win == null) {
            win = new DummyClient(this);
        }
        win.show_all();
        win.present();
    }
}

public static int main(string[] args)
{
    var app = new DummyClientApp();
    return app.run();
}
