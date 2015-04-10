/*
 * CountItem.vala
 * 
 * Copyright 2015 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/**
 * Determines how this is to be rendered
 */
public enum CountPriority {
    HIGH,
    NORMAL,
    LOW
}

/**
 * Simplistic count badge
 */
public class CountItem : Gtk.EventBox
{
    private CountPriority _p;

    /**
     * Priority for this CountItem. Determines how this is rendered
     */
    public CountPriority priority {
        public set {
            string[] removals = {};
            string[] adds = {};

            switch (value) {
                case CountPriority.HIGH:
                    adds += "urgent";
                    removals += "non-urgent";
                    break;
                case CountPriority.NORMAL:
                    removals += "non-urgent";
                    removals += "urgent";
                    break;
                case CountPriority.LOW:
                    this.get_style_context().add_class("non-urgent");
                    adds += "non-urgent";
                    removals += "urgent";
                    break;
            }
            foreach (var c in removals) {
                get_style_context().remove_class(c);
            }
            foreach (var c in adds) {
                get_style_context().add_class(c);
            }
            this._p = value;
        }
        public get {
            return this._p;
        }
    }

    private Gtk.Label? label;

    private int _count = 0;

    /**
     * The count to display. 0 or below will hide the count, whereas anything
     * over 9 will show "9+"
     */
    public int count {
        public set {
            this._count = value;
            if (value <= 0) {
                label.hide();
            } else {
                label.show();
            }
            if (value > 9) {
                label.set_markup("9+");
            } else {
                label.set_markup("%d".printf(value));
            }
            queue_draw();
        }
        public get {
            return this._count;
        }
    }

    public override bool draw(Cairo.Context cr)
    {
        if (count > 0) {
            var st = get_style_context();
            Gtk.Allocation alloc;
            get_allocation(out alloc);
            st.render_background(cr, alloc.x, alloc.y, alloc.width, alloc.height);
            st.render_frame(cr, alloc.x, alloc.y, alloc.width, alloc.height);
            return base.draw(cr);
        }
        return Gdk.EVENT_STOP;
    }

    /**
     * Construct a new CountItem
     */
    public CountItem()
    {
        label = new Gtk.Label("");
        label.set_use_markup(true);
        add(label);

        get_style_context().add_class("count-item");

        show_all();
        set_no_show_all(true);
        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;
        label.halign = Gtk.Align.CENTER;
        label.valign = Gtk.Align.CENTER;

        this.priority = CountPriority.NORMAL;
        this.count = 0;

        margin = 3;
    }

    public override void get_preferred_width(out int min, out int nat)
    {
        min = 20;
        nat = 20;
    }
    public override void get_preferred_height(out int min, out int nat)
    {
        min = 18;
        nat = 18;
    }
}
