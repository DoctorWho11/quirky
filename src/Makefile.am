EXTRA_DIST = 

client_resources = $(shell glib-compile-resources --sourcedir=$(top_srcdir)/data --generate-dependencies $(top_srcdir)/data/client-resources.gresource.xml)

BUILT_SOURCES = \
	client-resources.h \
	client-resources.c

CLEANFILES = \
	$(BUILT_SOURCES)

# resources
client-resources.h: $(top_srcdir)/data/client-resources.gresource.xml $(client_resources)
	glib-compile-resources --target=$@ --sourcedir=$(top_srcdir)/data --generate-header --c-name client_resources $<

client-resources.c: $(top_srcdir)/data/client-resources.gresource.xml $(client_resources)
	glib-compile-resources --target=$@ --sourcedir=$(top_srcdir)/data --generate-source --c-name client_resources $<


bin_PROGRAMS = \
	dummy-bot \
	quirky

dummy_bot_SOURCES = \
	IrcConstants.vala \
	IrcCore.vala \
	IrcParser.vala \
	DummyBot.vala

dummy_bot_CFLAGS = \
	$(GOBJECT_CFLAGS) \
	$(GIO_CFLAGS)

dummy_bot_LDADD = \
	$(GOBJECT_LIBS) \
	$(GIO_LIBS)

dummy_bot_VALAFLAGS = \
	$(VALAFLAGS) \
	--pkg gio-2.0

quirky_SOURCES = \
	client-resources.h \
	client-resources.c \
	CountItem.vala \
	Dialogs.vala \
	IrcConstants.vala \
	IrcCore.vala \
	IrcParser.vala \
	IrcTextEntry.vala \
	IrcTextWidget.vala \
	Messages.vala \
	Sidebar.vala \
	QuirkyClient.vala

quirky_CFLAGS = \
	$(GOBJECT_CFLAGS) \
	$(GIO_CFLAGS) \
	$(GTK_CFLAGS)

quirky_LDADD = \
	$(GOBJECT_LIBS) \
	$(GIO_LIBS) \
	$(GTK_LIBS)

quirky_VALAFLAGS = \
	--pkg gtk+-3.0 \
	--pkg gio-2.0 \
	$(VALAFLAGS)
