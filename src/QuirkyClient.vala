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
    HashTable<string,string> _colors;

    const string VOICE_ICON = "non-starred-symbolic";
    const string HALFOP_ICON = "semi-starred-symbolic";
    const string OP_ICON = "starred-symbolic";

    const string QUIT_MESSAGE = "Enough vacation-project testing for now!";
    const string JOIN_STRING = "Please try to /JOIN a channel first";

    bool is_channel = false;

    KeyFile settings;

    Gtk.Stack stack;
    NetworkListView connect_view;
    /**
     * While in early alpha..
     */
    private void insert_disclaimer()
    {
        var buffer = new Gtk.TextBuffer(main_view.tags);
        string msg = """
                         o8o           oooo
                         `"'           `888
  .ooooo oo oooo  oooo  oooo  oooo d8b  888  oooo  oooo    ooo
 d88' `888  `888  `888  `888  `888""8P  888 .8P'    `88.  .8'
 888   888   888   888   888   888      888888.      `88..8'
 888   888   888   888   888   888      888 `88b.     `888'
 `V8bod888   `V88V"V8P' o888o d888b    o888o o888o     .8'
       888.                                        .o..P'
       8P'                                         `Y8P'
       "


  ↠ Pre-alpha
  ↠ No SSL verification
  ↠ Per the name, quirky.

                                          - ufee1dead """;

        foreach (var line in msg.split("\n")) {
            main_view.add_message(buffer, null, _M(MSG.DISCLAIM), line);
        }
        // set_buffer looks for this or core.ident
        buffer.set_data("longestnick", "info");
        set_buffer(buffer);
    }

    private void init_settings()
    {
        settings = new KeyFile();
        var path = Path.build_path(Path.DIR_SEPARATOR_S, Environment.get_user_config_dir(), "quirky.conf");
        if (!FileUtils.test(path, FileTest.EXISTS)) {
            return;
        }
        IrcNetwork[] networks = {};

        try {
            settings.load_from_file(path, KeyFileFlags.NONE);
            bool b;

            if (settings.has_key("UI", "EnableMargin")) {
                b = settings.get_boolean("UI", "EnableMargin");
                main_view.visible_margin = b;
            }
            if (settings.has_key("UI", "EnableTimestamp")) {
                b = settings.get_boolean("UI", "EnableTimestamp");
                main_view.use_timestamp = b;
            }
            if (settings.has_key("UI", "EnableDarkTheme")) {
                b = settings.get_boolean("UI", "EnableDarkTheme");
                get_settings().set_property("gtk-application-prefer-dark-theme", b);
            }

            foreach (var section in settings.get_groups()) {
                if (!section.has_prefix("network:")) {
                    continue;
                }
                IrcNetwork n = IrcNetwork();
                n.name = section.split("network:")[1];
                if (!settings.has_key(section, "Hosts")) {
                    warning("Invalid network config: %s (no host)", n.name);
                    continue;
                }
                string[] hosts = settings.get_string_list(section, "Hosts");
                /* no cycle server handling yet. */
                var host = hosts[0];
                var port = 6667;
                bool ssl = false;
                if (":" in host) {
                    var rhost = host.split(":");
                    host = rhost[0];
                    if (rhost[1].has_prefix("+")) {
                        ssl = true;
                        port = int.parse(rhost[1].substring(1));
                    } else {
                        port  = int.parse(rhost[1]);
                    }
                }
                n.servers = new IrcServer[] {
                    IrcServer() {
                        hostname = host,
                        port = (uint16)port,
                        ssl = ssl
                    }
                };
                if (settings.has_key(section, "Nick1")) {
                    n.nick1 = settings.get_string(section, "Nick1");
                } else {
                    n.nick1 = "quirkyclient";
                }
                n.nick2 = n.nick1 + "_";
                n.nick3 = n.nick1 + "__";
                if (settings.has_key(section, "Gecos")) {
                    n.gecos = settings.get_string(section, "Gecos");
                } else {
                    n.gecos = "Quirky User";
                }
                if (settings.has_key(section, "Username")) {
                    n.username = settings.get_string(section, "Username");
                } else {
                    n.username = "quirky";
                }
                if (settings.has_key(section, "Channels")) {
                    n.channels = settings.get_string_list(section, "Channels");
                } else {
                    n.channels = new string[] { };
                }

                networks += n;
            }

        } catch (Error e) {
            warning("Badly handled error: %s", e.message);
        }

        if (networks.length > 0) {
            foreach (var net in networks) {
                this.connect_view.add_network(net);
            }
        } else {
            /* Please humbly accept this default :P */
            var n = IrcNetwork() {
                        name = "freenode",
                        username = Environment.get_user_name(),
                        gecos = "quirkyclient",
                        nick1 = "quirkyclient",
                        nick2 = "quirkyclient_",
                        nick3 = "quirkyclient__",
                        servers = new IrcServer[] {
                            IrcServer() { hostname = "irc.freenode.net", port = 6667, ssl = false }
                        },
                        channels = new string[] { "#evolveos" }
            };
            this.connect_view.add_network(n);
        }

    }

    private void flush_settings()
    {
        var path = Path.build_path(Path.DIR_SEPARATOR_S, Environment.get_user_config_dir(), "quirky.conf");

        try {
            var data = settings.to_data();
            FileUtils.set_contents(path, data);
/* TODO: Fix this for Windows! */
#if ! WINDOWSBUILD
            FileUtils.chmod(path, 00600);
#endif
        } catch (Error e) {
            warning("Badly handled flush error: %s", e.message);
        }
    }

    private void update_actions()
    {
        (application.lookup_action("join_channel") as SimpleAction).set_enabled(core != null && core.connected && stack.get_visible_child_name() != "connect");

        if (stack.get_visible_child_name() == "connect") {
            (application.lookup_action("add_server") as SimpleAction).set_enabled(true);
            (application.lookup_action("connect") as SimpleAction).set_enabled(false);
        } else {
            (application.lookup_action("add_server") as SimpleAction).set_enabled(false);
            (application.lookup_action("connect") as SimpleAction).set_enabled(true);
        }
    }

    private void connect_server(IrcNetwork? network)
    {
        var server = network.servers[0];
        var ident = IrcIdentity() {
            username = network.username,
            nick = network.nick1,
            gecos = network.gecos,
            auth = AuthenticationMode.NONE
        };

        var header = sidebar.add_expandable(server.hostname, "network-server-symbolic");
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
        message("Connecting to %s:%d", server.hostname, server.port);

        var core = new IrcCore(ident);
        core.set_data("network", network);
        roots[core] = header;
        header.set_data("icore", core);

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

        core.connect.begin(server.hostname, server.port, server.ssl, false); /* Currently not a UI option */
        core.messaged.connect(on_messaged);
        core.established.connect(()=> {
            IrcNetwork? n = core.get_data("network");
            /* TODO: Use a single call. */
            foreach (var channel in n.channels) {
                core.join_channel(channel);
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

            foreach (var key in ini.get_keys("Colors")) {
                var s = ini.get_string("Colors", key).strip();
                if (" " in s) {
                    s = s.replace(" ", "");
                    if (!s.has_prefix("#")) {
                        s = "#" + s;
                    }
                }
                _colors[key] = s;
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
        _colors = new HashTable<string,string>(str_hash,str_equal);
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

        main_view = new IrcTextWidget(_colors);
        main_view.use_timestamp = true;

        var connect = new NetworkListView();
        this.connect_view = connect;

        init_settings();

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
        commands["msg"] = Command() {
            cb = (line)=> {
                var splits = line.split(" ");
                var target = splits[0];
                var message = string.joinv(" ", splits[1:splits.length]);
                main_view.add_message(main_view.buffer, target, _M(MSG.PM), core.ident.nick, target, message);
                core.send_message(target, message);
            },
            help = "<user> <message>, send a message to a user without opening a new view",
            min_params = 2,
            max_params = -1,
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
        menu.append("Add a server", "app.add_server");
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
                input.grab_focus();
                return false;
            });
        });
        action.set_enabled(false);
        application.add_action(action);
        /* connect to server. */
        action = new SimpleAction("connect", null);
        action.activate.connect(()=> {
            queue_draw();
            Idle.add(()=> {
                stack.set_visible_child_name("connect");
                update_actions();
                return false;
            });
        });
        action.set_enabled(false);
        application.add_action(action);
        /* add server, only available on connect page.. */
        action = new SimpleAction("add_server", null);
        action.activate.connect(()=> {
            queue_draw();
            Idle.add(()=> {
                show_connect_dialog();
                return false;
            });
        });
        application.add_action(action);

        action = new SimpleAction("about", null);
        action.activate.connect(()=> {
            queue_draw();
            Idle.add(()=> {
                Gtk.show_about_dialog(this,
                    "program-name", "Quirky IRC Client",
                    "copyright", "Copyright \u00A9 2015 Ikey Doherty",
                    "website", "https://evolve-os.com",
                    "website-label", "Evolve OS",
                    "license-type", Gtk.License.GPL_2_0,
                    "comments", "IRC client for people who use IRC",
                    "version", "1",
                    "logo-icon-name", "quirky",
                    "artists", new string[] {
                        "Alejandro Seoane <asetrigo@gmail.com>"
                    },
                    "authors", new string[] {
                        "Ikey Doherty <ikey@evolve-os.com>"
                    }
                );
                input.grab_focus();
                return false;
            });
        });
        application.add_action(action);

        btn = new Gtk.MenuButton();
        img = new Gtk.Image.from_icon_name("emblem-system-symbolic", Gtk.IconSize.BUTTON);
        btn.add(img);
        menu = new Menu();
        btn.set_menu_model(menu);
        btn.set_use_popover(true);
        header.pack_end(btn);

        var submenu = new Menu();
        menu.append_submenu("Appearance", submenu);
        menu.append("Show timestamps", "app.timestamps");
        submenu.append("Show margin", "app.margin");
        submenu.append("Use dark theme", "app.dark_theme");

        submenu = new Menu();
        menu.append_section(null, submenu);
        submenu.append("About", "app.about");

        /* toggle timestamps */
        var paction = new PropertyAction("timestamps", main_view, "use_timestamp");
        application.add_action(paction);
        paction = new PropertyAction("margin", main_view, "visible_margin");
        application.add_action(paction);

        paction = new PropertyAction("dark_theme", get_settings(), "gtk-application-prefer-dark-theme");
        application.add_action(paction);

        set_icon_name("quirky");

        stack = new Gtk.Stack();
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);
        add(stack);

        connect.activated.connect(on_network_select);
        connect.edit.connect(on_network_edit);
        connect.closed.connect(()=> {
            this.stack.set_visible_child_name("main");
            update_actions();
        });
        stack.add_named(connect, "connect");
        var main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        stack.add_named(main_layout, "main");

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
        scroll.add(main_view);
        layout.pack_start(scroll, true, true, 0);

        var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        bottom.get_style_context().add_class("linked");
        layout.pack_end(bottom, false, false, 0);
        nick_button = new Gtk.ToggleButton.with_label("");
        nick_button.set_can_focus(false);
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

        input.set_can_default(true);
        input.grab_default();
        this.set_default(input);
        input.grab_focus();

        /* Due to using property actions */
        main_view.notify["visible-margin"].connect(()=> {
            try {
                settings.set_boolean("UI", "EnableMargin", main_view.visible_margin);
                flush_settings();
            } catch (Error e) {
                warning("Error setting boolean: %s", e.message);
            }
        });
        main_view.notify["use-timestamp"].connect(()=> {
            try {
                settings.set_boolean("UI", "EnableTimestamp", main_view.use_timestamp);
                flush_settings();
            } catch (Error e) {
                warning("Error setting boolean: %s", e.message);
            }
        });
        get_settings().notify["gtk-application-prefer-dark-theme"].connect(()=> {
            try {
                bool dark;
                get_settings().get("gtk-application-prefer-dark-theme", out dark);
                settings.set_boolean("UI", "EnableDarkTheme", dark);
                flush_settings();
            } catch (Error e) {
                warning("Error setting boolean: %s", e.message);
            }
        });


        insert_disclaimer();
        stack.set_visible_child_name("connect");
        /*
        Idle.add(()=> {
            show_connect_dialog();
            return false;
        });*/
    }

    void on_network_select(IrcNetwork? network, string[] channels)
    {
        stack.set_visible_child_name("main");
        network.channels = channels;
        connect_server(network);
            update_actions();
    }

    void on_network_edit(IrcNetwork? network)
    {
        show_connect_dialog(network);
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
     * Show a network connect dialog.
     *
     * TODO: Remove massive amounts of redundant storage......
     */
    private void show_connect_dialog(IrcNetwork? old = null)
    {
        var dlg = new ConnectDialog(this, old);
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
            ident.username = dlg.username;
            ident.gecos = dlg.gecos;

            IrcNetwork n = IrcNetwork() {
                 name = dlg.network,
                 username = ident.username,
                 gecos = ident.gecos,
                 password = ident.password,
                 auth = ident.auth,
                 channels = dlg.channel.split(" "),
                 nick1 = ident.nick,
                 nick2 = ident.nick + "_",
                 nick3 = ident.nick + "__",
                 servers = new IrcServer[] {
                    IrcServer() {
                         hostname = dlg.host,
                         port = dlg.port,
                         ssl = dlg.ssl
                     }
                 }
             };
             if (old != null) {
                 connect_view.remove_network(old);
                 try {
                    if (settings.has_group("network:" + old.name)) {
                        settings.remove_group("network:" + old.name);
                    }
                 } catch (Error e) {
                     warning("Badly handled config error: %s", e.message);
                 }
             }

             save_network(n);
             connect_view.add_network(n);
        }
        dlg.destroy();
        input.grab_focus();
    }

    void save_network(IrcNetwork n)
    {
        try {
            var sect = "network:" + n.name;
            if (settings.has_group(sect)) {
                settings.remove_group(sect);
            }

            string host1 = n.servers[0].hostname + ":";
            if (n.servers[0].ssl) {
                host1 += "+";
            }
            string[] hosts = {};
            host1 += n.servers[0].port.to_string();
            hosts += host1;
            settings.set_string_list(sect, "Hosts", hosts);
            settings.set_string(sect, "Nick1", n.nick1);
            settings.set_string(sect, "Gecos", n.gecos);
            settings.set_string(sect, "Username", n.username);
            settings.set_string_list(sect, "Channels", n.channels);
        } catch (Error e) {
            warning("Badly handled error: %s", e.message);
        }
        flush_settings();
    }

    /**
     * NOTE: We must log these and make the responses optional/customisable!
     */
    private void on_ctcp(IrcCore core, IrcUser user, string command, string text, bool privmsg)
    {
        switch (command) {
            case "VERSION":
                core.send_ctcp(user.nick, "VERSION", "Quirky IRC Client 1 / Probably Linux!", privmsg);
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

        IrcEntryLog? log = buffer.get_data("irclog");
        if (log == null) {
            log = new IrcEntryLog();
            buffer.set_data("irclog", log);
        }
        input.set_log(log);
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

public struct IrcServer {
    string hostname;
    uint16 port;
    bool ssl;
}

public struct IrcNetwork {
    string name;
    string username;
    string gecos;
    string nick1;
    string nick2;
    string nick3;
    IrcServer[] servers;
    string[] channels;
    string password;
    AuthenticationMode auth;
}
public class NetworkListView : Gtk.Box
{

    public signal void activated(IrcNetwork? network, string[] channels);
    public signal void edit(IrcNetwork? network);
    public signal void closed();

    HashTable<string,IrcNetwork?> networks;
    IrcNetwork? network;
    Gtk.Button connectbtn;
    Gtk.Button editbtn;
    Gtk.ComboBoxText combo;
    Gtk.Entry channels;

    public void add_network(IrcNetwork network)
    {
        if (!(network.name in networks)) {
            combo.append(network.name, network.name);
        }

        networks[network.name] = network;
        if (this.network != null && this.network.name == network.name) {
            this.network = network;
        }
        combo.set_active_id(network.name);
    }

    public void remove_network(IrcNetwork network)
    {
        if (network.name in networks) {
            combo.remove_all();
            networks.remove(network.name);
            networks.foreach((k,v)=>{
                combo.append(network.name, network.name);
            });
        }
    }

    void on_changed(Gtk.ComboBox? txt)
    {
        string active = (txt as Gtk.ComboBoxText).get_active_text();
        if (active in networks) {
            this.network = networks[active];
            connectbtn.set_sensitive(true);
            editbtn.set_sensitive(true);
            if (network.channels != null) {
                this.channels.set_text(string.joinv(" ", network.channels));
            } else {
                this.channels.set_text("");
            }
            return;
        }
        editbtn.set_sensitive(false);
        if (" " in active) {
            connectbtn.set_sensitive(false);
            return;
        }

        active = active.strip();
        if (active.length == 0) {
            connectbtn.set_sensitive(false);
            return;
        }

        uint16 port = 6667;
        bool ssl = false;
        string host = active;
        if (":" in active) {
            var splits = active.split(":");
            host = splits[0];
            var port_sect = splits[1];
            if (port_sect.has_prefix("+")) {
                ssl = true;
                port_sect = port_sect.substring(1);
                if (port_sect.length == 0) {
                    connectbtn.set_sensitive(false);
                    return;
                }
            }
            port = (uint16)int.parse(port_sect);
            if (port < 0) {
                port = 6667;
            }
        }
        this.network = IrcNetwork() {
            name = host,
            username = "quirky",
            gecos = "Quirky User",
            nick1 = "quirkyuser",
            nick2 = "quirkyuser_",
            nick3 = "quirkyuser__",
            servers = new IrcServer[] {
                IrcServer() {
                    hostname = host,
                    ssl = ssl,
                    port = port
                }
            }
        };
        connectbtn.set_sensitive(true);
    }

    public NetworkListView()
    {
        Object(orientation: Gtk.Orientation.VERTICAL);
        get_style_context().add_class("view");
        get_style_context().add_class("content-view");

        networks = new HashTable<string,IrcNetwork?>(str_hash, str_equal);

        var grid = new Gtk.Grid();
        grid.halign = Gtk.Align.CENTER;
        grid.valign = Gtk.Align.CENTER;
        pack_start(grid, true, true, 0);
        
        grid.set_column_spacing(10);
        grid.set_row_spacing(10);

        grid.margin_left = 50;
        grid.margin_right = 50;

        var row = 0;
        var label = new Gtk.Label("<span size='xx-large'>Connect to IRC</span>");
        label.margin_bottom = 20;
        label.use_markup = true;
        grid.attach(label, 0, row, 3, 1);

        ++row;
        label = new Gtk.Label("Network");
        label.halign = Gtk.Align.END;
        grid.attach(label, 0, row, 1, 1);

        combo = new Gtk.ComboBoxText.with_entry();
        var ent = combo.get_child() as Gtk.Entry;
        ent.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "dialog-information-symbolic");
        ent.set_icon_tooltip_markup(Gtk.EntryIconPosition.PRIMARY, "Specify a port after a hostname by separating with a \":\"\nUse a \"+\" symbol before the port to indicate SSL is required");
        combo.hexpand = true;
        grid.attach(combo, 1, row, 2, 1);

        editbtn = new Gtk.Button.from_icon_name("edit-symbolic", Gtk.IconSize.MENU);
        editbtn.set_relief(Gtk.ReliefStyle.NONE);
        grid.attach(editbtn, 3, row, 1, 1);

        ++row;

        label = new Gtk.Label("Channels");
        label.halign = Gtk.Align.END;
        grid.attach(label, 0, row, 1, 1);
        var entry = new Gtk.Entry();
        channels = entry;
        grid.attach(entry, 1, row, 2, 1);
        entry.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "dialog-information-symbolic");
        var lbl = """Enter a list of channels you wish to autojoin""";/*
If you wish to type a password for a channel,
use a colon to separate the channel name:

#somechannel:secret #someotherchannel""";*/
        entry.set_icon_tooltip_markup(Gtk.EntryIconPosition.PRIMARY, lbl);
        ++row;
        ++row;


        var btn = new Gtk.Button.with_label("Cancel");
        btn.clicked.connect(()=> {
            this.closed();
        });
        btn.margin_right = 4;

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        box.hexpand = false;
        box.halign = Gtk.Align.END;
        box.pack_start(btn, false, false, 0);
        grid.attach(box, 2, row, 1, 1);

        connectbtn = new Gtk.Button.with_label("Connect");

        connectbtn.get_style_context().add_class("suggested-action");
        connectbtn.set_sensitive(false);
        box.pack_start(connectbtn, false, false, 0);
        connectbtn.clicked.connect(()=> {
            this.activated(this.network, this.channels.text.split(" "));
        });

        combo.changed.connect(on_changed);

        editbtn.set_sensitive(false);
        editbtn.clicked.connect(()=> {
            this.edit(this.network);
        });
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
