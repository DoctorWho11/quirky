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

/**
 * Validation purposes.
 * i.e. a JOIN is VALUE_ONLY, anything after ": "
 * PRIVMSG is REQUIRES_VALUE|REQUIRES_PARAMS. Parameter is the target, and the
 * text segment is the PRIVMSG.. Well, you get the idea.
 */
public enum IrcParseFlags {
    NONE            = 0,
    VALUE_ONLY      = 1 << 0,
    REQUIRES_PARAMS = 1 << 1,
    REQUIRES_VALUE  = 1 << 2
}

/**
 * Encapsulate the parsing context and provide everything that a handler could
 * possibly need to know.
 */
public struct IrcParserContext {
    string? prefix; /**<Sender prefix, i.e. server or hostmask */
    string? command; /**<Command or numeric, i.e. PRIVMSG,  0001 */
    string[]? params; /**<Parameters given in the command, i.e. #evolveos */
    string? text; /**<Text segment following ": ", i.e. HAI THAR */
    int numeric; /**<Numeric value of command segment, -1 if its not a numeric */
    bool special; /**<Special case like PING, i.e. no :prefix, and cmd == prefix */
}

/**
 * Callback definition for IrcHandlers
 */
public delegate void IrcCallback (ref IrcParserContext p);

/**
 * Required for safe encapsulation of a callback
 */
public struct IrcHandler
{
    IrcParseFlags flags;    /* Required flags to be a valid call */
    weak IrcCallback ex;     /* Callback to execute when everything is valid. */
    int min_params;          /* Minimum parameter count for REQUIRES_PARAMS */
    int max_params;          /* Maximum parameter count for REQUIRES_PARAMS */
    int max_arg;             /* Maximum arguments in a text segment */
}

/**
 * Simplistic parser of IRC text. Keeps us Moar Safer.
 */
public class IrcParser {

    /**
     * Parse the given raw line (post \r\n strip) and if successful, populate
     * the context with everything known during this parse step
     *
     * @param input Raw line of IRC input
     * @param context Set when this method is successful
     *
     * @return true if this was successful, or false if we fail.
     */
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
