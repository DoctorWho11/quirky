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

    RPL_MOTDSTART = 375, /* Message-of-the-day (start) */
    RPL_MOTD = 372, /* Message-of-the-day (content) */
    RPL_ENDOFMOTD = 376 /* Message-of-the-day (end) */
}
