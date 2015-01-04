/*
 * IrcTextWidget.vala
 * 
 * Copyright 2015 Ikey Doherty <ikey@evolve-os.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/**
 * Constants for mirc colours
 */
public class MCS {
    public static const unichar BOLD = '\x02';
    public static const unichar COLOR = '\x03';
    public static const unichar ITALIC = '\x1D';
    public static const unichar UNDERLINE = '\x1F';
    public static const unichar REVERSE = '\x16';
    public static const unichar RESET = '\x0F';
}

/**
 * Enable special rendering of certain message types
 */
public enum IrcTextType {
    MESSAGE,
    ACTION,
    JOIN,
    PART,
    MOTD,
    SERVER
}

/**
 * Custom Entry enabling input of special control chars..
 */
public class IrcTextEntry : Gtk.Entry
{
    public override bool key_press_event(Gdk.EventKey event)
    {
        unichar to_append = ' ';
        bool replace = true;

        if (event.state == Gdk.ModifierType.CONTROL_MASK) {
            switch (event.keyval) {
                case Gdk.Key.K:
                case Gdk.Key.k:
                    to_append = MCS.COLOR;
                    break;
                case Gdk.Key.B:
                case Gdk.Key.b:
                    to_append = MCS.BOLD;
                    break;
                case Gdk.Key.I:
                case Gdk.Key.i:
                    to_append = MCS.ITALIC;
                    break;
                case Gdk.Key.U:
                case Gdk.Key.u:
                    to_append = MCS.UNDERLINE;
                    break;
                case Gdk.Key.O:
                case Gdk.Key.o:
                    to_append = MCS.RESET;
                    break;
                default:
                    replace = false;
                    break;
            }
        } else {
            replace = false;
        }
        if (replace) {
            this.insert_at_cursor(to_append.to_string());
            return Gdk.EVENT_STOP;
        }
        return base.key_press_event(event);
    }
}
/**
 * Fancier TextView suitable for usage in our main IRC client
 */
public class IrcTextWidget : Gtk.TextView
{
    HashTable<int,string> mcols;

    public Gtk.TextTagTable tags { public get; private set; }

    public bool use_timestamp {
        public set {
            tags.lookup("timestamp").invisible = !value;
            string? lnick = null;
            if (get_buffer() != null) {
                lnick = get_buffer().get_data("longestnick");
            }
            update_tabs(get_buffer(), lnick, true);
        }
        public get {
            return !(tags.lookup("timestamp").invisible);
        }
    }

    private bool _visible_margin;
    public bool visible_margin {
        public set {
            _visible_margin = value;
            queue_draw();
        }
        public get {
            return _visible_margin;
        }
    }

    private int margin_offset = -1;

    private int timestamp_length = 0;

    private int max(int a, int b)
    {
        if (a > b) {
            return a;
        }
        return b;
    }

    public override bool draw(Cairo.Context cr)
    {
        Gtk.Allocation alloc;
        get_allocation(out alloc);
        base.draw(cr);

        if (_visible_margin && margin_offset > 0 && get_buffer() != null) {
            cr.rectangle(margin_offset, 0, 1, alloc.height);
            /* TODO: Make customisable */
            cr.set_source_rgba(0.6, 0.6, 0.6, 0.5);
            cr.fill();
        }

        return Gdk.EVENT_PROPAGATE;
    }

    public override void get_preferred_width(out int n, out int w)
    {
        n = 1;
        w = 1;
    }

    bool custom_font = false;

    public IrcTextWidget()
    {
        set_wrap_mode(Gtk.WrapMode.WORD_CHAR);
        set_cursor_visible(false);
        set_editable(false);

        visible_margin = true;

        tags = new Gtk.TextTagTable();
        var tag = new Gtk.TextTag("default");
        tag.font_desc = Pango.FontDescription.from_string("Monospace 10");
        custom_font = true;
        tags.add(tag);

        tag = new Gtk.TextTag("nickname");
        tags.add(tag);

        tag = new Gtk.TextTag("action");
        tags.add(tag);

        tag = new Gtk.TextTag("spacing");
        tag.pixels_above_lines = 8;
        tag.invisible = true;
        tags.add(tag);

        tag = new Gtk.TextTag("timestamp");
        tag.foreground = "darkgrey";
        tag.invisible = true;
        tags.add(tag);

        /* default colors palette (m0-15) */
        string[,] palette = {
            { "white", "white" },
            { "black", "black" },
            { "blue", "blue" },
            { "green", "green" },
            { "red", "red" },
            { "brown", "brown" },
            { "purple", "purple" },
            { "orange", "orange" },
            { "yellow", "yellow" },
            { "lightgreen", "lightgreen" },
            { "teal", "teal" },
            { "cyan", "cyan" },
            { "lightblue", "lightblue" },
            { "pink", "pink" },
            { "grey", "grey" },
            { "lightgrey", "lightgrey" }
        };

        mcols = new HashTable<int,string>(direct_hash, direct_equal);
        for (int i = 0; i < palette.length[0]; i++) {
            tag = new Gtk.TextTag("m_" + palette[i,0]);
            tag.foreground = palette[i,1];
            tags.add(tag);
            tag = new Gtk.TextTag("mb_" + palette[i,0]);
            tag.background = palette[i,1];
            tags.add(tag);
            mcols[i] = palette[i,0];
        }

        tag = new Gtk.TextTag("mbold");
        tag.weight = Pango.Weight.BOLD;
        tags.add(tag);

        tag = new Gtk.TextTag("mitalic");
        tag.style = Pango.Style.ITALIC;
        tags.add(tag);

        tag = new Gtk.TextTag("munderline");
        tag.underline = Pango.Underline.SINGLE;
        tags.add(tag);

        left_margin = 6;
        right_margin = 6;
    }

