#include <sourcemod>
#include <clientprefs>
#include <connect>

#pragma newdecls required
#pragma semicolon 1

#define _DEBUG

#define PLUGIN_VERSION "1.00"

bool g_bPlayerTickStartEnabled = false;
int g_iPlayerTickStartTime[MAXPLAYERS + 1] = { 0, ... };
int g_iCurrentValidPlayerCount = 0;

Cookie g_hReservedSlotsUsageCookie = null;
StringMap g_hReservedSlotsUsageTempStringMap = null;

#include <basic_reserved_slots_using_connect/log.sp>
#include <basic_reserved_slots_using_connect/convar.sp>
#include <basic_reserved_slots_using_connect/database.sp>
#include <basic_reserved_slots_using_connect/lateload.sp>

public Plugin myinfo = 
{
	name = "Basic Reserved Slots using Connect",
	author = "luki1412",
	description = "Simple plugin for reserved slots using Connect",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/member.php?u=43109"
}

public void OnPluginStart()
{
	SetupConVars();

	g_hReservedSlotsUsageCookie = new Cookie("brsc_reserved_used", "Whether client used reserved slots in the session", CookieAccess_Protected);
	g_hReservedSlotsUsageTempStringMap = new StringMap();

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	HandleLateLoad();
}

public void OnPluginEnd()
{
	delete g_hReservedSlotsUsageTempStringMap;
	delete g_hReservedSlotsUsageCookie;

	if(g_bPlayerTickStartEnabled)
	{
		int time_played;
		char steamID[32];

		int currentTime = GetTime();

		g_bPlayerTickStartEnabled = false;

		Database db = connectToDatabase();

		if(db == null)
		{
			return;
		}

		for(int i = 1; i <= MaxClients; i++)
		{
			if(g_iPlayerTickStartTime[i] == 0)
				continue;
			
			time_played = currentTime - g_iPlayerTickStartTime[i];

			g_iPlayerTickStartTime[i] = 0;

			if(!GetClientAuthId(i, AuthId_Steam2, steamID, sizeof(steamID))) continue;

			InsertTimePlayed(db, steamID, time_played);
		}

		delete db;
	}
}

public void OnClientPutInServer(int client)
{
	if(!IsValidClient(client))
		return;

	g_iCurrentValidPlayerCount += 1;
	
	if(g_iCurrentValidPlayerCount < g_icvarPlayerCountCondition)
		return;

	int currentTime = GetTime();
	
	if(!g_bPlayerTickStartEnabled)
	{
		g_bPlayerTickStartEnabled = true;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i))
				continue;
			
			g_iPlayerTickStartTime[i] = currentTime;
		}
	}
	else
	{
		g_iPlayerTickStartTime[client] = currentTime;
	}
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

public void OnClientDisconnect(int client)
{	
	if(!IsValidClient(client))
		return;
	
	g_iCurrentValidPlayerCount -= 1;

	if(!g_bPlayerTickStartEnabled)
		return;

	int time_played;
	char steamID[32];

	int currentTime = GetTime();

	if(g_iCurrentValidPlayerCount >= g_icvarPlayerCountCondition)
	{
		if(g_iPlayerTickStartTime[client] == 0)
			return;

		time_played = currentTime - g_iPlayerTickStartTime[client];

		g_iPlayerTickStartTime[client] = 0;

		if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) return;

		Database db = connectToDatabase();

		if(db == null)
		{
			return;
		}

		InsertTimePlayed(db, steamID, time_played);

		delete db;
	}
	else
	{
		g_bPlayerTickStartEnabled = false;

		Database db = connectToDatabase();

		if(db == null)
		{
			return;
		}

		for(int i = 1; i <= MaxClients; i++)
		{
			if(g_iPlayerTickStartTime[i] == 0)
				continue;
			
			time_played = currentTime - g_iPlayerTickStartTime[i];

			g_iPlayerTickStartTime[i] = 0;

			if(!GetClientAuthId(i, AuthId_Steam2, steamID, sizeof(steamID))) continue;

			InsertTimePlayed(db, steamID, time_played);
		}

		delete db;
	}
}

