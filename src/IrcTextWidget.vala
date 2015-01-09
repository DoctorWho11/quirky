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

struct TmpIter {
    int start;
    int end;
    string tag;
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

    public IrcTextWidget(HashTable<string,string> colors)
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

        mcols = new HashTable<int,string>(direct_hash, direct_equal);
        for (int i = 0; i < 99; i++) {
            var color = colors.lookup(@"color_$(i)");
            if (color == null) {
                color = "black";
            }
            if (tags.lookup("m_" + color) == null) {
                tag = new Gtk.TextTag("m_" + color);
                tag.foreground = color;
                tags.add(tag);
                tag = new Gtk.TextTag("mb_" + color);
                tag.background = color;
                tags.add(tag);
            }
            mcols[i] = color;
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
        int nick_index = (int) (whom.hash() % 15);
        if (nick_index < 2) {
            nick_index = 2;
        }

        return nick_index;
    }

    public void add_message(Gtk.TextBuffer buf, string? whom, string format, ...)
    {
        va_list va = va_list();
        string[] lines = {};

        insert_timestamp(buf);

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
            StringBuilder b = new StringBuilder();
            TmpIter[] iters = {};

            int tindex = message.index_of("\t");
            if (tindex > 0) {
                var left = message.substring(0,tindex);
                update_tabs(buf, demirc(left));
            } else {
                update_tabs(buf, "    ");
            }

            /* Handle colours later.. */
            bool bold  = false;
            bool underline = false;
            bool italic = false;

            TmpIter b_tmp = TmpIter();
            TmpIter i_tmp = TmpIter();
            TmpIter u_tmp = TmpIter();
            TmpIter c_tmpb = TmpIter();
            TmpIter c_tmpf = TmpIter();

            for (int i = 0, r=0; i < message.char_count(); i++) {
                unichar c = message.get_char(message.index_of_nth_char(i));
                switch (c) {
                    case MCS.BOLD:
                        if (!bold) {
                            b_tmp = TmpIter();
                            b_tmp.tag = "mbold";
                            b_tmp.start = r;
                        } else {
                            b_tmp.end = r;
                            iters += b_tmp;
                        }
                        bold = !bold;
                        break;
                    case MCS.RESET:
                        if (underline) {
                            u_tmp.end = r;
                            underline = false;
                            iters += u_tmp;
                        }
                        if (bold) {
                            b_tmp.end = r;
                            bold = false;
                            iters += b_tmp;
                        }
                        if (italic) {
                            i_tmp.end = r;
                            italic = false;
                            iters += i_tmp;
                        }
                        if (c_tmpf.tag != null) {
                            c_tmpf.end = r;
                            iters += c_tmpf;
                            c_tmpf.tag = null;
                        }
                        if (c_tmpb.tag != null) {
                            c_tmpb.end = r;
                            iters += c_tmpb;
                            c_tmpb.tag = null;
                        }
                        break;
                    case MCS.UNDERLINE:
                        if (!underline) {
                            u_tmp = TmpIter();
                            u_tmp.tag = "munderline";
                            u_tmp.start = r;
                        } else {
                            u_tmp.end = r;
                            iters += u_tmp;
                        }
                        underline = !underline;
                        break;
                    case MCS.ITALIC:
                        if (!italic) {
                            i_tmp = TmpIter();
                            i_tmp.tag = "mitalic";
                            i_tmp.start = r;
                        } else {
                            i_tmp.end = r;
                            iters += i_tmp;
                        }
                        italic = !italic;
                        break;
                    case MCS.COLOR:
                        StringBuilder tbuf = new StringBuilder();
                        int k = i;
                        bool comma = false;
                        int lside = 0;
                        int rside = 0;
                        if (k+1 < message.char_count()) {
                            for (k = i+1; k < message.char_count(); k++) {
                                c = message.get_char(message.index_of_nth_char(k));
                                if (c.isdigit()) {
                                    if (!comma) {
                                        lside++;
                                    } else {
                                        rside++;
                                    }
                                } else if (c == ',') {
                                    if (k+1 < message.char_count() && !message.get_char(message.index_of_nth_char(k+1)).isdigit()) {
                                        k--;
                                        break;
                                    }
                                    comma = true;
                                } else {
                                    k--;
                                    break;
                                }
                                if (!comma && lside > 2) {
                                    k--;
                                    break;
                                } else if (comma && rside > 2) {
                                    k--;
                                    break;
                                }
                                tbuf.append_unichar(c);
                            }
                            i = k;
                        }
                        if (tbuf.str.strip().length == 0) {
                            /* color reset.. */
                            if (c_tmpb.tag != null) {
                                c_tmpb.end = r;
                                iters += c_tmpb;
                                c_tmpb.tag = null;
                            }
                            if (c_tmpf.tag != null) {
                                c_tmpf.end = r;
                                iters += c_tmpf;
                                c_tmpf.tag = null;
                            }
                            break;
                        }
                        int fg_index = -1;
                        int bg_index = -1;
                        if ("," in tbuf.str) {
                            var split = tbuf.str.split(",");
                            fg_index = int.parse(split[0]);
                            bg_index = int.parse(split[1]);
                        } else {
                            fg_index = int.parse(tbuf.str);
                        }

                        if (fg_index == 30) {
                            fg_index = get_nick_color(whom);
                        }
                        if (fg_index > 0) {
                            fg_index = fg_index % (int)mcols.size();
                        }
                        if (bg_index > 0) {
                            bg_index = bg_index % (int)mcols.size();
                        }
                        /* Got old colour ? */
                        if (c_tmpf.tag != null) {
                            c_tmpf.end = r;
                            /* same colour again = reset */
                            iters += c_tmpf;
                            if (c_tmpf.tag == "m_" + mcols[fg_index]) {
                                c_tmpf.tag = null;
                                break;
                            }
                            c_tmpf.tag = null;
                        }
                        if (c_tmpb.tag != null) {
                            c_tmpb.end = r;
                            /* same colour again = reset */
                            iters += c_tmpb;
                            if (c_tmpb.tag == "mb_" + mcols[fg_index]) {
                                c_tmpb.tag = null;
                                break;
                            }
                            c_tmpb.tag = null;
                        }


                        if (fg_index >= 0) {
                            c_tmpf.start = r;
                            c_tmpf.tag = "m_" + mcols[fg_index % (int)mcols.size()];
                        }
                        if (bg_index >= 0) {
                            c_tmpb.start = r;
                            c_tmpb.tag = "mb_" + mcols[bg_index % (int)mcols.size()];
                        }
                        break;
                    default:
                        ++r;
                        b.append_unichar(c);
                        break;
                }
            }
            /* claim unfinished iters */
            if (bold) {
                iters += b_tmp;
            }
            if (italic) {
                iters += i_tmp;
            }
            if (underline) {
                iters += u_tmp;
            }
            if (c_tmpf.tag != null) {
                iters += c_tmpf;
            }
            if (c_tmpb.tag != null) {
                iters += c_tmpb;
            }
            Gtk.TextIter it;
            Gtk.TextIter et;
            buf.get_end_iter(out it);
            int start = it.get_offset();

            buf.insert_with_tags_by_name(it, b.str, -1, "default");
            buf.get_end_iter(out it);
            int end = it.get_offset();

            foreach (var iter in iters) {
                buf.get_iter_at_offset(out it, start+iter.start);
                buf.get_iter_at_offset(out et, iter.end <= iter.start ? end : start+iter.end);
                buf.apply_tag_by_name(iter.tag, it, et);
            }

            iters = null;
            buf.get_end_iter(out it);
            buf.insert_with_tags_by_name(it, "\n", -1, "default");
  
            /* Process URLs (string sanitised by prior mirc run. */
            var urls = get_urls(b.str);
            if (urls.length > 0) {
                foreach (var url in urls) {
                    Gtk.TextIter s;
                    Gtk.TextIter e;
                    buf.get_iter_at_offset(out s, start+url.start);
                    buf.get_iter_at_offset(out e, start+url.start+url.url.length);
                    var tag = buf.create_tag(null);
                    tag.set_data("_uri", url.url);
                    buf.apply_tag_by_name("url", s, e);
                    buf.apply_tag(tag, s, e);
                }
            }

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

    private string demirc(string input)
    {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < input.char_count(); i++) {
            unichar c = input.get_char(input.index_of_nth_char(i));
            switch (c) {
                case MCS.BOLD:
                case MCS.ITALIC:
                case MCS.UNDERLINE:
                case MCS.REVERSE:
                case MCS.RESET:
                    break;
                case MCS.COLOR:
                    int j;
                    bool comma = false;
                    int lside = 0;
                    int rside = 0;
                    for (j = i+1; j < input.char_count(); j++) {
                        c = input.get_char(input.index_of_nth_char(j));
                        if (c.isdigit()) {
                            if (!comma) {
                                lside++;
                            } else {
                                rside++;
                            }
                        } else if (c == ',') {
                            if (j+1 < input.char_count() && !input.get_char(input.index_of_nth_char(j+1)).isdigit()) {
                                j--;
                                break;
                            }
                            comma = true;
                        } else {
                            j--;
                            break;
                        }
                        if (!comma && lside > 2) {
                            j--;
                            break;
                        } else if (comma && rside > 2) {
                            j--;
                            break;
                        }
                    }
                    i = j;
                    break;
                default:
                    b.append_unichar(c);
                    break;
            }
        }
        return b.str;
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

        for (int i = 0; i < fmt.char_count(); i++) {
            var c = fmt.get_char(fmt.index_of_nth_char(i));
            switch (c) {
                case '$':
                    /* Indexed argument follows.. */
                    assert(i+1 <= fmt.char_count());
                    unichar j = fmt.get_char(fmt.index_of_nth_char(i+1));
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
                    assert(i+1 <= fmt.char_count());
                    unichar j = fmt.get_char(fmt.index_of_nth_char(i+1));
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