    private bool mirc_color(string s)
    {
        unichar[] known = { '\x02', '\x03', '\x1D', '\x1F', '\x16', '\x0F' };
        foreach (var cha in known) {
            if (s.index_of_char(cha) != -1) {
                return true;
            }
        }
        return false;
    }

    public void add_message(Gtk.TextBuffer buf, string whom, string message, IrcTextType ttype)
    {
        /* Don't ever use white/black */
        int nick_index = (int) (whom.hash() % mcols.size());
        if (nick_index < 2) {
            nick_index = 2;
        }

        string last_nick = buf.get_data("_lastnick");

        string[] default_tags = { "default" };
        switch (ttype) {
            case IrcTextType.ACTION:
                default_tags += "action";
                break;
            case IrcTextType.MOTD:
                default_tags += "m_purple";
                break;
            case IrcTextType.JOIN:
                default_tags += "m_green";
                break;
            case IrcTextType.PART:
                default_tags += "m_red";
                break;
            case IrcTextType.SERVER:
                default_tags += "m_brown";
                break;
            default:
                break;
        }

        Gtk.TextIter i;
        buf.get_end_iter(out i);

        if (last_nick != whom) {
            if (ttype != IrcTextType.MOTD && ttype != IrcTextType.SERVER) {
                buf.insert_with_tags_by_name(i, " ", -1, "spacing", "default");
                buf.get_end_iter(out i);
            }
        }

        var time = new DateTime.now_local();
        var stamp = time.format("[%H:%M:%S] ");
        if (stamp.length > timestamp_length) {
            timestamp_length = stamp.length;
        }

        buf.insert_with_tags_by_name(i, stamp, -1, "timestamp", "default");
        buf.get_end_iter(out i);

        /* Custom formatting for certain message types.. */
        if (ttype == IrcTextType.MESSAGE) {
            if (last_nick != whom) {
                buf.insert_with_tags_by_name(i, whom + "\t", -1, "nickname", "m_" + mcols[nick_index], "default");
            } else {
                buf.insert_with_tags_by_name(i, "\t", -1, "default");
            }
        } else if (ttype == IrcTextType.ACTION) {
            buf.insert_with_tags_by_name(i, @"\t* $(whom) ", -1, "nickname", "m_" + mcols[nick_index], "action", "default");
        } else if (ttype == IrcTextType.JOIN || ttype == IrcTextType.PART) {
            buf.insert_with_tags_by_name(i, @"\t* ", -1, "default");
            if (whom != "") {
                buf.get_end_iter(out i);
                buf.insert_with_tags_by_name(i, @"$(whom) ", -1, "nickname", "m_" + mcols[nick_index], "default");
            }
        } else {
            //if (ttype != IrcTextType.SERVER && ttype != IrcTextType.MOTD) {
                /* Default, right align everything.. */
                buf.insert_with_tags_by_name(i, "\t", -1, "default");
            //}
        }
    
        buf.get_end_iter(out i);
        /* Begin processing mirc colours.. */
        if (mirc_color(message)) {
            /* Manual handling of string.. */
            bool bolding = false;
            bool italic = false;
            bool underline = false;

            List<string> styles = new List<string>();
            foreach (var s in default_tags) {
                styles.append(s);
            }

            for (int j=0; j < message.length; j++) {
                unichar c = message.get_char(j);
                bool skip = true;
                switch (c) {
                    case MCS.BOLD:
                        if (bolding) {
                            styles.remove(styles.find_custom("mbold", strcmp).data);
                        } else {
                            styles.append("mbold");
                        }
                        bolding = !bolding;
                        break;
                    case MCS.ITALIC:
                        if (italic) {
                            styles.remove(styles.find_custom("mitalic", strcmp).data);
                        } else {
                            styles.append("mitalic");
                        }
                        italic = !italic;
                        break;
                    case MCS.UNDERLINE:
                        if (underline) {
                            styles.remove(styles.find_custom("munderline", strcmp).data);
                        } else {
                            styles.append("munderline");
                        }
                        underline = !underline;
                        break;
                    case MCS.RESET:
                        bolding = false;
                        italic = false;
                        underline = false;
                        styles = new List<string>();
                        foreach (var s in default_tags) {
                            styles.append(s);
                        }
                        break;
                    case MCS.COLOR:
                        string tbuf = "";
                        int k = j;
                        int sk = j;
                        if (k+1 < message.length) {
                            for (k = j+1; k < message.length; k++) {
                                var ch = message.get_char(k);
                                if (ch == ',' || ch.isdigit()) {
                                    tbuf += ch.to_string();
                                } else {
                                    k -= 1;
                                    break;
                                }
                            }
                            j = k;
                        }
                        if (tbuf.length == 0) {
                            /* Ugly as shit but that's what happens when we you used linked lists.. */
                            var  blist = styles.copy();
                            foreach (var st in blist) {
                                if (st.has_prefix("m_") || st.has_prefix("mb_")) {
                                    styles.remove(st);
                                }
                            }
                            blist = null;
                            k = sk;
                            break;
                        }
                        int fg_index = -1;
                        int bg_index = -1;
                        if ("," in tbuf) {
                            var split = tbuf.split(",");
                            fg_index = int.parse(split[0]);
                            bg_index = int.parse(split[1]);
                        } else {
                            fg_index = int.parse(tbuf);
                        }
                        if (fg_index in mcols) {
                            styles.append("m_" + mcols[fg_index]);
                        }
                        if (bg_index in mcols) {
                            styles.append("mb_" + mcols[bg_index]);
                        }
                        break;
                    default:
                        /* Not arsed. */
                        skip = false;
                        break;
                }
                if (!skip) {
                    buf.get_end_iter(out i);
                    var offset = i.get_offset();
                    Gtk.TextIter s;
                    buf.insert(ref i, c.to_string(), 1);
                    buf.get_iter_at_offset(out s, offset);
                    foreach (var st in styles) {
                        buf.apply_tag_by_name(st, s, i);
                    }
                }
            }
            buf.get_end_iter(out i);
            buf.insert_with_tags_by_name(i, "\n", -1, "default");
        } else {
            buf.get_end_iter(out i);
            var offset = i.get_offset();
            Gtk.TextIter s;
            buf.insert(ref i, message, -1);
            buf.get_iter_at_offset(out s, offset);
            foreach (var st in default_tags) {
                buf.apply_tag_by_name(st, s, i);
            }
            buf.insert_with_tags_by_name(i, "\n", -1, "default");
        }
        if (ttype == IrcTextType.MESSAGE) {
            buf.set_data("_lastnick", whom);
        } else {
            buf.set_data("_lastnick", null);
        }
        update_tabs(buf, whom);

        scroll_to_bottom(buffer);
    }