public bool OnClientPreConnectEx(const char[] name, char password[255], const char[] ip, const char[] steamID, char rejectReason[255])
{
	#if defined _DEBUG
	LogBRSCMessage("[OnClientPreConnectEx] steamID: %s, GetClientCount(false): %d, GetClientCount(true): %d, MaxClients: %d", steamID, GetClientCount(false), GetClientCount(true), MaxClients);
	#endif

	if (!GetConVarInt(g_hcvarEnabled))
	{
		#if defined _DEBUG
		LogBRSCMessage("[OnClientPreConnectEx] Plugin Disabled");
		#endif
		return true;
	}

	if (GetClientCount(false) < MaxClients)
	{
		#if defined _DEBUG
		LogBRSCMessage("[OnClientPreConnectEx] GetClientCount(false) < MaxClients");
		#endif
		return true;	
	}

	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, steamID);

	Database db = null;
	bool kickCondition = false;

	if (GetAdminFlag(admin, Admin_Generic))
	{
		#if defined _DEBUG
		LogBRSCMessage("[OnClientPreConnectEx] Access Granted: Admin_Generic (b flag)");
		#endif
		kickCondition = true;
	}
	
	if (!kickCondition && GetAdminFlag(admin, Admin_Reservation))
	{
		db = connectToDatabase();

		kickCondition = true;

		if(db != null)
		{
			#if defined _DEBUG
			LogBRSCMessage("[OnClientPreConnectEx] Checking if connecting player is applicable to reservation...");
			#endif
			kickCondition = !checkIfUsageExceeded(db, steamID);
			delete db;
		}
		else
		{
			#if defined _DEBUG
			LogBRSCMessage("[OnClientPreConnectEx] Database fail, Granting access without checking...");
			#endif
		}

		#if defined _DEBUG
		if(kickCondition)
			LogBRSCMessage("[OnClientPreConnectEx] Access Granted: Admin_Reservation (a flag)");
		else
			LogBRSCMessage("[OnClientPreConnectEx] Access Denied: Admin_Reservation (a flag)");
		#endif
	}

	if (!kickCondition)
	{
		db = connectToDatabase();

		if(db != null)
		{
			#if defined _DEBUG
			LogBRSCMessage("[OnClientPreConnectEx] Checking if connecting player is applicable to reservation...");
			#endif
			kickCondition = checkNonDonorAllowed(db, steamID);
			delete db;
		}
		else
		{
			#if defined _DEBUG
			LogBRSCMessage("[OnClientPreConnectEx] Database fail, Denying access without checking...");
			#endif
		}

		#if defined _DEBUG
		if(kickCondition)
			LogBRSCMessage("[OnClientPreConnectEx] Access Granted: Not admin (no flag)");
		else
			LogBRSCMessage("[OnClientPreConnectEx] Access Denied: Not admin (no flag)");
		#endif
	}

	if(kickCondition)
	{
		#if defined _DEBUG
		LogBRSCMessage("[OnClientPreConnectEx] Invoking SelectKickClient for selecting client to kick...");
		#endif

		int target = SelectKickClient();

		#if defined _DEBUG
		LogBRSCMessage("[OnClientPreConnectEx] Selected client to kick");
		#endif
		
		if(db == null)
		{
			db = connectToDatabase();
		}

		if(target && db != null)
		{
			char targetSteamID[32];
			GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID));

			#if defined _DEBUG
			LogBRSCMessage("[OnClientPreConnectEx] Resetting the total play time of target player: %s...", targetSteamID);
			#endif
			ResetTimePlayed(db, targetSteamID);

			#if defined _DEBUG
			LogBRSCMessage("[OnClientPreConnectEx] Inserting the usage of reservation slots of player: (%s, %s)...", steamID, targetSteamID);
			#endif
			InsertUsage(db, steamID, targetSteamID);
		}

		if(db != null)
		{
			delete db;
		}

		if (target)
		{
			char rReason[255];
			GetConVarString(g_hcvarReason, rReason, sizeof(rReason));
			#if defined _DEBUG
			LogBRSCMessage("[OnClientPreConnectEx] Kicking target player...");
			#endif

			if(!StrEqual(g_sRedirectionServerAddress, ""))
			{
				ClientCommand(target, "redirect %s", g_sRedirectionServerAddress);
			}

			KickClientEx(target, "%s", rReason);

			g_hReservedSlotsUsageTempStringMap.SetValue(steamID, 1);
		}
	}
	
	return true;
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

