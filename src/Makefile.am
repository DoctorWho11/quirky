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
	$(VALAFLAGS)


if BUILD_WINDOWS
	dummy_bot_CFLAGS += $(GIO_WINDOWS_CFLAGS)
	dummy_bot_LDADD += $(GIO_WINDOWS_LIBS)
else
	dummy_bot_CFLAGS += $(GIO_UNIX_CFLAGS)
	dummy_bot_LDADD += $(GIO_UNIX_LIBS)
endif


dummy_client_SOURCES = \
	IrcConstants.vala \
	IrcCore.vala \
	IrcTextWidget.vala \
	Widgets.vala \
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
	--pkg gtk+-3.0 \
	$(VALAFLAGS)

if BUILD_WINDOWS
	dummy_client_CFLAGS += $(GIO_WINDOWS_CFLAGS)
	dummy_client_LDADD += $(GIO_WINDOWS_LIBS)
else
	dummy_client_CFLAGS += $(GIO_UNIX_CFLAGS)
	dummy_client_LDADD += $(GIO_UNIX_LIBS)
endif
