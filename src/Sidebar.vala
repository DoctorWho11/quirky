/*
 * Widgets.vala
 * 
 * Copyright 2015 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/**
 * Much cheat. We force an offset size to enable things to come from under the overlay
 */
public class ReserveBox : Gtk.Bin
{
    public Gtk.Widget? targ;

    public ReserveBox(Gtk.Widget? targ)
    {
        this.targ = targ;
    }

    public override void get_preferred_width(out int min, out int nat)
    {
        int m;
        int n;
        targ.get_preferred_width(out m, out n);
        min = m;
        nat = n;
    }

    public override void get_preferred_height(out int min, out int nat)
    {
        int m;
        int n;
        targ.get_preferred_height(out m, out n);
        min = m;
        nat = n;
    }
}

/**
 * Sidebar items belong to a SidebarExpandable
 */
public class SidebarItem : Gtk.EventBox
{
    private Gtk.Image img;
    private Gtk.Label l;

    private bool _selected;

    public string label {
        public set {
            l.set_label(value);
        }
        public get {
            return l.get_text();
        }
    }

    public CountItem count { public get ; private set; }

    public string icon_name {
        public set {
            img.set_from_icon_name(value, Gtk.IconSize.BUTTON);
        }
        public owned get {
            return img.icon_name;
        }
    }
    public bool selected {
        public set {
            _selected = value;
            if (value) {
                activated();
            }
        }
        public get {
            return _selected;
        }
    }

    /**
     * "Usable" state, visually different for parted channels, etc.
     */
    private bool _usable;
    public bool usable {
        public set {
            if (value) {
                get_style_context().remove_class("dim-label");
            } else {
                get_style_context().add_class("dim-label");
            }
            _usable = usable;
        }
        public get {
            return _usable;
        }
        default = true;
    }

    public new signal void activated();

    public SidebarItem(string label, string icon)
    {
        get_style_context().add_class("sidebar-item");

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        add(box);

        _usable = true;
        usable = true;

        l = new Gtk.Label(label);
        l.halign = Gtk.Align.START;
        box.margin_left = 20;

        img = new Gtk.Image.from_icon_name(icon, Gtk.IconSize.BUTTON);
        box.pack_start(img, false, false, 0);
        img.margin = 5;
        box.pack_start(l, true, true, 0);

        count = new CountItem();
        box.pack_end(count, false, false, 0);

        show_all();
    }

    public override bool draw(Cairo.Context cr)
    {
        Gtk.Allocation alloc;
        get_allocation(out alloc);
        var st = get_style_context();
        if (_selected) {
            st.set_state(Gtk.StateFlags.SELECTED | get_state_flags());
        } else {
            st.set_state(get_state_flags());
        }
        st.render_background(cr, alloc.x, alloc.y, alloc.width, alloc.height);
        st.render_frame(cr, alloc.x, alloc.y, alloc.width, alloc.height);

        if (get_child() != null) {
            propagate_draw(get_child(), cr);
        }
        return false;
    }
}

/**
 * Root node in a Sidebar
 */
public class SidebarExpandable : Gtk.Box
{
    private Gtk.Label _label;
    private Gtk.Image _icon;
    private ReserveBox r;
    private Gtk.Button _expand;

    private Gtk.Revealer revealer;
    private Gtk.Box revealer_box;

    private List<SidebarItem> items;

    public string label {
        public set {
            _label.set_label(value);
        }
        public get {
            return _label.get_text();
        }
    }

    public string icon_name {
        public set {
            _icon.set_from_icon_name(value, Gtk.IconSize.BUTTON);
        }
        public owned get {
            return _icon.icon_name;
        }
    }

    private bool _selected;
    public bool selected {
        public set {
            _selected = value;
            if (!value && selected_item != null) {
                /* invalidate child selection.. */
                selected_item.selected = false;
                selected_item = null;
            }
            queue_draw();
        }
        public get {
            return _selected;
        }
    }

    /**
     * "Usable" state, visually different for disconnected servers, etc.
     */
    private bool _usable;
    public bool usable {
        public set {
            if (value) {
                get_style_context().remove_class("dim-label");
            } else {
                get_style_context().add_class("dim-label");
            }
            _usable = usable;
        }
        public get {
            return _usable;
        }
        default = true;
    }

