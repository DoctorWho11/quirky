/*
 * IrcConstants.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey@evolve-os.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public enum IRC {
    RPL_WELCOME = 001, /* Successful connection to IRC/registered */

    RPL_NAMREPLY = 353, /* Name list */
    RPL_ENDOFNAMES = 366, /* End of names list */

    /* Nickname errors */
    ERR_NONICKNAMEGIVEN = 431, /* Duh. */
    ERR_ERRONEUSNICKNAME =  432, /* Invalid nickname (/NICK) */
    ERR_NICKNAMEINUSE = 433, /* Someone has this nick. */
    ERR_NICKCOLLISION = 436, /* Goodbye imposter! */
    ERR_UNAVAILRESOURCE = 437, /* Channel or nick delay */

    ERR_RESTRICTED = 484, /* Restricted (+r) connection */

    RPL_MOTDSTART = 375, /* Message-of-the-day (start) */
    RPL_MOTD = 372, /* Message-of-the-day (content) */
    RPL_ENDOFMOTD = 376 /* Message-of-the-day (end) */
}
