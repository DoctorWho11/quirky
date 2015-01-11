/*
 * IrcParser.vala
 * 
 * Copyright 2015 Ikey Doherty <ikey@evolve-os.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public struct IrcParserContext {
    string? prefix;
    string? command;
    string[]? params;
    string? text;
    int numeric;
    bool special;
}

public class IrcParser {

    public bool parse(string input, out IrcParserContext context)
    {
        context = IrcParserContext() {
            prefix = null,
            command = null,
            params = null,
            text = null,
            numeric = -1,
            special = false
        };
        /* fu, go home */
        if (input.length > 512) {
            return false;
        }
        int index = input.index_of(" ");
        if (index < 1) {
            /* All IRC messages have spaces. Go home. */
            return false;
        }

        int colon_index = input.index_of(" :");

        var first = input.substring(0, index);

        string cmd = null;

        /* Obtain the command name. */
        if (first.has_prefix(":")) {
            var space = input.index_of(" ", index);
            if (space+1 < 1) {
                return false;
            }
            var nxt_space = input.index_of(" ", space+1);
            if (nxt_space+1 < 1) {
                return false;
            }
            cmd = input.substring(space+1, nxt_space-space-1);
        }
        /* Obtain any possible " :" text remnant */
        string text = null;
        if (colon_index > 0 && colon_index+2 < input.length) {
            text = input.substring(colon_index+2, input.length-colon_index-2);
        }
        /* Obtain any parameters (anything after command, and before string end or " :" */
        int params_end = colon_index > 0 ? colon_index : input.length;

        string params = null;
        int length = first.length+1  + (cmd != null ? cmd.length : 0);
        /* False positive for parameters. */
        if (length -1 != params_end) {
            params = input.substring(length, params_end-length);
        }

        /* Special cases like ping. */
        if (cmd == null && !input.has_prefix(":")) {
            cmd = input;
            context.special = true;
        }

        if (cmd.length == 3) {
            if (cmd[0].isdigit() && cmd[1].isdigit() && cmd[2].isdigit()) {
                context.numeric = int.parse(cmd);
            }
        }
        context.command = cmd;
        context.text = text;
        context.prefix = first;
        if (params != null) {
            context.params = params.strip().split(" ");
        }

        return true;
    }
}