    public signal void clicked();
    public signal void activated();

    private weak SidebarItem? selected_item;

    public void select_item(SidebarItem? item)
    {
        if (selected_item != null) {
            selected_item.selected = false;
        }
        selected_item = item;
        selected_item.selected = true;
        queue_draw();
        clicked();
        selected = true;
    }

    public void select_first_item()
    {
        /* First item is always us.. */
        activated();
        clicked();
        selected = true;
    }

    public void select_last_item()
    {
        SidebarItem? item = null;
        if (items.length()  >= 1) {
            item = items.nth_data(items.length()-1);
            select_item(item);
            item.activate();
            return;
        }
        selected_item = null;
        activated();
        clicked();
        selected = true;
    }

    public bool handle_mouse(Gtk.Widget? source_widget, Gdk.EventButton button) {
        if (source_widget.get_type() == typeof(SidebarItem)) {
           select_item((SidebarItem)source_widget);
        } else {
            if (selected_item != null) {
                selected_item.selected = false;
                selected_item = null;
                queue_draw();
            }
            activated();
            clicked();
            selected = true;
        }
        return Gdk.EVENT_PROPAGATE;
    }

    public SidebarItem add_item(string label, string icon)
    {
        var item = new SidebarItem(label, icon);
        item.button_press_event.connect(handle_mouse);
        revealer_box.pack_start(item);
        update_expander();

        item.set_data("index", items.length());
        items.append(item);
        return item;
    }

    public void remove_item(SidebarItem? item)
    {
        revealer_box.remove(item);
        SidebarItem? target = null;

        int index = item.get_data("index");

        if (items.length()-1 == 0) {
            /* We just activate ourselves. */
            selected_item = null;
            activated();
            clicked();
            selected = true;
        } else {
            // choose previous first if we can, otherwise next
            if (index-1 >= 0) {
                target = items.nth_data(index-1);
            } else {
                target = items.nth_data(index+1);
            }
            this.select_item(target);
            target.activate();
        }

        /* move chain down */
        if (index < items.length()) {
            for (int i = index+1; i < items.length(); i++) {
                var old = items.nth_data(i);
                old.set_data("index", i-1);
            }
        }
        items.remove(item);

        update_expander();
        return;
    }

    private void update_expander()
    {
        var kids = revealer_box.get_children();
        if (kids != null || kids.length() > 0) {
            _expand.show_all();
        } else {
            _expand.hide();
        }
        queue_resize();
        r.targ.queue_resize();
        r.queue_resize();
        queue_draw();
    }

    public void set_expanded(bool exp)
    {
        var kids = revealer_box.get_children();
        if (kids == null || kids.length() == 0) {
            return;
        }
        string icon = exp ? "list-remove-symbolic" : "list-add-symbolic";
        revealer.set_reveal_child(exp);
        (_expand.get_image() as Gtk.Image).set_from_icon_name(icon, Gtk.IconSize.MENU);
    }

    /**
     * Construct a new SidebarExpandable
     *
     * @param label The label to display
     * @param icon The icon to display
     */
    public SidebarExpandable(string label, string icon)
    {
        Object(orientation: Gtk.Orientation.VERTICAL);

        _label = new Gtk.Label(label);
        _label.halign = Gtk.Align.START;

        var overlay = new Gtk.Overlay();
        pack_start(overlay, false, false, 0);

        items = new List<SidebarItem>();

        /* includes whole widget.. */
        get_style_context().add_class("sidebar-expandable");

        var wrap = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        var wrap2 = new Gtk.EventBox();
        wrap2.add(wrap);
        wrap.get_style_context().add_class("sidebar-header");
        wrap2.button_press_event.connect(handle_mouse);
        wrap.draw.connect((cr)=> {
            Gtk.Allocation alloc;
            wrap.get_allocation(out alloc);
            var st = wrap.get_style_context();

            if (selected_item != null && selected_item.selected && !revealer.get_reveal_child()) {
                st.set_state(Gtk.StateFlags.SELECTED | get_state_flags());
            } else if (selected && selected_item == null) {
                st.set_state(Gtk.StateFlags.SELECTED | get_state_flags());
            } else {
                st.set_state(get_state_flags());
            }
        
            st.render_background(cr, alloc.x, alloc.y, alloc.width, alloc.height);
            st.render_frame(cr, alloc.x, alloc.y, alloc.width, alloc.height);
            return false;
        });
        _icon = new Gtk.Image.from_icon_name(icon, Gtk.IconSize.BUTTON);
        _icon.margin = 5;
        wrap.pack_start(_icon, false, false, 0);
        wrap.pack_start(_label, true, true, 0);

        _expand = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.MENU);
        _expand.set_can_focus(false);
        _expand.valign = Gtk.Align.CENTER;
        _expand.set_relief(Gtk.ReliefStyle.NONE);
        _expand.clicked.connect(on_clicked);
        wrap.pack_end(_expand, false, false, 0);

