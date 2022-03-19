#include <sourcemod>

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
forward bool OnClientPreConnectEx(const char[] name, char password[255], const char[] ip, const char[] steamID, char rejectReason[255]);

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
	g_hcvarKickType = CreateConVar("sm_brsc_type", "1", "Who gets kicked out: 1 - Highest ping player, 2 - Longest connection time player, 3 - Random player", FCVAR_NONE, true, 1.0, true, 3.0);
	g_hcvarReason = CreateConVar("sm_brsc_reason", "Kicked to make room for an admin", "Reason used when kicking players", FCVAR_NONE);
	
	SetConVarString(g_hcvarVer, PLUGIN_VERSION);	
	AutoExecConfig(true, "Basic_Reserved_Slots_using_Connect");
}

public bool OnClientPreConnectEx(const char[] name, char password[255], const char[] ip, const char[] steamID, char rejectReason[255])
{
	if (!GetConVarInt(g_hcvarEnabled))
	{
		return true;
	}

	if (GetClientCount(false) < MaxClients)
	{
		return true;	
	}

	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, steamID);
	
	if (admin == INVALID_ADMIN_ID)
	{
		return true;
	}

	bool kickCondition = false;

	if (GetAdminFlag(admin, Admin_Generic))
	{
		kickCondition = true;
	}
	
	if (!kickCondition && GetAdminFlag(admin, Admin_Reservation))
	{
		Database db = connectToDatabase();

		if(db != null)
		{
			kickCondition = !checkIfUsageExceeded(db, steamID);
			delete db;
		}
	}

	if(kickCondition)
	{
		int target = SelectKickClient();
		
		if (target)
		{
			char rReason[255];
			GetConVarString(g_hcvarReason, rReason, sizeof(rReason));
			KickClientEx(target, "%s", rReason);
		}
	}
	
	return true;
}

int SelectKickClient()
{	
	float highestValue;
	int highestValueId;
	
	float highestSpecValue;
	int highestSpecValueId;
	
	bool specFound;
	
	float value;
	
	for (int i = 1; i <= MaxClients; i++)
	{	
		if (!IsValidClient(i))
		{
			continue;
		}
	
		int flags = GetUserFlagBits(i);
		
		if (IsFakeClient(i) || flags & ADMFLAG_ROOT || flags & ADMFLAG_RESERVATION || CheckCommandAccess(i, "sm_reskick_immunity", ADMFLAG_RESERVATION, false))
		{
			continue;
		}
		
		value = 0.0;
		
		switch(GetConVarInt(g_hcvarKickType))
		{
			case 1:
			{
				value = GetClientAvgLatency(i, NetFlow_Outgoing);
			}
			case 2:
			{
				value = GetClientTime(i);
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
	
	if (specFound)
	{
		return highestSpecValueId;
	}
	
	return highestValueId;
}

stock bool IsValidClient(int client, bool replaycheck=true)
{
	if(client<=0 || client>MaxClients)
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
	int usage = 0;
	int expired = 0;

	if(!InsertUsage(db, steamID)) return false;
	if(!SelectUsage(db, steamID, usage, expired)) return false;

	if(expired)
	{
		UpdateUsage(db, steamID, 1);
	}
	else if(usage >= 3)
	{
		return true;
	}
	else
	{
		UpdateUsage(db, steamID, usage + 1);
	}

	return false;
}

// DB

bool db_createTableSuccess = false;

char db_createReserveUsage[] = "CREATE TABLE IF NOT EXISTS `vip_reserved` ( \
	`steam_id` varchar(256) NOT NULL, \
	`usage` int NOT NULL, \
	`timestamp` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(), \
	PRIMARY KEY (`steam_id`) \
);";

char db_usageInsert[] = "INSERT IGNORE INTO `vip_reserved` (`steam_id`, `usage`) VALUES ('%s', 0);";
char db_usageSelect[] = "SELECT `usage`, (`timestamp` < current_date()) AS `expired` FROM `vip_reserved` WHERE `steam_id` = '%s';";
char db_usageUpdate[] = "UPDATE `vip_reserved` SET `usage` = %d WHERE `steam_id` = '%s';";

Database connectToDatabase()
{
	char error[255];
	Database db;
	
	if(SQL_CheckConfig("vip_reserved"))
	{
		db = SQL_Connect("vip_reserved", true, error, sizeof(error));
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

	if(!db_createTableSuccess && !SQL_FastQuery(db, db_createReserveUsage))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		delete db;
		return null;
	}

	db_createTableSuccess = true;
	
	return db;
}

bool InsertUsage(Database db, const char[] steamID)
{
	char error[255];

	int queryStatementLength = sizeof(db_usageInsert) + strlen(steamID);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_usageInsert, steamID);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

bool SelectUsage(Database db, const char[] steamID, int &usage, int &expired)
{
	char error[255];

	int queryStatementLength = sizeof(db_usageSelect) + strlen(steamID);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_usageSelect, steamID);

	DBResultSet hQuery;

	if((hQuery = SQL_Query(db, queryStatement)) == null)
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	if(SQL_FetchRow(hQuery))
	{
		usage = SQL_FetchInt(hQuery, 0);
		expired = SQL_FetchInt(hQuery, 1);
	}

	delete hQuery;

	return true;
}

bool UpdateUsage(Database db, const char[] steamID, int usage)
{
	char error[255];

	int queryStatementLength = sizeof(db_usageUpdate) + strlen(steamID);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_usageUpdate, usage, steamID);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}