int SelectKickClient()
{	
	float highestValue;
	int highestValueId;
	
	float highestSpecValue;
	int highestSpecValueId;
	
	bool specFound;
	
	float value;
	
	Database db = null;
	char steamID[32];
	int currentTime;

	int ikickType = GetConVarInt(g_hcvarKickType);
	#if defined _DEBUG
	LogBRSCMessage("[SelectKickClient] Kick type convar int is %d", ikickType);
	#endif

	if(ikickType == 3)
	{
		db = connectToDatabase();
		if(db == null)
		{
			ikickType = 2;
			#if defined _DEBUG
			LogBRSCMessage("[SelectKickClient] DB failure, setting iKickType to %d", ikickType);
			#endif
		}
		else
		{
			#if defined _DEBUG
			LogBRSCMessage("[SelectKickClient] DB success");
			#endif
		}
		currentTime = GetTime();
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		#if defined _DEBUG
		LogBRSCMessage("[SelectKickClient] client num %d: ", i);
		#endif
		if (!IsValidClient(i))
		{
			#if defined _DEBUG
			LogBRSCMessage("[SelectKickClient] Not valid client ");
			#endif
			continue;
		}
	
		int flags = GetUserFlagBits(i);
		
		if (IsFakeClient(i) || flags & ADMFLAG_ROOT || flags & ADMFLAG_GENERIC || CheckCommandAccess(i, "sm_reskick_immunity", ADMFLAG_GENERIC, false))
		{
			#if defined _DEBUG
			LogBRSCMessage("[SelectKickClient] Client is root or generic admin ");
			#endif
			continue;
		}
		
		value = 0.0;
		
		switch(ikickType)
		{
			case 1:
			{
				value = GetClientAvgLatency(i, NetFlow_Outgoing);
			}
			case 2:
			{
				value = GetClientTime(i);
			}
			case 3:
			{
				int time = 0;

				GetClientAuthId(i, AuthId_Steam2, steamID, sizeof(steamID));

				SelectTimePlayed(db, steamID, time);

				if(g_iPlayerTickStartTime[i] != 0)
				{
					time += currentTime - g_iPlayerTickStartTime[i];
				}

				value = 0.0 + time;
			}
			default:
			{
				value = GetRandomFloat(0.0, 100.0);
			}
		}

		#if defined _DEBUG
		LogBRSCMessage("[SelectKickClient] kickPriority: %f", value);
		#endif

		if (IsClientObserver(i))
		{
			#if defined _DEBUG
			LogBRSCMessage("[SelectKickClient] Client is spectator");
			#endif	
			specFound = true;
			
			if (value > highestSpecValue)
			{
				highestSpecValue = value;
				highestSpecValueId = i;
			}
		}
		
		if (value >= highestValue)
		{
			highestValue = value;
			highestValueId = i;
		}
	}

	if(db != null)
	{
		delete db;
	}
	
	if (specFound)
	{
		#if defined _DEBUG
		LogBRSCMessage("[SelectKickClient] client who has highest priority is %d with value %f", highestSpecValueId, highestSpecValue);
		#endif
		return highestSpecValueId;
	}

	#if defined _DEBUG
	LogBRSCMessage("[SelectKickClient] client who has highest priority is %d with value %f", highestValueId, highestValue);
	#endif
	
	return highestValueId;
}

stock bool IsValidClient(int client, bool replaycheck = true)
{
	if(client <= 0 || client > MaxClients)
		return false;

	if(!IsClientConnected(client))
		return false;

	if(!IsClientInGame(client))
		return false;

	if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
		return false;

	if(replaycheck && (IsClientSourceTV(client) || IsClientReplay(client)))
		return false;
	
	return true;
}

bool checkIfUsageExceeded(Database db, const char[] steamID)
{
	int available = 0;

	if(!SelectUsage(db, steamID, available)) return false;

	if(!available)
	{
		return true;
	}

	return false;
}

bool checkNonDonorAllowed(Database db, const char[] steamID)
{
	int available1 = 0;
	int available2 = 0;

	if(!SelectNonDonorUsage(db, steamID, available1)) return false;
	if(!SelectUsage(db, steamID, available2)) return false;

	if(!available1 || !available2)
	{
		return false;
	}

	return true;
}

// ConVar
