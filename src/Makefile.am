EXTRA_DIST = 

bin_PROGRAMS = \
	dummy-bot \
	dummy-client

dummy_bot_SOURCES = \
	IrcConstants.vala \
	IrcCore.vala \
	DummyBot.vala

dummy_bot_CFLAGS = \
	$(GOBJECT_CFLAGS) \
	$(GIO_UNIX_CFLAGS)

dummy_bot_LDADD = \
	$(GOBJECT_LIBS) \
	$(GIO_UNIX_LIBS)

dummy_bot_VALAFLAGS = \
	--pkg gio-unix-2.0



dummy_client_SOURCES = \
	IrcConstants.vala \
	IrcCore.vala \
	DummyClient.vala

dummy_client_CFLAGS = \
	$(GOBJECT_CFLAGS) \
	$(GIO_UNIX_CFLAGS) \
	$(GTK_CFLAGS)

dummy_client_LDADD = \
	$(GOBJECT_LIBS) \
	$(GIO_UNIX_LIBS) \
	$(GTK_LIBS)

dummy_client_VALAFLAGS = \
	--pkg gio-unix-2.0 \
	--pkg gtk+-3.0
