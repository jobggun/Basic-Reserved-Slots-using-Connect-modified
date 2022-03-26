#include <sourcemod>
#include <clientprefs>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "1.00"

public Extension __ext_Connect = 
{
	name = "Connect",
	file = "connect.ext",
	autoload = 1,
	required = 1,
}

ConVar g_hcvarKickType;
ConVar g_hcvarEnabled;
ConVar g_hcvarReason;
ConVar g_hcvarCooldownTime;
ConVar g_hcvarPlayerCountCondition;

int g_icvarCooldownTime = 60;
int g_icvarPlayerCountCondition = 28;

bool g_bPlayerTickStartEnabled = false;
int g_iPlayerTickStartTime[MAXPLAYERS + 1] = { 0, ... };
int g_iCurrentValidPlayerCount = 0;

Cookie g_hReservedSlotsUsageCookie = null;
StringMap g_hReservedSlotsUsageTempStringMap = null;

forward bool OnClientPreConnectEx(const char[] name, char password[255], const char[] ip, const char[] steamID, char rejectReason[255]);

bool g_bLateLoad = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_bLateLoad = true;
}

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
	ConVar g_hcvarVer = CreateConVar("sm_brsc_version", PLUGIN_VERSION, "Basic Reserved Slots using Connect - version cvar", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hcvarEnabled = CreateConVar("sm_brsc_enabled", "1", "Enables/disables this plugin", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hcvarKickType = CreateConVar("sm_brsc_type", "1", "Who gets kicked out: 1 - Highest ping player, 2 - Longest connection time player, 3 - Longest time played in database, 0 - Random player", FCVAR_NONE, true, 0.0, true, 3.0);
	g_hcvarReason = CreateConVar("sm_brsc_reason", "Kicked to make room for an admin", "Reason used when kicking players", FCVAR_NONE);
	g_hcvarCooldownTime = CreateConVar("sm_brsc_cooldown_time", "60", "Cooldown time for re use of reservation slot", FCVAR_NONE);
	g_hcvarPlayerCountCondition = CreateConVar("sm_brsc_player_count", "28", "Minimum players count for kick player queue", FCVAR_NONE);

	HookConVarChange(g_hcvarCooldownTime, ConVarCooldownTime);
	HookConVarChange(g_hcvarPlayerCountCondition, ConVarPlayerCountCondition);

	SetConVarString(g_hcvarVer, PLUGIN_VERSION);	
	AutoExecConfig(true, "Basic_Reserved_Slots_using_Connect");

	g_hReservedSlotsUsageCookie = new Cookie("brsc_reserved_used", "Whether client used reserved slots in the session", CookieAccess_Protected);
	g_hReservedSlotsUsageTempStringMap = new StringMap();

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	if(g_bLateLoad)
	{
		g_iCurrentValidPlayerCount = 0;
		g_bPlayerTickStartEnabled = false;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i))
				continue;
			
			g_iCurrentValidPlayerCount += 1;
		}

		if(g_iCurrentValidPlayerCount >= g_icvarPlayerCountCondition)
		{
			g_bPlayerTickStartEnabled = true;

			int currentTime = GetTime();

			for(int i = 1; i <= MaxClients; i++)
			{
				if(!IsValidClient(i))
					continue;
			
				g_iPlayerTickStartTime[i] = currentTime;
			}
		}
	}
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
	LogMessage("[OnClientPreConnectEx] steamID: %s, GetClientCount(false): %d, GetClientCount(true): %d, MaxClients: %d", steamID, GetClientCount(false), GetClientCount(true), MaxClients);
	#endif

	if (!GetConVarInt(g_hcvarEnabled))
	{
		#if defined _DEBUG
		LogMessage("[OnClientPreConnectEx] Plugin Disabled");
		#endif
		return true;
	}

	if (GetClientCount(false) < MaxClients)
	{
		#if defined _DEBUG
		LogMessage("[OnClientPreConnectEx] GetClientCount(false) < MaxClients");
		#endif
		return true;	
	}

	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, steamID);

	Database db = null;
	bool kickCondition = false;

	if (GetAdminFlag(admin, Admin_Generic))
	{
		#if defined _DEBUG
		LogMessage("[OnClientPreConnectEx] Access Granted: Admin_Generic (b flag)");
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
			LogMessage("[OnClientPreConnectEx] Checking if connecting player is applicable to reservation...");
			#endif
			kickCondition = !checkIfUsageExceeded(db, steamID);
			delete db;
		}
		else
		{
			#if defined _DEBUG
			LogMessage("[OnClientPreConnectEx] Database fail, Granting access without checking...");
			#endif
		}

		#if defined _DEBUG
		if(kickCondition)
			LogMessage("[OnClientPreConnectEx] Access Granted: Admin_Reservation (a flag)");
		else
			LogMessage("[OnClientPreConnectEx] Access Denied: Admin_Reservation (a flag)");
		#endif
	}

	if (!kickCondition)
	{
		db = connectToDatabase();

		if(db != null)
		{
			#if defined _DEBUG
			LogMessage("[OnClientPreConnectEx] Checking if connecting player is applicable to reservation...");
			#endif
			kickCondition = checkNonDonorAllowed(db, steamID);
			delete db;
		}
		else
		{
			#if defined _DEBUG
			LogMessage("[OnClientPreConnectEx] Database fail, Denying access without checking...");
			#endif
		}

		#if defined _DEBUG
		if(kickCondition)
			LogMessage("[OnClientPreConnectEx] Access Granted: Not admin (no flag)");
		else
			LogMessage("[OnClientPreConnectEx] Access Denied: Not admin (no flag)");
		#endif
	}

	if(kickCondition)
	{
		#if defined _DEBUG
		LogMessage("[OnClientPreConnectEx] Invoking SelectKickClient for selecting client to kick...");
		#endif

		int target = SelectKickClient();

		#if defined _DEBUG
		LogMessage("[OnClientPreConnectEx] Selected client to kick");
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
			LogMessage("[OnClientPreConnectEx] Resetting the total play time of target player: %s...", targetSteamID);
			#endif
			ResetTimePlayed(db, targetSteamID);

			#if defined _DEBUG
			LogMessage("[OnClientPreConnectEx] Inserting the usage of reservation slots of player: (%s, %s)...", steamID, targetSteamID);
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
			LogMessage("[OnClientPreConnectEx] Kicking target player...");
			#endif
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

	if(ikickType == 3)
	{
		db = connectToDatabase();
		if(db == null)
		{
			ikickType = 2;
		}
		currentTime = GetTime();
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{	
		if (!IsValidClient(i))
		{
			continue;
		}
	
		int flags = GetUserFlagBits(i);
		
		if (IsFakeClient(i) || flags & ADMFLAG_ROOT || flags & ADMFLAG_GENERIC || CheckCommandAccess(i, "sm_reskick_immunity", ADMFLAG_GENERIC, false))
		{
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

		if (IsClientObserver(i))
		{			
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
		return highestSpecValueId;
	}
	
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

void ConVarCooldownTime(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int iNewValue = StringToInt(newValue);

	if(iNewValue != 0)
	{
		g_icvarCooldownTime = iNewValue;
	}
}

void ConVarPlayerCountCondition(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int iOldValue = g_icvarPlayerCountCondition;
	int iNewValue = StringToInt(newValue);
	
	g_icvarPlayerCountCondition = iNewValue;

	if(iOldValue > iNewValue && g_iCurrentValidPlayerCount >= g_icvarPlayerCountCondition && !g_bPlayerTickStartEnabled)
	{
		g_bPlayerTickStartEnabled = true;

		int currentTime = GetTime();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i))
				continue;
			
			g_iPlayerTickStartTime[i] = currentTime;
		}
	}
	else if(iOldValue < iNewValue && g_iCurrentValidPlayerCount < g_icvarPlayerCountCondition && g_bPlayerTickStartEnabled)
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

// DB

bool db_createTableSuccess = false;

char db_createReserveUsage[] = "CREATE TABLE IF NOT EXISTS `reserved_slots_usage` ( \
	`id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, \
	`steam_id` VARCHAR(32) NOT NULL, \
	`victim_steam_id` VARCHAR(32) NOT NULL, \
	`timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP() \
);";

char db_usageInsert[] = "INSERT INTO `reserved_slots_usage` (`steam_id`, `victim_steam_id`) VALUES ('%s', '%s');";
char db_usageSelect[] = "SELECT NOT EXISTS(SELECT 1 FROM `reserved_slots_usage` WHERE `steam_id` = '%s' GROUP BY `steam_id` HAVING MAX(`timestamp`) >= NOW() - INTERVAL %d MINUTE) AND NOT EXISTS(SELECT 1 FROM `reserved_slots_usage` WHERE `victim_steam_id` = '%s' GROUP BY `victim_steam_id` HAVING MAX(`timestamp`) >= NOW() - INTERVAL %d MINUTE);";
char db_usageNonDonorSelect[] = "SELECT (SELECT COUNT(*) FROM `reserved_slots_usage` WHERE `victim_steam_id` = '%s' AND `steam_id` != `victim_steam_id`) - 2 * (SELECT COUNT(*) FROM `reserved_slots_usage` WHERE `steam_id` = '%s' AND `steam_id` != `victim_steam_id`) >= 2;";

char db_createTimePlayed[] = "CREATE TABLE IF NOT EXISTS `time_played` ( \
	`id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, \
	`steam_id` VARCHAR(32) NOT NULL, \
	`total_time` INT NOT NULL, \
	`timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP(), \
	`session_time` INT NOT NULL \
);";

char db_timePlayedInsert[] = "INSERT INTO `time_played` (`steam_id`, `total_time`, `session_time`) VALUES ('%s', IFNULL((SELECT `A`.`total_time` FROM (SELECT `total_time` + %d as `total_time` FROM `time_played` WHERE `steam_id` = '%s' ORDER BY `id` DESC LIMIT 1) as `A`), %d), %d);";
char db_timePlayedReset[] = "INSERT INTO `time_played` (`steam_id`, `total_time`, `session_time`) VALUES ('%s', 0, 0);";
char db_timePlayedSelect[] = "SELECT `total_time` FROM `time_played` WHERE `steam_id` = '%s' ORDER BY `id` DESC LIMIT 1;";

Database connectToDatabase()
{
	char error[255];
	Database db;
	
	if(SQL_CheckConfig("reserved_slots"))
	{
		db = SQL_Connect("reserved_slots", true, error, sizeof(error));
	}
	else
	{
		db = SQL_Connect("default", true, error, sizeof(error));
	}
	
	if(db == null)
	{
		LogError("Could not connect to database: %s", error);

		return db;
	}

	if(!db_createTableSuccess && !(SQL_FastQuery(db, db_createReserveUsage) && SQL_FastQuery(db, db_createTimePlayed)))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		delete db;
		return null;
	}

	db_createTableSuccess = true;
	
	return db;
}

bool InsertUsage(Database db, const char[] steamID, const char[] victimSteamID)
{
	char error[255];

	int queryStatementLength = sizeof(db_usageInsert) + strlen(steamID) + strlen(victimSteamID);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_usageInsert, steamID, victimSteamID);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

bool SelectUsage(Database db, const char[] steamID, int &available)
{
	char error[255];

	int queryStatementLength = sizeof(db_usageSelect) + 2 * strlen(steamID) + 20;
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_usageSelect, steamID, g_icvarCooldownTime, steamID, g_icvarCooldownTime);

	DBResultSet hQuery;

	if((hQuery = SQL_Query(db, queryStatement)) == null)
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	if(SQL_FetchRow(hQuery))
	{
		available = SQL_FetchInt(hQuery, 0);
	}

	delete hQuery;

	return true;
}

