EXTRA_DIST = \
	client-resources.gresource.xml \
	messages.conf \
	servers.conf \
	style.css \
	quirky.desktop \
	quirky-128x128.png \
	quirky-16x16.png \
	quirky-192x192.png \
	quirky-22x22.png \
	quirky-24x24.png \
	quirky-256x256.png \
	quirky-32x32.png \
	quirky-36x36.png \
	quirky-48x48.png \
	quirky-512x512.png \
	quirky-64x64.png \
	quirky-72x72.png \
	quirky-96x96.png \
	quirky.ico

# Our .desktop file
desktopdir=$(datadir)/applications
desktop_DATA = \
	quirky.desktop

# Our PNG's
icon_sizes = \
	128x128 \
	16x16 \
	192x192 \
	22x22 \
	24x24 \
	256x256 \
	32x32 \
	36x36 \
	48x48 \
	512x512 \
	64x64 \
	72x72 \
	96x96 \
	$(NULL)

install-icons:
	for iconsize in $(icon_sizes); do \
		mkdir -p $(DESTDIR)$(datadir)/icons/hicolor/$$iconsize/apps; \
		$(INSTALL_DATA) $(srcdir)/quirky-$$iconsize.png $(DESTDIR)$(datadir)/icons/hicolor/$$iconsize/apps/quirky.png; \
	done

uninstall-icons:
	for iconsize in $(icon_sizes); do \
		rm $(DESTDIR)$(datadir)/icons/hicolor/$$iconsize/apps/quirky.png; \
	done

install-data-local: install-icons
uninstall-local: uninstall-icons