        r = new ReserveBox(wrap2);
        overlay.add_overlay(wrap2);
        _label.show();

        revealer = new Gtk.Revealer();
        revealer_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        revealer_box.remove.connect(()=> {
            update_expander();
        });
        revealer.add(revealer_box);
        pack_start(revealer, false, false, 0);

        /* Reserve widget .. spacing */
        overlay.add(r);
        overlay.show_all();

        show_all();
        no_show_all = true;
        _expand.hide();
    }

    private void on_clicked()
    {
        var vis = !(revealer.get_reveal_child());
        string icon = vis ? "list-remove-symbolic" : "list-add-symbolic";
        revealer.set_reveal_child(vis);
        (_expand.get_image() as Gtk.Image).set_from_icon_name(icon, Gtk.IconSize.MENU);
    }

}

/**
 * Simple sidebar widget, akin to a 2 depth treeview but with a shmexy
 * revealer transition for expanding
 */
public class IrcSidebar : Gtk.Box
{

    private weak SidebarExpandable? selected_row;
    private bool we_change = false;
    private List<SidebarExpandable> rows;

    public IrcSidebar()
    {
        Object(orientation: Gtk.Orientation.VERTICAL);
        selected_row = null;
        rows = new List<SidebarExpandable>();
    }

    public void select_row(SidebarExpandable? row)
    {
        on_row_click(row);
        row.activated();
    }

    private void on_row_click(SidebarExpandable? source)
    {
        if (source == selected_row) {
            return;
        }
        we_change = true;
        if (selected_row != null ) {
            selected_row.freeze_notify();
            selected_row.selected = false;
            selected_row.thaw_notify();
            selected_row.queue_draw();
        }
        selected_row = source;
        selected_row.freeze_notify();
        selected_row.selected = true;
        selected_row.thaw_notify();
        selected_row.queue_draw();

        we_change = false;
    }

    public SidebarExpandable add_expandable(string label, string icon)
    {
        var exp = new SidebarExpandable(label, icon);
        exp.clicked.connect(on_row_click);
        pack_start(exp, false, false, 0);
        if (selected_row == null) {
            we_change = true;
            selected_row = exp;
            selected_row.freeze_notify();
            selected_row.selected = true;
            selected_row.thaw_notify();
            we_change = false;
            selected_row.activate();
        }

        exp.set_data("index", rows.length());
        rows.append(exp);
        return exp;
    }

    public void remove_expandable(SidebarExpandable exp)
    {
        remove(exp);
        SidebarExpandable? target = null;

        int index = exp.get_data("index");

        if (rows.length()-1 == 0) {
            /* screwed. */
            return;
        }

        // choose previous first if we can, otherwise next
        if (index-1 >= 0) {
            target = rows.nth_data(index-1);
            target.select_last_item();
        } else {
            target = rows.nth_data(index+1);
            target.select_first_item();
        }

        /* move chain down */
        if (index < rows.length()) {
            for (int i = index+1; i < rows.length(); i++) {
                var old = rows.nth_data(i);
                old.set_data("index", i-1);
            }
        }

        rows.remove(exp);
    }
}
