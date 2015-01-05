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

/**
 * Command callbacks..
 */
delegate void cmd_callback(string? line);

/**
 * Assists in command parsing
 * @note If min_params is 0, max_params MUST NOT be 0
 */
struct Command {
    weak cmd_callback cb; /**< Callback for this command */
    int min_params; /**< Minimum parameters */
    int max_params; /**< Maximum parameters */
    string? help; /**<Optional help string, highly recommended to set. */
    bool offline; /**<If this command can be used while not connected */
    bool server; /**<If you can run this in the server tab */
}

/**
 * Main client GUI
 */
public class DummyClient : Gtk.ApplicationWindow
{
    Gtk.HeaderBar header;
    IrcTextEntry input;
    IrcTextWidget? main_view;
    Gtk.ScrolledWindow scroll;
    IrcCore? core = null;
    IrcSidebar sidebar;
    string? target;
    Gtk.ToggleButton nick_button;
    Gtk.TreeView nick_list;

    HashTable<string,Gtk.TextBuffer> buffers;
    HashTable<string,Gtk.ListStore> nicklists;

    HashTable<IrcCore?,SidebarExpandable> roots;

    /** Command callbacks */
    HashTable<string,Command?> commands;

    Gtk.Revealer nick_reveal;
    Gtk.Revealer side_reveal;


    const string VOICE_ICON = "non-starred-symbolic";
    const string HALFOP_ICON = "semi-starred-symbolic";
    const string OP_ICON = "starred-symbolic";

    const string QUIT_MESSAGE = "Enough vacation-project testing for now!";
    const string JOIN_STRING = "Please try to /JOIN a channel first";

    /**
     * While in early alpha..
     */
    private void insert_disclaimer()
    {
        var buffer = new Gtk.TextBuffer(main_view.tags);
        string msg = """
This is barely alpha software, and may eat your cat, hamster or other cute pets.

Note that many features are not yet implemented, so here is a heads up:

 * DO NOT attempt commands other than /me right now, not implemented
 * Any command (/cmd) will just go to the current channel
 * This means do NOT PM NickServ! :)
 * SSL connection will accept all certificates by default right now.
    
Please enjoy testing, and report any bugs that you find!
This message won't be in the final versions :)

In the mean time, connect to a network using the button at the top left of this
window.

 - ufee1dead""";

        foreach (var line in msg.split("\n")) {
            main_view.add_message(buffer, "", line, IrcTextType.MOTD);
        }
        // set_buffer looks for this or core.ident
        buffer.set_data("longestnick", "info");
        set_buffer(buffer);
    }
    private void update_actions()
    {
        (application.lookup_action("join_channel") as SimpleAction).set_enabled(core != null && core.connected);
    }

    private void connect_server(string host, uint16 port, bool ssl, string? autojoin, IrcIdentity ident)
    {
        var header = sidebar.add_expandable(host, "network-server-symbolic");
        header.activated.connect(()=> {
            IrcCore core = header.get_data("icore");
            this.target = null;
            this.core = core;
            update_actions();
            var buf = get_named_buffer(core, "\\ROOT\\");
            /* Just ensures we don't use nicknames for sizing of our margin/indent */
            buf.set_data("longestnick", " ");
            set_buffer(buf);
            update_nick(core);

            nick_reveal.set_reveal_child(false);
            nick_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT);
        });
        side_reveal.set_reveal_child(true);

        /* Need moar status in window.. */
        message("Connecting to %s:%d", host, port);

        var core = new IrcCore(ident);
        roots[core] = header;
        header.set_data("icore", core);
        core.set_data("autojoin", autojoin);
        /* Now switch view.. */
        sidebar.select_row(header);

        core.names_list.connect((c,u)=> {
            /* Could be /NAMES response.. */
            if (get_nicklist(core,c,false) == null) {
                foreach (var user in u) {
                    nl_add_user(core, c, user);
                }
                if (core == this.core && this.target == c) {
                    nick_list.set_model(get_nicklist(core, c));
                }
            }
            message("Got names list for %s", c);
        });

