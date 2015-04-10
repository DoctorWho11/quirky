/*
 * IrcTextEntry.vala
 * 
 * Copyright 2015 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/**
 * Used as a simple command/message buffer for the text entry, enabling
 * UP/DOwWN keyboard navigation through the history.
 */
public class IrcEntryLog : Object
{

    public int cmd_index;
    public Queue<string> items;
    public string? save_text = null;
    int size_limit;
    public int position;
    public string text;

    /**
     * Construct a new IrcEntryLog
     */
    public IrcEntryLog(int size_limit = 25)
    {
        this.size_limit = size_limit;
        cmd_index = -1;
        items = new Queue<string>();
        text = "";
        position = 0;
    }

    /**
     * IrcTextEntry will automatically call this.
     */
    public void add_log(string command)
    {
        items.push_head(command);
        if (items.length == this.size_limit) {
            items.pop_tail();
        }
    }
}

public delegate string[]? IrcEntryCompleteFunc(string cmd, string line);

/**
 * Custom Entry enabling input of special control chars, command buffer history
 * and tab completion.
 */
public class IrcTextEntry : Gtk.Entry
{
    private weak IrcEntryLog? log;

    int cycle_index = 0;
    string[] current_completions = {};
    string cycle_prefix;
    string cycle_suffix;
    bool cycling = false;

    weak IrcEntryCompleteFunc func;

    public IrcTextEntry()
    {
        log = null;
        /* We do the logging. */
        activate.connect(()=> {
            if (get_text().strip().length > 0) {
                if (log != null) {
                    log.add_log(get_text());
                }
            }
        });
    }

    public void set_completion_func(IrcEntryCompleteFunc func)
    {
        this.func = func;
    }

    public void set_log(IrcEntryLog? log) {
        /* Sync up. */
        if (this.log != null) {
            this.log.text = get_text();
            this.log.position = get_position();
        }
        this.log = log;
        set_text(log.text);
        set_position(log.position);
        cycle_index = 0;
        cycling = false;
    }

    public override bool key_press_event(Gdk.EventKey event)
    {
        unichar to_append = ' ';
        bool replace = true;

        string name = Gdk.keyval_name(event.keyval);
        if (log != null && log.save_text == null) {
            log.save_text = get_text();
        }

        /* Handle mirc colours first */
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
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

        bool log_switch = false;
        switch (name) {
            case "Up":
                if (log == null) {
                    break;
                }
                log_switch = true;
                string? item = log.items.peek_nth(++log.cmd_index);
                if (item == null) {
                    log.cmd_index = (int)log.items.length;
                    break;
                }
                set_text(item);
                break;
            case "Down":
                if (log == null) {
                    break;
                }
                log_switch = true;
                string? item = log.items.peek_nth(--log.cmd_index);
                if (item == null) {
                    log.cmd_index = -1;
                    /* back to you me old mate. */
                    set_text(log.save_text);
                    break;
                }
                set_text(item);
                break;
            case "Tab":
                if (cycling) {
                    string ntext = cycle_prefix + current_completions[cycle_index%current_completions.length];
                    int len = ntext.length;
                    ntext += " " + cycle_suffix;
                    set_text(ntext);
                    set_position(len+1);
                    cycle_index += 1;
                    return Gdk.EVENT_STOP;
                }

                int pos = get_position();
                string txt = get_text();
                string? cmd = null;
                bool spaced = false;
                int i;
                for (i = pos-1; i > 0; i--) {
                    unichar c = txt.get_char(txt.index_of_nth_char(i));
                    if (c == ' ') {
                        cmd = txt.substring(txt.length-(txt.length-i), pos-i);
                        spaced = true;
                        ++i;
                        break;
                    }
                }
                if (!spaced) {
                    /* Likely back to start */
                    i = 0;
                    cmd = txt.substring(0, pos);
                }
                cmd = cmd.strip();

                if (cmd.length == 0) {
                    return Gdk.EVENT_STOP;
                }

                if (this.func == null) {
                    return Gdk.EVENT_STOP;
                }
                var c = this.func(cmd,get_text());

                if (c.length == 1) {
                    string txtt = txt.substring(0,txt.length-(txt.length-i));
                    txtt += c[0];
                    int len = txtt.length;
                    string remnant = pos < txt.length ? txt.substring(pos, txt.length-pos) : "";
                    txtt += " " + remnant;
                    if (remnant.length == 0) {
                        len += 1;
                    }
                    set_text(txtt);
                    set_position(len);
                } else if (c.length > 1) {
                    cycle_prefix = txt.substring(0,txt.length-(txt.length-i));
                    current_completions = c;
                    string txtt = cycle_prefix + current_completions[cycle_index%current_completions.length] + " ";
                    int len = txtt.length;
                    cycle_suffix = pos < txt.length ? txt.substring(pos, txt.length-pos) : "";
                    txtt += " " + cycle_suffix;
                    set_text(txtt);
                    set_position(len+1);
                    current_completions = c;
                    cycling = true;
                    cycle_index += 1;
                }
                return Gdk.EVENT_STOP;
            default:
                if (log != null) {
                    log.cmd_index = -1;
                    log.save_text = null;
                }
                cycling = false;
                cycle_index = 0;
                break;
        }
        if (log != null) {
            log.cmd_index = log.cmd_index.clamp(-1, (int)log.items.length-1);
        }
        if (log_switch) {
            return Gdk.EVENT_STOP;
        }
        return base.key_press_event(event);
    }
}
