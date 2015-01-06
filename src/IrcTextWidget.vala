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
    weak Gtk.TextTag? last_uri = null;

    public Gtk.TextTagTable tags { public get; private set; }
    private Gdk.Cursor _link;

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

    /**
     * Let us click URIs
     */
    public override bool button_press_event(Gdk.EventButton evt)
    {
        int bx;
        int by;

        if (evt.button != 1 || buffer == null) {
            return base.button_press_event(evt);
        }

        Gtk.TextIter iter;
        window_to_buffer_coords(Gtk.TextWindowType.TEXT, (int)evt.x, (int)evt.y, out bx, out by);
        get_iter_at_location(out iter, bx, by);
        foreach (var tag in iter.get_tags()) {
            string uri = tag.get_data("_uri");
            if (uri != null) {
                try {
                    AppInfo.launch_default_for_uri(uri, null);
                } catch (Error e) {
                    warning("Unable to launch URI: %s", e.message);
                }
                break;
            }
        }
        return base.button_press_event(evt);
    }

    /**
     * All this just lets us give a link effect for known URIs.
     */
    public override bool motion_notify_event(Gdk.EventMotion evt)
    {
        int bx;
        int by;

        if (buffer == null) {
            return base.motion_notify_event(evt);
        }
        Gtk.TextIter iter;
        weak Gtk.TextTag? wtag = null;
        window_to_buffer_coords(Gtk.TextWindowType.TEXT, (int)evt.x, (int)evt.y, out bx, out by);
        get_iter_at_location(out iter, bx, by);
        bool g = false;
        foreach (var tag in iter.get_tags()) {
            string uri = tag.get_data("_uri");
            if (uri != null) {
                tag.underline = Pango.Underline.SINGLE;
                wtag = tag;
                g = true;
                break;
            }
        }
        if (last_uri != null && last_uri != wtag) {
            last_uri.underline = tags.lookup("default").underline;
            last_uri = null;
        }
        var win = get_window(Gtk.TextWindowType.TEXT);
        if (!g) {
            if (win.get_cursor() != null) {
                win.set_cursor(null);
            }
        } else {
            win.set_cursor(_link);
            last_uri = wtag;
        }
        return base.motion_notify_event(evt);
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

        _link = new Gdk.Cursor(Gdk.CursorType.HAND1);

        tags = new Gtk.TextTagTable();
        var tag = new Gtk.TextTag("default");
        tag.font_desc = Pango.FontDescription.from_string("Monospace 10");
        custom_font = true;
        tags.add(tag);

        tag = new Gtk.TextTag("nickname");
        tags.add(tag);
        tag = new Gtk.TextTag("nickchange");
        tags.add(tag);

        tag = new Gtk.TextTag("action");
        tags.add(tag);

        /* currently we just underline the links on hover. */
        tag = new Gtk.TextTag("url");
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

    /**
     * Currently unused
     */
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

    void insert_timestamp(Gtk.TextBuffer buf)
    {
        Gtk.TextIter i;
        buf.get_end_iter(out i);
        var time = new DateTime.now_local();
        var stamp = time.format("[%H:%M:%S] ");
        if (stamp.length > timestamp_length) {
            timestamp_length = stamp.length;
        }

        buf.insert_with_tags_by_name(i, stamp, -1, "timestamp", "default");
    }

    int get_nick_color(string whom)
    {
        /* Don't ever use white/black */
        int nick_index = (int) (whom.hash() % mcols.size());
        if (nick_index < 2) {
            nick_index = 2;
        }

        return nick_index;
    }

    /**
     * Helpers.
     */
    public void add_error(Gtk.TextBuffer buf, string fmt, ...)
    {
        va_list va = va_list();
        add_message(buf, null, MSG.ERROR, fmt.vprintf(va));
    }
    public void add_info(Gtk.TextBuffer buf, string fmt, ...)
    {
        va_list va = va_list();
        add_message(buf, null, MSG.INFO, fmt.vprintf(va));
    }

    public void add_message(Gtk.TextBuffer buf, string? whom, string format, ...)
    {
        va_list va = va_list();
        string last_nick = buf.get_data("_lastnick");
        string[] lines = {};

        Gtk.TextIter i;
        buf.get_end_iter(out i);
        insert_timestamp(buf);

        if (whom == null) {
            whom = "    ";
        }

        /**
         * TODO: Think about re-adding this.
         */
        /*if (last_nick != whom) {
            if (ttype != IrcTextType.MOTD && ttype != IrcTextType.SERVER && ttype != IrcTextType.ERROR && ttype != IrcTextType.INFO) {
                buf.insert_with_tags_by_name(i, " ", -1, "spacing", "default");
                buf.get_end_iter(out i);
            }
        }*/


        lines = _print_formatted(format, va);

        foreach (var message in lines) {
            buf.get_end_iter(out i);
            int msg_start = i.get_offset();

            /* Manual handling of string.. */
            bool bolding = false;
            bool italic = false;
            bool underline = false;

            List<string> styles = new List<string>();
            styles.append("default");

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
                        styles.append("default");
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
                        if (fg_index == 30) {
                            fg_index = get_nick_color(whom);
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
  
            /* Process URLs */
            var urls = get_urls(message);
            if (urls.length > 0) {
                foreach (var url in urls) {
                    Gtk.TextIter s;
                    Gtk.TextIter e;
                    buf.get_iter_at_offset(out s, msg_start+url.start);
                    buf.get_iter_at_offset(out e, msg_start+url.start+url.url.length);
                    var tag = buf.create_tag(null);
                    tag.set_data("_uri", url.url);
                    buf.apply_tag_by_name("url", s, e);
                    buf.apply_tag(tag, s, e);
                }
            }
            buf.set_data("_lastnick", whom);
            update_tabs(buf, whom);

            scroll_to_bottom(buffer);
        }
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

    /**
     * Inspiration comes from polari, who in turn used this regex:
     * http://daringfireball.net/2010/07/improved_regex_for_matching_urls
     */
    private UrlMatch[] get_urls(string input)
    {
        string s = """(?i)\b((?:[a-z][\w-]+:(?:/{1,3}|[a-z0-9%])|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))""";
        UrlMatch[] ret = {};

        try {
            var r = new Regex(s);

            MatchInfo inf;
            r.match(input, 0, out inf);
            while (inf.matches()) {
                var wat = inf.fetch(0);
                int offset;
                int end;
                inf.fetch_pos(0, out offset, out end);
                var o = UrlMatch() {
                    url = wat,
                    start = offset,
                    end = end
                };
                ret += o;
                inf.next();
            }
        } catch (Error e) {} 
        return ret;
    }

    /**
     * The notation we're supporting here is pretty much what you see in
     * xchat's pevents configuration file.
     * This enables us to handle various messages much more easily, such as:
     *
     * $t* $1 has joined $2
     *
     * Index parameters are replaced from the va_list indexes, and certain special
     * control characters exist:
     *
     * $t = \t
     * $n = \n (we split ourselves
     * $$ = escaped dollar sign
     * %C = mirc colour (%C03 or $C03,45, for example)
     * %O = (O not ZERO) reset formatting
     * %B = bold
     * %I = italic
     * %U = underline
     *
     * @note These match with existing conventions, such as the mirc keyboard
     * shortcuts we have also mapped that enter these characters (CTRL+K being
     * the clear exception, in order to assist in those porting old xchat themes
     * in the future)
     */
    string[] _print_formatted(string fmt, va_list va)
    {
        StringBuilder b = new StringBuilder();

        string[] opts = {};
        string? nxt = null;
        while ((nxt = va.arg<string>()) != null) {
            opts += nxt;
        }

        string[] ret = {};

        for (int i = 0; i < fmt.length; i++) {
            var c = fmt.get_char(i);
            switch (c) {
                case '$':
                    /* Indexed argument follows.. */
                    assert(i+1 <= fmt.length);
                    unichar j = fmt.get_char(i+1);
                    i++;
                    if (j.isdigit()) {
                        int index = int.parse(j.to_string());
                        if (index < 0 || index > opts.length) {
                            warning("Format string requested invalid index %d: %s", index, fmt);
                            b.append("null");
                            break;
                        }
                        string replace = opts[index-1];
                        b.append(replace);
                    } else if (j == '$') {
                        b.append("$");
                    } else if (j == 't') {
                        b.append("\t");
                    } else if (j == 'n') {
                        /* newline.. */
                        ret += b.str;
                        b.truncate(0);
                    } else {
                        warning("Invalid $notation: %s, skipping..", j.to_string());
                    }
                    break;
                case '%':
                    /* colours */
                    assert(i+1 <= fmt.length);
                    unichar j = fmt.get_char(i+1);
                    if (j == '%') {
                        b.append_unichar(j);
                        i++;
                        break;
                    }
                    if (j == 'C') {
                        b.append_unichar(MCS.COLOR);
                    } else if (j == 'B') {
                        /* bold */
                        b.append_unichar(MCS.BOLD);
                    } else if (j == 'I') {
                        /* italic */
                        b.append_unichar(MCS.ITALIC);
                    } else if (j == 'U') {
                        /* underline */
                        b.append_unichar(MCS.UNDERLINE);
                    } else if (j == 'O') {
                        /* reset */
                        b.append_unichar(MCS.RESET);
                    }
                    i++;
                    break;
                default:
                    b.append_unichar(c);
                    break;
            }
        }
        if (b.len > 0) {
            ret += b.str;
        }
        return ret;
    }
}

protected struct UrlMatch
{
    string url;
    int start;
    int end;
}