        core.connecting.connect((s,h,p,m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, "", m, IrcTextType.SERVER);
            /* Just ensures we don't use nicknames for sizing of our margin/indent */
            main_view.update_tabs(buf, " ", true);
        });
        core.nick_error.connect(on_nick_error);

        core.server_info.connect((i)=> {
            if (i.network != null) {
                var root = roots[core];
                root.label = i.network;
            }
        });

        core.connect.begin(host, port, ssl, false); /* Currently not a UI option */
        core.messaged.connect(on_messaged);
        core.established.connect(()=> {
            string aj = core.get_data("autojoin");
            if (aj != null) {
                core.join_channel(aj);
            }
            update_actions();
            update_nick(core);
        });
        core.ctcp.connect(on_ctcp);
        core.joined_channel.connect((u,c)=> {
            update_actions();
            if (u.nick == core.ident.nick) {
                /* If we have a buffer here, reuse it. */
                var buf = get_named_buffer(core, c, false);
                SidebarExpandable? root = roots[core];
                SidebarItem? item;
                if (buf == null) {
                    item = root.add_item(c, "user-available-symbolic");
                    item.set_data("icore", core);
                    item.set_data("ichannel", c);
                    var tbuf = get_named_buffer(core, c);
                    tbuf.set_data("sitem", item); // Maybe its time to subclass TextBuffer :p
                    item.activated.connect(()=> {
                        var nbuf = get_named_buffer(core, c);
                        this.core = item.get_data("icore");
                        this.target = item.get_data("ichannel");
                        set_buffer(nbuf);
                        update_actions();
                        update_nick(core);
                        /* select appropriate nicklist.. */
                        var nlist = get_nicklist(core, this.target, false);
                        nick_list.set_model(nlist);
                        nick_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT);
                        nick_reveal.set_reveal_child(true);
                    });
                    buf = tbuf;
                } else {
                    buf = get_named_buffer(core, c, false);
                    item = buf.get_data("sitem");
                    item.usable = true;
                }
                root.set_expanded(true);
                root.select_item(item);
                main_view.add_message(buf, "", @"You have joined $(c)", IrcTextType.JOIN);
            } else {
                var buf = get_named_buffer(core, c); /* do nothing :P */
                main_view.add_message(buf, u.nick, @"has joined $(c)", IrcTextType.JOIN);

                nl_add_user(core, c, u);
            }
        });

        core.parted_channel.connect((u,c,r)=> {
            string msg = u.nick == core.ident.nick ? @"You have left $(c)" : @"has left $(c)";
            if (r != null) {
                msg += @" ($(r))";
            }
            var buf = get_named_buffer(core, c);
            main_view.add_message(buf, u.nick == core.ident.nick ? "" : u.nick, msg, IrcTextType.PART);
            /* Did **we** leave? :o */
            if (u.nick == core.ident.nick) {
                SidebarItem? item = buf.get_data("sitem");
                item.usable = false;
                nl_destroy(core, c);
                if (this.target == c) {
                    this.target = null;
                }
            } else {
                nl_remove_user(core, c, u);
            }
        });
        core.motd_start.connect((m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, "", m, IrcTextType.MOTD);
        });
        core.motd_line.connect((m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, "", m, IrcTextType.MOTD);
        });
        core.motd.connect((o,m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, "", m, IrcTextType.MOTD);
        });
        core.nick_changed.connect((u,n,us)=> {
            if (us) {
                update_nick(core);
            }
            /* Update nicklists when we have one, instead of iterating each list. */
            nicklists.foreach((cid,l)=> {
                /* See if its valid for this server */
                string? c = id_to_channel(core, cid);
                if (c != null && nl_rename_user(core, c, u, n)) {
                    /* Append a nick change message.. */
                    var buf = get_named_buffer(core, c);
                    if (buf != null) {
                        /* Update the channel buffer.. */
                        if (!us) {
                            main_view.add_nickchange(buf, u.nick, n, "changed their nick to");
                        } else {
                            main_view.add_nickchange(buf, u.nick, n, "changed your nick to", true);
                        }
                    }
                }
            });
        });
        core.user_quit.connect((u,r)=> {
            if (u.nick == ident.nick) {
                /* Derp? */
                return;
            }
            nicklists.foreach((cid,l)=> {
                /* See if its valid for this server */
                string? c = id_to_channel(core, cid);
                if (c != null && nl_remove_user(core, c, u)) {
                    /* Append a nick change message.. */
                    var buf = get_named_buffer(core, c);
                    if (buf != null) {
                        /* Update the channel buffer.. */
                        string quit_msg = "has quit IRC";
                        if (r != null) {
                            quit_msg += @" ($(r))";
                        }
                        main_view.add_message(buf, u.nick, quit_msg, IrcTextType.QUIT);
                    }
                }
            });
        });
    }

    private string? id_to_channel(IrcCore c, string id)
    {
        string p1 = @"$(c.id)";
        if (!id.has_prefix(p1)) {
            return null;
        }
        var ret = id.substring(p1.length);
        return ret;
    }

    private unowned Gtk.TextBuffer? get_named_buffer(IrcCore c, string name, bool create = true)
    {
        string compname = @"$(c.id)$(name)";
        Gtk.TextBuffer? buf;
        if (compname in buffers) {
            buf = buffers[compname];
        } else {
            if (!create) {
                return null;
            }
            buf = new Gtk.TextBuffer(main_view.tags);
            buffers[compname] = buf;
        }
        if (name == "\\ROOT\\") {
            buffers[compname].set_data("ignoretab", true);
        }
        return buffers[compname];
    }

    private unowned Gtk.ListStore? get_nicklist(IrcCore c, string channel, bool create = true)
    {
        string compname = @"$(c.id)$(channel)";
        Gtk.ListStore? list;
        if (compname in nicklists) {
            list = nicklists[compname];
        } else {
            if (!create) {
                return null;
            }
            list = new Gtk.ListStore(3, typeof(string), typeof(IrcUser), typeof(string));
            list.set_sort_func(1, nick_compare);
            list.set_sort_column_id(1, Gtk.SortType.ASCENDING);
            nicklists[compname] = list;
        }
        return nicklists[compname];
    }

    /**
     * Currently very trivial IrcUser comparison..
     */
    public int nick_compare(Gtk.TreeModel tmodel, Gtk.TreeIter a, Gtk.TreeIter b)
    {
        var model = tmodel as Gtk.ListStore;
        IrcUser? ia;
        IrcUser? ib;
        model.get(a, 1, out ia, -1);
        model.get(b, 1, out ib, -1);

        if (ia.op != ib.op) {
            if (ia.op) {
                return -1;
            }
            return 1;
        }

        return strcmp(ia.nick.down(), ib.nick.down());
    }

    public DummyClient(Gtk.Application application)
    {
        Object(application: application);

        header = new Gtk.HeaderBar();
        header.set_show_close_button(true);
        set_title("DummyClient");
        set_titlebar(header);
        header.set_title("DummyClient");

        main_view = new IrcTextWidget();

        commands = new HashTable<string,Command?>(str_hash, str_equal);
        /* Handle /me action */
        commands["me"] = Command() {
            cb = (line)=> {
                core.send_action(this.target, line);
                main_view.add_message(main_view.buffer, core.ident.nick, line,  IrcTextType.ACTION);
            },
            help = "%C <action>, sends an \"action\" to the current channel or person",
            min_params = 1
        };
        /* Handle /join */
        commands["join"] = Command() {
            cb = (line)=> {
                core.join_channel(line);
            },
            help = "%C <channel> [password], join the given channel with an optional password",
            min_params = 1,
            server = true
        };
        /* Handle /nick */
        commands["nick"] = Command() {
            cb = (line)=> {
                core.set_nick(line);
            },
            help = "%C <nickname>, set your new nickname on this IRC server",
            min_params = 1,
            max_params = 1,
            server = true
        };
        /* Allow raw quoting, no error handling for this atm. */
        commands["quote"] = Command() {
            cb = (line)=> {
                core.send_quote(line);
            },
            help = "%C <text>, send raw text to the server",
            min_params = 1,
            server = true
        };
        /* Allow starting a PM.. */
        commands["query"] = Command() {
            cb = (line)=> {
                var buffer = get_named_buffer(core, line);
                ensure_view(core, buffer, line, true);
            },
            help = "%C <user>, start a query with a user",
            min_params = 1,
            max_params = 1,
            server = true
        };
        /* Part from a channel */
        commands["part"] = Command() {
            cb = (line)=> {
                if (line == null) {
                    if (this.target == null) {
                        main_view.add_error(main_view.buffer, JOIN_STRING);
                    } else {
                        /* Current channel. (no default part message yet) */
                        SidebarItem? item = main_view.buffer.get_data("sitem");
                        if (item.usable) {
                            main_view.add_error(main_view.buffer, JOIN_STRING);
                        } else {
                            core.part_channel(this.target, null);
                        }
                    }
                } else {
                    var splits = line.strip().split(" ");
                    if (splits.length == 1) {
                        core.part_channel(splits[0], null);
                    } else {
                        core.part_channel(splits[0], string.joinv(" ", splits[1:splits.length]));
                    }
                }
            },
            help = "%C [channel] [reason], leave a given channel with an optional reason, or the current one",
            min_params = 0,
            max_params = -1,
            server = true
        };
        /* Currently personal favourite. :P */
        commands["cycle"] = Command() {
            cb = (line)=> {
                if (line == null) {
                    if (this.target == null) {
                        main_view.add_error(main_view.buffer, JOIN_STRING);
                    } else {
                        core.part_channel(this.target, null);
                        core.join_channel(this.target);
                    }
                } else {
                    core.part_channel(line, null);
                    core.join_channel(line);
                }
            },
            help = "%C [channel], part and immediately rejoin the channel",
            min_params = 0,
            max_params = 1,
            server = true
        };
        commands["help"] = Command() {
            cb = (line)=> {
                if (line == null) {
                    /* Display all help topics.. */
                    main_view.add_info(main_view.buffer, "");
                    main_view.add_info(main_view.buffer, "For info on a given command, type /HELP [command]. Available commands are:");
                    main_view.add_info(main_view.buffer, "");
                    commands.foreach((k,v)=> {
                        main_view.add_info(main_view.buffer, "\u2022 %s", k);
                    });
                    main_view.add_info(main_view.buffer, "");
                } else {
                    main_view.add_info(main_view.buffer, "");
                    if (!(line in commands)) {
                        main_view.add_info(main_view.buffer, "%s: Unknown command. Type /HELP for a list of commands.", line);
                    } else {
                        main_view.add_info(main_view.buffer, "%s", template(commands[line].help, line));
                    }
                }
            },
            help = "%s - Display help",
            min_params = 0,
            max_params = -1,
            server = true,
            offline = true
        };
        /* actions.. */
        var btn = new Gtk.MenuButton();
        btn.margin_left = 6;
        var img = new Gtk.Image.from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON);
        btn.add(img);
        header.pack_start(btn);
        var menu = new Menu();
        menu.append("Connect to server", "app.connect");
        menu.append("Join channel", "app.join_channel");
        btn.set_menu_model(menu);
        btn.set_use_popover(true);

        /* join channel. */
        var action = new SimpleAction("join_channel", null);
        action.activate.connect(()=> {
            queue_draw();
            Idle.add(()=> {
                var dlg = new JoinChannelDialog(this);
                if (dlg.run() == Gtk.ResponseType.OK) {
                    core.join_channel(dlg.response_text);
                }
                dlg.destroy();
                return false;
            });
        });
        application.add_action(action);
        /* connect to server. */
        action = new SimpleAction("connect", null);
        action.activate.connect(()=> {
            queue_draw();
            Idle.add(()=> {
                show_connect_dialog();
                return false;
            });
        });
        application.add_action(action);

        btn = new Gtk.MenuButton();
        img = new Gtk.Image.from_icon_name("emblem-system-symbolic", Gtk.IconSize.BUTTON);
        btn.add(img);
        menu = new Menu();
        menu.append("Show timestamps", "app.timestamps");
        menu.append("Show margin", "app.margin");
        btn.set_menu_model(menu);
        btn.set_use_popover(true);
        header.pack_end(btn);

        /* toggle timestamps */
        var paction = new PropertyAction("timestamps", main_view, "use_timestamp");
        application.add_action(paction);
        paction = new PropertyAction("margin", main_view, "visible_margin");
        application.add_action(paction);

        update_actions();

        set_icon_name("xchat");

        var main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        add(main_layout);

        /* Sidebar.. */
        scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        sidebar = new IrcSidebar();
        scroll.add(sidebar);
        side_reveal = new Gtk.Revealer();
        side_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_RIGHT);
        side_reveal.add(scroll);
        main_layout.pack_start(side_reveal, false, false, 0);

        buffers = new HashTable<string,Gtk.TextBuffer>(str_hash, str_equal);
        roots = new HashTable<IrcCore?,SidebarExpandable>(direct_hash, direct_equal);
        nicklists =  new HashTable<string,Gtk.ListStore>(str_hash, str_equal);

        var layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 3);
        main_layout.pack_start(layout, true, true, 0);
        layout.margin = 3;
        sidebar.margin_top = 3;

        scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_shadow_type(Gtk.ShadowType.IN);
        main_view.set_editable(false);
        main_view.use_timestamp = true;
        scroll.add(main_view);
        layout.pack_start(scroll, true, true, 0);

        var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        bottom.get_style_context().add_class("linked");
        layout.pack_end(bottom, false, false, 0);
        nick_button = new Gtk.ToggleButton.with_label("");
        bottom.pack_start(nick_button, false, false, 0);

        /* Shmancy. Popover to change nickname =) */
        var entry = new Gtk.Entry();
        var pop = new Gtk.Popover(nick_button);
        entry.activate.connect(()=> {
            var txt = entry.text.strip();
            pop.hide();
            if (txt.length == 0) {
                return;
            }
            if (core == null) {
                warning("Cannot set nick without IRCCORE!");
                return;
            }
            core.set_nick(txt);
        });

        pop.closed.connect(()=> {
            nick_button.freeze_notify();
            nick_button.set_active(false);
            nick_button.thaw_notify();
            entry.set_text("");
        });
        pop.border_width = 10;
        pop.add(entry);

        nick_button.clicked.connect(()=> {
            pop.show_all();
        });
        nick_button.set_sensitive(false);
        input = new IrcTextEntry();
        input.activate.connect(send_text);
        bottom.pack_end(input, true, true, 0);

        /* Nicklist. */
        nick_list = new Gtk.TreeView();
        nick_list.set_headers_visible(false);
        var nscroll = new Gtk.ScrolledWindow(null, null);
        nscroll.set_shadow_type(Gtk.ShadowType.IN);
        nscroll.margin = 3;
        nscroll.margin_left = 0;
        nscroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        var render = new Gtk.CellRendererText();
        render.set_padding(20, 5);
        render.alignment = Pango.Alignment.LEFT;
        nick_list.insert_column_with_attributes(-1, "Name", render, "text", 0);
        var prender = new Gtk.CellRendererPixbuf();
        prender.set_padding(5, 0);
        nick_list.insert_column_with_attributes(-1, "Icon", prender, "icon_name", 2);

        nscroll.add(nick_list);
        nick_reveal = new Gtk.Revealer();
        nick_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT);
        nick_reveal.add(nscroll);
        main_layout.pack_end(nick_reveal, false, false, 0);

        delete_event.connect(handle_quit);

        set_default_size(800, 550);
        window_position = Gtk.WindowPosition.CENTER;

        insert_disclaimer();
        /*
        Idle.add(()=> {
            show_connect_dialog();
            return false;
        });*/
    }

    private void update_nick(IrcCore core)
    {
        if (this.core == core) {
            nick_button.set_sensitive(core.connected);
            nick_button.set_label(core.ident.nick);
        }
    }

    private void nl_destroy(IrcCore core, string channel)
    {
        var nlist = get_nicklist(core, channel, false);
        if (nlist == null) {
            return;
        }
        if (nick_list.get_model() == nlist) {
            nick_list.set_model(null);
        }
        nicklists.remove(@"$(core.id)$(channel)");
        nlist = null;
    }

    private bool nl_remove_user(IrcCore core, string channel, IrcUser user)
    {
        /* Remove user from nicklist */
        var nlist = get_nicklist(core, channel, false);
        if (nlist == null) {
            return false;
        }
        Gtk.TreeIter iter;
        nlist.get_iter_first(out iter);
        while (true) {
            IrcUser? u;
            nlist.get(iter, 1, out u, -1);
            if (u.nick == user.nick) {
                /* Found him. */
                nlist.remove(iter);
                return true;
            }
            if (!nlist.iter_next(ref iter)) {
                break;
            }
        }
        return false;
    }

    private bool nl_rename_user(IrcCore core, string channel, IrcUser old, string newu)
    {
        var nlist = get_nicklist(core, channel, false);
        if (nlist == null) {
            return false;
        }

        Gtk.TreeIter iter;
        nlist.get_iter_first(out iter);
        while (true) {
            IrcUser? u;
            nlist.get(iter, 1, out u, -1);
            if (u.nick == old.nick) {
                u.nick = newu;
                nlist.set(iter, 1, u, 0, u.nick);
                return true;
            }
            if (!nlist.iter_next(ref iter)) {
                break;
            }
        }
        return false;
    }

    private void nl_add_user(IrcCore core, string channel, IrcUser user)
    {
        var list = get_nicklist(core, channel);

        Gtk.TreeIter iter;
        list.append(out iter);

        IrcUser copy = IrcUser();
        copy.username = user.username;
        copy.nick = user.nick;
        copy.op = user.op;
        copy.hostname = user.hostname;

        string icon_name = null;
        if (copy.op) {
            icon_name = OP_ICON;
        } else if (copy.voice) {
            icon_name = VOICE_ICON;
        }

        list.set(iter, 0, copy.nick, 1, copy, 2, icon_name);
    }

    public bool handle_quit(Gdk.EventAny evt)
    {
        hide();

        /* Disconnect from all IRC networks and clean up.. */
        roots.foreach((k,v)=> {
            message("Disconnecting from server..");
            if (k.connected) {
                k.quit(QUIT_MESSAGE);
            }
        });

        return Gdk.EVENT_PROPAGATE;
    }

    private void on_nick_error(IrcCore core, string nick, IrcNickError e, string human)
    {
        /* Note, these messages should ideally go to the *current* view. */
        switch (e) {
            case IrcNickError.IN_USE:
                /* Attempt to reuse the name with a _, if the nick was in use during
                 * connection. */
                var buffer = get_named_buffer(core, "\\ROOT\\");
                main_view.add_error(buffer, "%s is already in use", nick);
                string? tmp_nick = core.get_data("attemptnick");
                if (tmp_nick == null) {
                    tmp_nick = core.ident.nick;
                }

                tmp_nick += "_";

                if (!core.connected) {
                    int count = core.get_data("nicktries");
                    if (count >= 3) {
                        main_view.add_error(buffer, "Attempted too many times to change nick");
                        main_view.add_error(buffer, "Disconnecting");
                        core.disconnect();
                        break;
                    }
                    core.set_nick(tmp_nick);
                    count++;
                    core.set_data("nicktries", count);
                    core.set_data("attemptnick", tmp_nick);
                }
                break;
            default:
                var buffer = get_named_buffer(core, "\\ROOT\\");
                main_view.add_error(buffer, "%s: %s", nick, human);
                break;
        }
    }

    /**
     * Show a network connect dialog. In future we'll have identities and stored
     * networks
     */
    private void show_connect_dialog()
    {
        var dlg = new ConnectDialog(this);
        if (dlg.run() == Gtk.ResponseType.OK) {
            IrcIdentity ident = IrcIdentity() {
                nick = "ikeytestclient", /* Backup */
                username = "dummyclient",
                gecos = "Ikeys Test Client",
                mode = 0
            };
            ident.nick = dlg.nickname;
            connect_server(dlg.host, dlg.port, dlg.ssl, dlg.channel, ident);
        }
        dlg.destroy();
    }

    /**
     * NOTE: We must log these and make the responses optional/customisable!
     */
    private void on_ctcp(IrcCore core, IrcUser user, string command, string text, bool privmsg)
    {
        switch (command) {
            case "VERSION":
                core.send_ctcp(user.nick, "VERSION", "DummyClient 0.1 / Probably Linux!", privmsg);
                break;
            case "PING":
                if (text == "") {
                    warning("%s sent us a borked CTCP PING with no timestamp", user.nick);
                } else {
                    core.send_ctcp(user.nick, "PING", text, privmsg);
                }
                break;
            default:
                warning("Unknown CTCP request (%s %s) from %s: ", command, text, user.nick);
                break;
            }
    }

    protected void send_text()
    {
        if (input.text.length < 1) {
            return;
        }
        string message = input.text;

        if (message.has_prefix("/") && message.length >= 2) {
            parse_command(message);
            input.set_text("");
            return;
        }

        if (core == null) {
            main_view.add_error(main_view.buffer, "You are not currently connected");
            input.set_text("");
            return;
        }
        if (target == null) {
            main_view.add_error(main_view.buffer, JOIN_STRING);
            input.set_text("");
            return;
        }
        if (message.length == 0) {
            return;
        }
        message = message.replace("\r","");
        var buffer = get_named_buffer(core, target);
        input.set_text("");

        /* We really need to think about output throttling. */
        foreach (var msg in message.split("\n")) {
            core.send_message(target, msg);
            main_view.add_message(buffer, core.ident.nick, msg, IrcTextType.MESSAGE);
        }
        main_view.update_tabs(buffer, core.ident.nick);
    }

    void activate_view(SidebarItem? item)
    {
        this.target = item.get_data("iuser");
        this.core = item.get_data("icore");
        var buf = get_named_buffer(core, this.target);
        set_buffer(buf);
        update_actions();
        update_nick(core);
        nick_reveal.set_reveal_child(false);
        nick_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT);
    }

    /**
     * Ensure we have a view for private messages
     */
    private void ensure_view(IrcCore core, Gtk.TextBuffer buffer, string nick, bool activate = false)
    {
        SidebarItem? item = buffer.get_data("sitem");
        if (item == null) {
            var root = roots[core];
            item = root.add_item(nick, "avatar-default-symbolic");
            buffer.set_data("sitem", item);
            item.set_data("iuser", nick);
            item.set_data("icore", core);
            item.activated.connect(activate_view);
        }
        if (activate) {
            var root = roots[core];
            root.select_item(item);
        }
    }

    private void set_buffer(Gtk.TextBuffer buffer)
    {
        main_view.set_buffer(buffer);
        string longest_nick = buffer.get_data("longestnick");
        main_view.update_tabs(buffer, longest_nick != null ? longest_nick : core.ident.nick);
        main_view.scroll_to_bottom(buffer);
    }

    protected void on_messaged(IrcCore core, IrcUser user, string target, string message, IrcMessageType type)
    {
        Gtk.TextBuffer? buffer;

        if ((type & IrcMessageType.PRIVATE) != 0) {
            /* private message.. */
            buffer = get_named_buffer(core, user.nick);
            ensure_view(core, buffer, user.nick);
        } else {
            buffer = get_named_buffer(core, target);
        }
        if ((type & IrcMessageType.ACTION) != 0) {
            main_view.add_message(buffer, user.nick, message, IrcTextType.ACTION);
        } else {
            main_view.add_message(buffer, user.nick, message, IrcTextType.MESSAGE);
        }
    }

    /**
     * Later on this will be expanded, right now it just replaces
     * %C with the command name.
     */
    string template(string input, string cmd)
    {
        var t = input.replace("%C", cmd.up());
        return t;
    }

    /**
     * Handle a command
     */
    void parse_command(string? iline)
    {
        var line = iline.substring(1);

        var p = line.split(" ");
        var cmd = p[0].down();
        if (!(cmd in commands)) {
            main_view.add_error(main_view.buffer, "Unknown command: %s", cmd);
            return;
        }
        weak Command? command = commands.lookup(cmd);
        if (this.core == null && !command.offline) {
            main_view.add_error(main_view.buffer, "/%s can only be used while connected", cmd);
            return;
        }
        if (this.target == null && !command.server) {
            main_view.add_error(main_view.buffer, "/%s cannot be used in the server view", cmd);
            return;
        }
        var r = p[1:p.length];
        if (r.length < command.min_params) {
            if (command.help != null) {
                var parsed = template(command.help, cmd.up());
                main_view.add_error(main_view.buffer, "Usage: %s", parsed);
            } else {
                main_view.add_error(main_view.buffer, "Invalid use of /%s", cmd);
            }
            return;
        }
        if (r.length > command.max_params && command.max_params >= command.min_params) {
            if (command.help != null) {
                var parsed = template(command.help, cmd.up());
                main_view.add_error(main_view.buffer, "Usage: %s", parsed);
            } else {
                main_view.add_error(main_view.buffer, "Invalid use of /%s", cmd);
            }
            return;
        }
        string? remnant;
        if (r.length >= 1) {
            remnant = string.joinv(" ", p[1:p.length]);
        } else {
            remnant = null;
        }
        command.cb(remnant);
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

public class ConnectDialog : Gtk.Dialog
{

    public string host { public get; private set; }
    public uint16 port { public get; private set; }
    public bool ssl { public get; private set; }
    public string channel { public get; private set; }
    public string nickname { public get; private set; }

    private Gtk.Entry nick_ent;
    private Gtk.Entry host_ent;
    private Gtk.Widget con;
    private Gtk.CheckButton check;

    public ConnectDialog(Gtk.Window parent)
    {
        Object(transient_for: parent);

        add_button("Cancel", Gtk.ResponseType.CANCEL);
        var w = add_button("Connect", Gtk.ResponseType.OK);
        w.get_style_context().add_class("suggested-action");
        w.set_sensitive(false);
        con = w;

        var grid = new Gtk.Grid();
        int row = 0;
        int column = 0;
        int norm_size = 1;
        int max_size = 3;

        /* hostname */
        var label = new Gtk.Label("Hostname");
        label.halign = Gtk.Align.START;
        grid.attach(label, column, row, norm_size, norm_size);
        var entry = new Gtk.Entry();
        host_ent = entry;
        entry.changed.connect(()=> {
            do_validate(false);
        });
        entry.activate.connect(()=> {
            do_validate(true);
        });
        entry.hexpand = true;
        grid.attach(entry, column+1, row, max_size-1, norm_size);
        grid.column_spacing = 12;
        grid.row_spacing = 12;

        row++;
        /* port */
        label = new Gtk.Label("Port");
        label.halign = Gtk.Align.START;
        grid.attach(label, column, row, norm_size, norm_size);
        var scale = new Gtk.SpinButton.with_range(0, 65555, 1);
        scale.value_changed.connect(()=> {
            this.port = (uint16)scale.value;
        });
        scale.set_value(6667);
        grid.attach(scale, column+1, row, norm_size, norm_size);
        check = new Gtk.CheckButton.with_label("Use SSL");
        check.clicked.connect(()=> {
            this.ssl = check.active;
        });
        grid.attach(check, column+2, row, norm_size, norm_size);

        /* user info, not supporting additional ident features yet.. */
        row++;
        label = new Gtk.Label("Nickname");
        label.halign = Gtk.Align.START;
        grid.attach(label, column, row, norm_size, norm_size);
        entry = new Gtk.Entry();
        nick_ent = entry;
        entry.text = Environment.get_user_name();
        entry.hexpand = true;
        grid.attach(entry, column+1, row, max_size-1, norm_size);

        /* Nick validation.. */
        entry.changed.connect(()=> {
            do_validate(false);
        });
        entry.activate.connect(()=> {
            do_validate(true);
        });

        row++;
        /* channel */
        label = new Gtk.Label("Channel");
        label.halign = Gtk.Align.START;
        grid.attach(label, column, row, norm_size, norm_size);
        entry = new Gtk.Entry();
        entry.hexpand = true;
        entry.changed.connect(()=> {
            channel = entry.text;
        });
        entry.activate.connect(()=> {
            do_validate(true);
        });
        grid.attach(entry, column+1, row, max_size-1, norm_size);

        grid.margin_bottom = 6;

        get_content_area().set_border_width(10);
        get_content_area().add(grid);
        get_content_area().show_all();
    }

    private void do_validate(bool emit)
    {
        unichar[] spcls = {
            '[', ']', '\\', '\'', '_', '^', '{', '|', '}'
        };

        /* Test nick first.. */
        var txt = nick_ent.text;
        bool valid = true;
        string? fail = "";
        if (txt.strip() == "") {
            valid = false;
            fail = "Nickname must be entered";
        } else {
            valid = true;
            if (!(txt.get_char(0) in spcls)) {
                if(!txt.get_char(0).isalpha()) {
                    valid = false;
                    fail = "Nicknames may only start with: a-z, A-Z, [] \\ ' _ ^ { | } ";
                }
            }
            if (txt.length > 1) {
                for (int i=1; i < txt.length; i++) {
                    unichar c = txt.get_char(i);
                    if (!(c in spcls)) {
                        if (!c.isalnum()) {
                            if (c != '-') {
                                valid = false;
                                fail = "Nicknames may only contain: a-z, A-Z, 0-9, [] \\ ' _ ^ { | } -";
                                break;
                            }
                        }
                    }
                }
            }
        }
        if (!valid) {
            nick_ent.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "dialog-error-symbolic");
            nick_ent.set_icon_tooltip_text(Gtk.EntryIconPosition.PRIMARY, fail);
            con.set_sensitive(false);
            return;
        } else {
            nick_ent.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, null);
            nick_ent.set_icon_tooltip_text(Gtk.EntryIconPosition.PRIMARY, null);
        }

        if (host_ent.text.strip() == "") {
            con.set_sensitive(false);
            return;
        }

        host = host_ent.text;
        nickname = nick_ent.text;
        con.set_sensitive(true);

        if (emit) {
            response(Gtk.ResponseType.OK);
        }
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
