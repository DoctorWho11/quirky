/*
 * Messages.vala
 *
 * See messages.conf for explanations.
 *
 * Copyright 2015 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class MSG
{
    public static const string JOIN              = "join";
    public static const string YOU_JOIN          = "you_join";

    public static const string TOPIC             = "topic";
    public static const string TOPIC_WHO         = "topic_who";
    public static const string PART              = "part";
    public static const string PART_R            = "part_reason";
    public static const string YOU_PART          = "you_part";
    public static const string YOU_PART_R        = "you_part_reason";

    public static const string NICK              = "nick_change";
    public static const string YOU_NICK          = "you_nick_change";

    public static const string ACTION            = "action";
    public static const string ACTION_HIGHLIGHT  = "action_highlight";

    public static const string MESSAGE           = "message";
    public static const string MESSAGE_HIGHLIGHT = "message_highlight";
    public static const string PM                = "pm";
    public static const string CHANNEL_NOTICE    = "channel_notice";
    public static const string NOTICE            = "notice";
    public static const string QUIT              = "quit";

    public static const string MOTD              = "motd";
    public static const string SERVER_NOTICE     = "server_notice";
    public static const string INFO              = "info";
    public static const string DISCLAIM          = "disclaimer";
    public static const string HELP_LIST         = "help_list";
    public static const string HELP_ITEM         = "help_item";
    public static const string HELP_VIEW         = "help_view";

    public static const string LOGGING_IN        = "logging_in";
    public static const string LOGIN_SUCCESS     = "login_success";
    public static const string LOGIN_FAIL        = "login_fail";

    public static const string ERROR             = "error";
}
