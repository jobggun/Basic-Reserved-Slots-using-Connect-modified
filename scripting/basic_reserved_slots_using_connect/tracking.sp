static Cookie g_hReservedSlotsUsageCookie = null;
static StringMap g_hReservedSlotsUsageTempStringMap = null;

void SetUpTracking()
{
	g_hReservedSlotsUsageCookie = new Cookie("brsc_reserved_used", "Whether client used reserved slots in the session", CookieAccess_Protected);
	g_hReservedSlotsUsageTempStringMap = new StringMap();

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}

void TerminateTracking()
{
	delete g_hReservedSlotsUsageTempStringMap;
	delete g_hReservedSlotsUsageCookie;
}

void AddTracking(const char[] steamID)
{
	g_hReservedSlotsUsageTempStringMap.SetValue(steamID, 1);
}

public void OnClientCookiesCached(int client)
{
	char steamID[32];
	GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));

	int value = 0;
	if(g_hReservedSlotsUsageTempStringMap.GetValue(steamID, value) && value == 1)
	{
		SetClientCookie(client, g_hReservedSlotsUsageCookie, "1");
		g_hReservedSlotsUsageTempStringMap.Remove(steamID);
	}
	else
	{
		SetClientCookie(client, g_hReservedSlotsUsageCookie, "0");
	}
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if(!IsValidClient(client))
		return Plugin_Continue;
	
	if(!AreClientCookiesCached(client))
		return Plugin_Continue;

	char reserved[4] = "0";
	GetClientCookie(client, g_hReservedSlotsUsageCookie, reserved, sizeof(reserved));

	int iReserved = StringToInt(reserved);

	if(iReserved == 0)
		return Plugin_Continue;
	
	char steamID[32];
	GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));

	Database db = connectToDatabase();

	if(db == null)
		return Plugin_Continue;
		
	InsertUsage(db, steamID, steamID);

	delete db;

	return Plugin_Continue;
}