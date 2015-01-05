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
	dummy-client

dummy_bot_SOURCES = \
	IrcConstants.vala \
	IrcCore.vala \
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

dummy_client_SOURCES = \
	client-resources.h \
	client-resources.c \
	IrcConstants.vala \
	IrcCore.vala \
	IrcTextWidget.vala \
	Widgets.vala \
	DummyClient.vala

dummy_client_CFLAGS = \
	$(GOBJECT_CFLAGS) \
	$(GIO_CFLAGS) \
	$(GTK_CFLAGS)

dummy_client_LDADD = \
	$(GOBJECT_LIBS) \
	$(GIO_LIBS) \
	$(GTK_LIBS)

dummy_client_VALAFLAGS = \
	--pkg gtk+-3.0 \
	--pkg gio-2.0 \
	$(VALAFLAGS)