bool SelectNonDonorUsage(Database db, const char[] steamID, int &available)
{
	char error[255];

	int queryStatementLength = sizeof(db_usageNonDonorSelect) + 2 * strlen(steamID);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_usageNonDonorSelect, steamID, steamID);

	DBResultSet hQuery;

	if((hQuery = SQL_Query(db, queryStatement)) == null)
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	if(SQL_FetchRow(hQuery))
	{
		available = SQL_FetchInt(hQuery, 0);
	}

	delete hQuery;

	return true;
}

bool InsertTimePlayed(Database db, const char[] steamID, int time)
{
	char error[255];

	int queryStatementLength = sizeof(db_timePlayedInsert) + 2 * strlen(steamID) + 30;
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_timePlayedInsert, steamID, time, steamID, time, time);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

bool ResetTimePlayed(Database db, const char[] steamID)
{
	char error[255];

	int queryStatementLength = sizeof(db_timePlayedInsert) + strlen(steamID);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_timePlayedReset, steamID);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

bool SelectTimePlayed(Database db, const char[] steamID, int &time)
{
	char error[255];

	int queryStatementLength = sizeof(db_timePlayedSelect) + strlen(steamID);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_timePlayedSelect, steamID);

	DBResultSet hQuery;

	if((hQuery = SQL_Query(db, queryStatement)) == null)
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	if(SQL_FetchRow(hQuery))
	{
		time = SQL_FetchInt(hQuery, 0);
	}

	delete hQuery;

	return true;
}