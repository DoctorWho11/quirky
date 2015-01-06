/*
 * Messages.vala
 *
 * @note: This file is somewhat temporary, eventually we'll have a config file
 * to store all this.
 *
 * Copyright 2015 Ikey Doherty <ikey@evolve-os.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/* Colour index.
 * 0 = white
 * 1 = black
 * 2 = blue
 * 3 = green
 * 4 = red
 * 5 = brown
 * 6 = purple
 * 7 = orange
 * 8 = yellow
 * 9 = lightgreen
 * 10 = teal
 * 11 = cyan
 * 12 = lightblue
 * 13 = pink
 * 14 = grey
 * 15 = lightgrey
 *
 * 30 = auto nick colour
 */

public class MSG
{
    public static const string JOIN         = "$t* %C3$1 has joined $2";
    public static const string YOU_JOIN     = "$t* %C3You have joined $2";

    public static const string PART         = "$t* %C4$1 has left $2";
    public static const string PART_R       = "$t* %C4$1 has left $2 ($3)";
    public static const string YOU_PART     = "$t* %C4You have left $2";
    public static const string YOU_PART_R   = "$t* %C4You have left $2 ($3)";

    public static const string NICK         = "$t* %C30$1%C30 has changed their nick to %C30$2%0";
    public static const string YOU_NICK     = "$t* You have changed your nick to %C30$2%0";

    public static const string ACTION       = "$t%C30* $1%O $2";

    public static const string MESSAGE      = "%C30$1%C$t$2"; /* ← lol. */

    public static const string QUIT         = "$t* %C5$1 has quit ($2)";

    public static const string MOTD         = "$t%C6$1";
    public static const string INFO         = "$t%C2=>%C $1";
    public static const string DISCLAIM     = "$t%C6$1";
    public static const string HELP_LIST    = "$t$1";
    public static const string HELP_ITEM    = "$t* $1";
    public static const string HELP_VIEW    = "%U$1%O$t $2";

    public static const string ERROR        = "$t%C4=>%C $1";
}
