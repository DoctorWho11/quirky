/*
 * Dialogs.vala
 * 
 * Copyright 2015 Ikey Doherty <ikey@evolve-os.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

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
            channel = channel_entry.text;
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
