Quirky IRC Client
===============

Destined to be a *real* IRC client for both light and heavyweight
IRC users.
We do plan on supporting all IRCv3 extensions, and already have
minimal internal implementations under way.

In short: Wanted a good looking IRC client that was still an IRC client,
didn't have a shed-load of deps, and wasn't another IM library frontend. [1]

Currently under heavy development!


Important
--------
The core library is missing a ton of checks, so wil likely crash in some
situations.  ircfuzz kills it instantly.  Also note there is NO SSL validation
and all certificates are accepted!

License
------

GPLv2

Versioning
---------

Simple incremental version bumps, similar to other Evolve OS projects such as
Budgie, i.e. v1, v2, v3. Version number is not an indicator of stability or
feature parity.

Authors
-------
 * Ikey Doherty <ikey@evolve-os.com>

Icons
------
 * Quirky icon copyright of Alejandro Seoane, many thanks!
 
[1] They are CHANNELS. Not ROOMS.
