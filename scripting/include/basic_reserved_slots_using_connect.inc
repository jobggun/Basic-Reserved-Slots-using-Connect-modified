#if defined _basic_reserved_slots_using_connect_included
    #endinput
#endif
#define _basic_reserved_slots_using_connect_included

#pragma semicolon 1

public SharedPlugin __pl_brsc =
{
    name = "brsc",
    file = "basic_reserved_slots_using_connect.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

public __pl_brsc_SetNTVOptional()
{
    MarkNativeAsOptional("BRSC_AddFilter");
}

typedef FilterFunction = function Action(const char[] steamID, AdminId admin);

native BRSC_AddFilter(FilterFunction func);