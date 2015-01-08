/*
 * QuirkyClient.vala
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
public class QuirkyClient : Gtk.ApplicationWindow
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

    const string ADDRESSING_CHAR = ",";


    /** Store our client messages.. */
    HashTable<string,string> _messages;

    const string VOICE_ICON = "non-starred-symbolic";
    const string HALFOP_ICON = "semi-starred-symbolic";
    const string OP_ICON = "starred-symbolic";

    const string QUIT_MESSAGE = "Enough vacation-project testing for now!";
    const string JOIN_STRING = "Please try to /JOIN a channel first";

    bool is_channel = false;

    /**
     * While in early alpha..
     */
    private void insert_disclaimer()
    {
        var buffer = new Gtk.TextBuffer(main_view.tags);
        string msg = """
This is barely alpha software, and may eat your cat, hamster or other cute pets.

Note that many features are not yet implemented, so here is a heads up:

 * STARTTLS is currently disabled until CAP is implemented
 * SSL connection will accept all certificates by default right now.
 * For implemented commands, type /HELP
 * Unimplemented commands can be bypassed with /QUOTE, but may cause issues!!
 * Missing modes, kick support, etc.
    
Please enjoy testing, and report any bugs that you find!
This message won't be in the final versions :)

In the mean time, connect to a network using the button at the top left of this
window.

 - ufee1dead """;

        foreach (var line in msg.split("\n")) {
            main_view.add_message(buffer, null, _M(MSG.DISCLAIM), line);
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
            this.is_channel = false;

            nick_reveal.set_reveal_child(false);
            nick_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT);
        });

        side_reveal.set_reveal_child(true);
        /* reverse the polarity >_> */
        side_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_RIGHT);

        /* Need moar status in window.. */
        message("Connecting to %s:%d", host, port);

        var core = new IrcCore(ident);
        roots[core] = header;
        header.set_data("icore", core);
        core.set_data("autojoin", autojoin);

        /* init/setup */
        {
            var buf = get_named_buffer(core, "\\ROOT\\");
            buf.set_data("header", header);
        }

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
            main_view.add_message(buf, null, _M(MSG.INFO), m);
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
                    var tbuf = get_named_buffer(core, c);
                    tbuf.set_data("sitem", item); // Maybe its time to subclass TextBuffer :p
                    is_channel = true;
                    item.activated.connect(()=> {
                        var nbuf = get_named_buffer(core, c);
                        this.core = item.get_data("icore");
                        if (item.usable) {
                            this.target = item.get_data("ichannel");
                        }
                        this.is_channel = true;
                        set_buffer(nbuf);
                        update_actions();
                        update_nick(core);
                        /* select appropriate nicklist.. */
                        var nlist = get_nicklist(core, this.target, false);
                        nick_list.set_model(nlist);
                        nick_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT);
                        nick_reveal.set_reveal_child(true);
                        item.count.count = 0;
                        item.count.priority = CountPriority.NORMAL;
                    });
                    buf = tbuf;
                } else {
                    buf = get_named_buffer(core, c, false);
                    item = buf.get_data("sitem");
                    item.usable = true;
                }
                item.set_data("ichannel", c);
                item.set_data("_ichannel", c); // for close_view

                root.set_expanded(true);
                root.select_item(item);
                main_view.add_message(buf, core.ident.nick, _M(MSG.YOU_JOIN), core.ident.nick, c);
            } else {
                var buf = get_named_buffer(core, c); /* do nothing :P */
                main_view.add_message(buf, u.nick, _M(MSG.JOIN), u.nick, c);

                nl_add_user(core, c, u);
            }
        });

        core.parted_channel.connect((u,c,r)=> {
            string msg = u.nick == core.ident.nick ? @"You have left $(c)" : @"has left $(c)";
            if (r != null) {
                msg += @" ($(r))";
            }
            var buf = get_named_buffer(core, c, false);
            if (buf == null) {
                return;
            }
            string response;
            if (u.nick == core.ident.nick) {
                if (r == null) {
                    response = MSG.YOU_PART;
                } else {
                    response = MSG.YOU_PART_R;
                }
            } else {
                if (r == null) {
                    response = MSG.PART;
                } else {
                    response = MSG.PART_R;
                }
            }

            main_view.add_message(buf, u.nick, _M(response), u.nick, c, r);
            /* Did **we** leave? :o */
            if (u.nick == core.ident.nick) {
                SidebarItem? item = buf.get_data("sitem");
                if (item != null) {
                    item.usable = false;
                    nl_destroy(core, c);
                    if (this.target == c) {
                        this.target = null;
                    }
                }
                item.set_data("ichannel", null);
            } else {
                nl_remove_user(core, c, u);
            }
        });
        core.motd_start.connect((m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, null, _M(MSG.MOTD), m);
        });
        core.motd_line.connect((m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, null, _M(MSG.MOTD), m);
        });
        core.motd.connect((o,m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, null, _M(MSG.MOTD), m);
        });
        core.logging_in.connect(()=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, null, _M(MSG.LOGGING_IN), core.ident.account_id);
        });
        core.login_success.connect((a,m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, null, _M(MSG.LOGIN_SUCCESS), a, m);
        });
        core.login_failed.connect((m)=> {
            var buf = get_named_buffer(core, "\\ROOT\\");
            main_view.add_message(buf, null, _M(MSG.LOGIN_FAIL), m);
        });
        core.noticed.connect((u,t,m)=> {
            Gtk.TextBuffer? buf = null;
            /* server sent it */
            if (u.nick == null) {
                buf = get_named_buffer(core, "\\ROOT\\");
                main_view.add_message(buf, null, _M(MSG.SERVER_NOTICE), m);
                return;
            }

            if (t == core.ident.nick) {
                /* We got noticed. */
                buf = get_named_buffer(core, u.nick, false);
                /* notice to us. */
                if (buf == null && this.core == core) {
                    /* send to current buffer, its a direct notice */
                    buf = main_view.buffer;
                }
            } else {
                buf = get_named_buffer(core, t, false);
            }
            /* Default to server buffer */
            if (buf == null) {
                buf = get_named_buffer(core, "\\ROOT\\");
            }
            main_view.add_message(buf, u.nick, t == core.ident.nick?  _M(MSG.NOTICE) : _M(MSG.CHANNEL_NOTICE), u.nick, t, m);
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
                        main_view.add_message(buf, u.nick, us ? _M(MSG.YOU_NICK) : _M(MSG.NICK), u.nick, n);
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
                        main_view.add_message(buf, u.nick, _M(MSG.QUIT), u.nick, r);
                    }
                }
            });
        });
        core.topic.connect((c,t)=> {
            /* joined, or requested. */
            var buf = get_named_buffer(core, c, false);
            if (buf == null) {
                buf = get_named_buffer(core, "\\ROOT\\");
            }
            main_view.add_message(buf, null, _M(MSG.TOPIC), c, t);
        });
        core.topic_who.connect((c,u,s)=> {
            var buf = get_named_buffer(core, c, false);
            if (buf == null) {
                buf = get_named_buffer(core, "\\ROOT\\");
            }
            var date = new DateTime.from_unix_local(s);
            var datef = date.format("%x %X");
            /* need to format date at some point. */
            main_view.add_message(buf, null, _M(MSG.TOPIC_WHO), c, u.nick, u.username, u.hostname, datef);
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

    private unowned Gtk.ListStore? get_nicklist(IrcCore c, string? channel, bool create = true)
    {
        if (channel == null) {
            return null;
        }
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

    void init_messages()
    {
        try {
            var ini = new KeyFile();
            uint8[] data;
            /* For now we'll pull the one in from the binary */
            var f = File.new_for_uri("resource:///com/evolve_os/irc_client/messages.conf");
            f.load_contents(null, out data, null);
            ini.load_from_data((string)data, data.length, KeyFileFlags.NONE);

            foreach (var key in ini.get_keys("Messages")) {
                var s = ini.get_string("Messages", key);
                if (s.has_prefix(" ")) {
                    s = s.substring(1);
                }
                _messages[key] = s;
            }
        } catch (Error e) {
            message("MISSING MESSAGES CONFIG: %s", e.message);
            /* Coredumping is so last century. */
        }
    }

    /**
     * Return a string, check MSG for index names
     */
    string _M(string key) {
        if (!(key in _messages)) {
            warning("MISSING TEXT: %s", key);
            return "@@@MISSING@@@";
        }
        return _messages[key];
    }

    private void add_error(Gtk.TextBuffer buf, string fmt, ...)
    {
        va_list va = va_list();
        main_view.add_message(buf, null, _M(MSG.ERROR), fmt.vprintf(va));
    }

    private void add_info(Gtk.TextBuffer buf, string fmt, ...)
    {
        va_list va = va_list();
        main_view.add_message(buf, null, _M(MSG.INFO), fmt.vprintf(va));
    }

    public QuirkyClient(Gtk.Application application)
    {
        Object(application: application);


        _messages = new HashTable<string,string>(str_hash,str_equal);
        init_messages();

        {
            try {
                var f = File.new_for_uri("resource://com/evolve_os/irc_client/style.css");
                var css = new Gtk.CssProvider();
                css.load_from_file(f);
                Gtk.StyleContext.add_provider_for_screen(screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            } catch (Error e) {
                warning("CSS initialisation error: %s", e.message);
            }
        }

        header = new Gtk.HeaderBar();
        header.set_show_close_button(true);
        set_title("Quirky");
        set_titlebar(header);
        header.set_title("Quirky");

        main_view = new IrcTextWidget();

        commands = new HashTable<string,Command?>(str_hash, str_equal);
        /* Handle /me action */
        commands["me"] = Command() {
            cb = (line)=> {
                core.send_action(this.target, line);
                main_view.add_message(main_view.buffer, core.ident.nick, _M(MSG.ACTION), core.ident.nick, line);
            },
            help = "<action>, sends an \"action\" to the current channel or person",
            min_params = 1
        };
        /* Handle /join */
        commands["join"] = Command() {
            cb = (line)=> {
                core.join_channel(line);
            },
            help = "<channel> [password], join the given channel with an optional password",
            min_params = 1,
            server = true
        };
        /* Handle /nick */
        commands["nick"] = Command() {
            cb = (line)=> {
                core.set_nick(line);
            },
            help = "<nickname>, set your new nickname on this IRC server",
            min_params = 1,
            max_params = 1,
            server = true
        };
        /* Allow raw quoting, no error handling for this atm. */
        commands["quote"] = Command() {
            cb = (line)=> {
                core.send_quote(line);
            },
            help = "<text>, send raw text to the server",
            min_params = 1,
            server = true
        };
        /* Allow starting a PM.. */
        commands["query"] = Command() {
            cb = (line)=> {
                var buffer = get_named_buffer(core, line);
                ensure_view(core, buffer, line, true);
            },
            help = "<user>, start a query with a user",
            min_params = 1,
            max_params = 1,
            server = true
        };
        /* Part from a channel */
        commands["part"] = Command() {
            cb = (line)=> {
                if (line == null) {
                    if (this.target == null || !this.is_channel) {
                        add_error(main_view.buffer, JOIN_STRING);
                    } else {
                        /* Current channel. (no default part message yet) */
                        SidebarItem? item = main_view.buffer.get_data("sitem");
                        if (!item.usable) {
                            add_error(main_view.buffer, JOIN_STRING);
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
            help = "[channel] [reason], leave a given channel with an optional reason, or the current one",
            min_params = 0,
            max_params = -1,
            server = true
        };
        /* Currently personal favourite. :P */
        commands["cycle"] = Command() {
            cb = (line)=> {
                if (line == null) {
                    if (this.target == null) {
                        add_error(main_view.buffer, JOIN_STRING);
                    } else {
                        core.part_channel(this.target, null);
                        core.join_channel(this.target);
                    }
                } else {
                    core.part_channel(line, null);
                    core.join_channel(line);
                }
            },
            help = "[channel], part and immediately rejoin the channel",
            min_params = 0,
            max_params = 1,
            server = true
        };
        commands["help"] = Command() {
            cb = (line)=> {
                if (line == null) {
                    /* Display all help topics.. */
                    main_view.add_message(main_view.buffer, null, _M(MSG.HELP_LIST), "For info on a given command, type /HELP [command]. Available commands are:");
                    commands.foreach((k,v)=> {
                        main_view.add_message(main_view.buffer, null, _M(MSG.HELP_ITEM), k);
                    });
                } else {
                    if (!(line in commands)) {
                        add_info(main_view.buffer, "%s: Unknown command. Type /HELP for a list of commands.", line.split(" ")[0]);
                    } else {
                        main_view.add_message(main_view.buffer, line, _M(MSG.HELP_VIEW), line.up(), commands[line].help);
                    }
                }
            },
            help = "Display help",
            min_params = 0,
            max_params = -1,
            server = true,
            offline = true
        };
        commands["close"] = Command() {
            cb = (line)=> {
                close_view(main_view.buffer);
            },
            help = "closes the current view, parting or disconnecting as appropriate",
            min_params = 0,
            max_params = 0,
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
        menu.append("Use dark theme", "app.dark_theme");
        btn.set_menu_model(menu);
        btn.set_use_popover(true);
        header.pack_end(btn);

        /* toggle timestamps */
        var paction = new PropertyAction("timestamps", main_view, "use_timestamp");
        application.add_action(paction);
        paction = new PropertyAction("margin", main_view, "visible_margin");
        application.add_action(paction);

        paction = new PropertyAction("dark_theme", get_settings(), "gtk-application-prefer-dark-theme");
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
        input.set_completion_func(this.handle_completion);
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

    /**
     * Return a matched set of nicks for the given prefix
     *
     * @param c The relevant IrcCore
     * @param channel Channel to search
     * @param prefix Prefix to match against
     * @param store Where to store the results
     * @param line_start If its at the start of the line, use an addressing suffix
     * @param limit Maximum number of results to return
     */
    private void complete_nicks(IrcCore c, string channel, string prefix, ref string[] store, bool line_start, int limit = 10)
    {
        string[] ret = {};
        var nlist = get_nicklist(core, channel, false);
        if (nlist == null) {
            return;
        }
        Gtk.TreeIter iter;
        nlist.get_iter_first(out iter);
        while (true) {
            string nick;
            nlist.get(iter,  0, out nick, -1);
            if (nick.down().has_prefix(prefix.down())) {
                if (line_start) {
                    ret += nick + ADDRESSING_CHAR;
                } else {
                    ret += nick;
                }
            }
            if (ret.length == limit) {
                break;
            }
            if (!nlist.iter_next(ref iter)) {
                break;
            }
        }
        store = ret;
    }

    /**
     * Tab completion handling
     */
    private string[]? handle_completion(string prefix, string line)
    {
        string[] ret = {};

        if (this.core != null && this.target != null) {
            if (this.is_channel) {
                complete_nicks(this.core, this.target, prefix, ref ret, prefix == line);
            } else {
                /* PM, add users nick */
                if (this.target.down().has_prefix(prefix.down())) {
                    if (prefix == line) {
                        ret += target + ADDRESSING_CHAR;
                    } else {
                        ret += target;
                    }
                }
            }
        }

        /* Add joined channels to completion */
        if (this.core != null) {
            nicklists.foreach((cid,l)=> {
                string? c = id_to_channel(core, cid);
                if (c != null && c.down().has_prefix(prefix.down())) {
                    ret += c;
                }
            });
        }

        /* Just handle /commands for now
         * NOTE: Only handling / if the *line* starts with it. */
        if (line.has_prefix("/")) {
            commands.foreach((k,v)=> {
                if (("/" + k.down()).has_prefix(prefix.down())) {
                    ret += "/" + k;
                }
            });
        }
        return ret;
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

    void _disconnect()
    {
        hide();

        /* Disconnect from all IRC networks and clean up.. */
        roots.foreach((k,v)=> {
            message("Disconnecting from server..");
            if (k.connected) {
                k.quit(QUIT_MESSAGE);
            }
        });
    }

    public bool handle_quit(Gdk.EventAny evt)
    {
        _disconnect();

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
                add_error(buffer, "%s is already in use", nick);
                string? tmp_nick = core.get_data("attemptnick");
                if (tmp_nick == null) {
                    tmp_nick = core.ident.nick;
                }

                tmp_nick += "_";

                if (!core.connected) {
                    int count = core.get_data("nicktries");
                    if (count >= 3) {
                        add_error(buffer, "Attempted too many times to change nick");
                        add_error(buffer, "Disconnecting");
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
                add_error(buffer, "%s: %s", nick, human);
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
                nick = "quirky", /* Backup */
                username = "quirkyclient",
                gecos = "Quirky IRC Client",
                mode = 0
            };
            ident.password = dlg.password;
            switch (dlg.auth_type) {
                case "nickserv":
                    ident.auth =  AuthenticationMode.NICKSERV;
                    break;
                case "sasl":
                    ident.auth = AuthenticationMode.SASL;
                    break;
                default:
                    ident.password = null;
                    ident.auth = AuthenticationMode.NONE;
                    break;
            }
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
                core.send_ctcp(user.nick, "VERSION", "Quirky IRC Client 0.1 / Probably Linux!", privmsg);
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
            add_error(main_view.buffer, "You are not currently connected");
            input.set_text("");
            return;
        }
        if (target == null) {
            add_error(main_view.buffer, JOIN_STRING);
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
            main_view.add_message(buffer, core.ident.nick, _M(MSG.MESSAGE), core.ident.nick, msg);
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
        item.count.count = 0;
        item.count.priority = CountPriority.NORMAL;
        this.is_channel = false;
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
            root.set_expanded(true);

            root.select_item(item);
        }
    }


    /**
     * Close a view by its buffer. May be any supported view.
     */
    private void close_view(Gtk.TextBuffer? buffer)
    {
        SidebarExpandable? root;
        SidebarItem? item;
        IrcCore? core = null;
        string? channel = null;
        string? user = null;

        if (buffer == null) {
            return;
        }
        string dtarget = "";

        item = buffer.get_data("sitem");
        root = buffer.get_data("header");
        if (item != null) {
            channel = item.get_data("_ichannel");
            user = item.get_data("iuser");
            core = item.get_data("icore");
            root = roots[core];
            item.usable = false;
        } 

        /* Handle channel closes.. */
        if (channel != null) {
            if (item.usable) {
                /* Part the channel. */
                core.part_channel(channel, null);
                nl_destroy(core, channel);
            }
            dtarget = channel;
        } else if (user != null) {
            dtarget = user;
        } else {
            /* Server page.. ? */
            if (roots.size() == 0) {
                /* Just quit. */
                _disconnect();
                this.destroy();
                return;
            }
            if (roots.size() - 1 == 0) {
                side_reveal.set_reveal_child(false);
                side_reveal.set_transition_type(Gtk.RevealerTransitionType.SLIDE_RIGHT);
                insert_disclaimer(); // revert view.
            }
            core = root.get_data("icore");
            core.quit(QUIT_MESSAGE);
            sidebar.remove_expandable(root);
            roots.remove(core);
            string id = @"$(core.id)\\ROOT\\";
            buffers.remove(id);

            if (core == this.core ){
                core = null;
                this.core = null;
            }
            update_actions();
            // TODO: Add support to close/disconnect servers!
            return;
        }
        string id = @"$(core.id)$(dtarget)";

        buffers.remove(id);
        root.remove_item(item);
    }

    private void set_buffer(Gtk.TextBuffer buffer)
    {
        main_view.set_buffer(buffer);
        string longest_nick = buffer.get_data("longestnick");
        main_view.update_tabs(buffer, longest_nick != null ? longest_nick : core.ident.nick);
        main_view.scroll_to_bottom(buffer);
    }

    private bool is_highlight(IrcCore core, string message)
    {
        /* prevent modification of ident */
        var name = core.ident.nick;
        if (name.down() in message.down()) {
            return true;
        }
        return false;
    }

    protected void on_messaged(IrcCore core, IrcUser user, string target, string message, IrcMessageType type)
    {
        Gtk.TextBuffer? buffer;

        if ((type & IrcMessageType.PRIVATE) != 0) {
            /* private message.. */
            buffer = get_named_buffer(core, user.nick);
            ensure_view(core, buffer, user.nick);
            if (user.nick != this.target) {
                /* Update badge */
                SidebarItem? item = buffer.get_data("sitem");
                item.count.count++;
                /* Add better highlighting logic in future */
                if (is_highlight(core, message)) {
                    item.count.priority = CountPriority.HIGH;
                }
            }
        } else {
            buffer = get_named_buffer(core, target);
            if (target != this.target) {
                SidebarItem? item = buffer.get_data("sitem");
                item.count.count++;
                if (is_highlight(core, message)) {
                    item.count.priority = CountPriority.HIGH;
                }
            }
        }
        if ((type & IrcMessageType.ACTION) != 0) {
            main_view.add_message(buffer, user.nick, _M(MSG.ACTION), user.nick, message);
        } else {
            main_view.add_message(buffer, user.nick, _M(MSG.MESSAGE), user.nick, message);
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

        var p = line.strip().split(" ");
        var cmd = p[0].down();
        if (!(cmd in commands)) {
            add_error(main_view.buffer, "Unknown command: %s", cmd);
            return;
        }
        weak Command? command = commands.lookup(cmd);
        if (this.core == null && !command.offline) {
            add_error(main_view.buffer, "/%s can only be used while connected", cmd);
            return;
        }
        if (this.target == null && !command.server) {
            add_error(main_view.buffer, "/%s cannot be used in the server view", cmd);
            return;
        }
        var r = p[1:p.length];
        if (r.length < command.min_params) {
            if (command.help != null) {
                var parsed = template(command.help, cmd.up());
                add_error(main_view.buffer, "Usage: %s", parsed);
            } else {
                add_error(main_view.buffer, "Invalid use of /%s", cmd);
            }
            return;
        }
        if (r.length > command.max_params && command.max_params >= command.min_params) {
            if (command.help != null) {
                var parsed = template(command.help, cmd.up());
                add_error(main_view.buffer, "Usage: %s", parsed);
            } else {
                add_error(main_view.buffer, "Invalid use of /%s", cmd);
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
    public string password { public get; private set; }
    public string auth_type { public get; private set; }

    private Gtk.Entry nick_ent;
    private Gtk.Entry host_ent;
    private Gtk.Entry pass_entry;
    private Gtk.Entry channel_entry;
    private Gtk.Widget con;
    private Gtk.CheckButton check;
    private Gtk.Label auth_label;
    private Gtk.Entry auth_entry;

    public ConnectDialog(Gtk.Window parent)
    {
        Object(transient_for: parent);

        add_button("Cancel", Gtk.ResponseType.CANCEL);
        var w = add_button("Connect", Gtk.ResponseType.OK);
        w.get_style_context().add_class("suggested-action");
        w.set_sensitive(false);
        con = w;

        auth_type = "none";

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
        channel_entry = entry;
        channel_entry.changed.connect(()=> {
            channel = entry.text;
        });
        channel_entry.activate.connect(()=> {
            do_validate(true);
        });
        grid.attach(entry, column+1, row, max_size-1, norm_size);

        row++;
        label = new Gtk.Label("Authentication");
        label.halign = Gtk.Align.START;
        grid.attach(label, column, row, norm_size, norm_size);
        var combo = new Gtk.ComboBoxText();
        combo.append("none", "None");
        combo.append("nickserv", "NickServ");
        combo.append("sasl", "SASL (PLAIN)");
        grid.attach(combo, column+1, row, max_size-1, norm_size);
        combo.active_id = "none";

        combo.changed.connect(()=> {
            this.auth_type = combo.active_id;
            auth_label.set_visible(combo.active_id != "none");
            auth_entry.set_visible(combo.active_id != "none");
            do_validate(false);
        });

        get_content_area().set_border_width(10);
        get_content_area().add(grid);
        get_content_area().show_all();
        grid.no_show_all = true;

        row++;
        label = new Gtk.Label("Password");
        auth_label = label;
        label.halign = Gtk.Align.START;
        grid.attach(label, column, row, norm_size, norm_size);
        entry = new Gtk.Entry();
        entry.set_visibility(false);
        auth_entry = entry;
        entry.hexpand = true;
        grid.attach(entry, column+1, row, max_size-1, norm_size);

        pass_entry = entry;
        pass_entry.changed.connect(()=> {
            password = pass_entry.get_text();
        });

        grid.margin_bottom = 6;

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

        if (auth_type != "none" && auth_entry.text.strip() == "") {
            con.set_sensitive(false);
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
public class QuirkyClientApp : Gtk.Application
{
    static QuirkyClient win = null;

    public QuirkyClientApp()
    {
        Object(application_id: "com.evolve_os.QuirkyIrcClient", flags: ApplicationFlags.FLAGS_NONE);
    }

    public override void activate()
    {
        if (win == null) {
            win = new QuirkyClient(this);
        }
        win.show_all();
        win.present();
    }
}

public static int main(string[] args)
{
    var app = new QuirkyClientApp();
    return app.run();
}