    public void scroll_to_bottom(Gtk.TextBuffer? buffer)
    {
        /* Temp: Autoscroll when appending, need to check this later.. */
        if (buffer != get_buffer()) {
            return;
        }
        Gtk.TextIter i;

        /* fwiw we need to just keep one single mark. */
        buffer.get_end_iter(out i);
        var m = buffer.create_mark(null, i, true);
        scroll_mark_onscreen(m);
        buffer.delete_mark(m);
    }

    /**
     * Update tabstop to align nicks and text properly
     */
    public void update_tabs(Gtk.TextBuffer? buffer, string? nick, bool invalidate = false)
    {
        if (buffer == null) {
            return;
        }
        if (buffer != this.buffer) {
            return;
        }

        if (nick == null) {
            nick = " ";
        }
        string longest = buffer.get_data("longestnick");
        if (longest == null) {
            longest = nick;
        }

        if (longest.length > nick.length) {
            return;
        } else {
            buffer.set_data("longestnick", nick);
        }

        var twidth = nick.length + 2;

        if (use_timestamp) {
            twidth += timestamp_length + 1;
        }

        var ctx = get_pango_context();
        Pango.FontDescription? desc = custom_font ? tags.lookup("default").font_desc : null;
        var mtx = ctx.get_metrics(desc, null);
        var charwidth = max(mtx.get_approximate_char_width(), mtx.get_approximate_digit_width());
        var pxwidth = (int) Pango.units_to_double(charwidth);

        var tabs = new Pango.TabArray(1, true);
        tabs.set_tab(0, Pango.TabAlign.LEFT, twidth * (int)pxwidth);
        set_tabs(tabs);
        indent = -twidth * pxwidth; // indent wrapped lines
        margin_offset = (twidth * (int)pxwidth) - (pxwidth/2);
        if (use_timestamp) {
            margin_offset -= (pxwidth/2);
        }

        queue_draw();
    }
}
