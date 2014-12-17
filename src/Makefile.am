EXTRA_DIST = 

bin_PROGRAMS = dummy-bot

dummy_bot_SOURCES = \
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
