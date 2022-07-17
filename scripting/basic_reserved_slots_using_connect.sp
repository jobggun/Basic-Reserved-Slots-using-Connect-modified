#include <sourcemod>
#include <clientprefs>
#include <connect>
#include <basic_reserved_slots_using_connect>

#pragma newdecls required
#pragma semicolon 1

#define _DEBUG

#define PLUGIN_VERSION "1.00"

bool g_bPlayerTickStartEnabled = false;
int g_iPlayerTickStartTime[MAXPLAYERS + 1] = { 0, ... };
int g_iCurrentValidPlayerCount = 0;

PrivateForward g_fwdFilter = null;

#include <basic_reserved_slots_using_connect/convar.sp>
#include <basic_reserved_slots_using_connect/database.sp>
#include <basic_reserved_slots_using_connect/filter.sp>
#include <basic_reserved_slots_using_connect/lateload.sp>
#include <basic_reserved_slots_using_connect/logging.sp>
#include <basic_reserved_slots_using_connect/tick.sp>
#include <basic_reserved_slots_using_connect/tracking.sp>

public Plugin myinfo = 
{
	name = "Basic Reserved Slots using Connect",
	author = "luki1412",
	description = "Simple plugin for reserved slots using Connect",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/member.php?u=43109"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("brsc");

	CreateNative("BRSC_AddFilter", Native_BRSC_AddFilter);

	SetLateLoad();
}

public int Native_BRSC_AddFilter(Handle plugin, int numParams)
{
	g_fwdFilter.AddFunction(plugin, GetNativeFunction(1));

	return 0;
}

public void OnPluginStart()
{
	SetUpConVars();
	SetUpTracking();
	SetUpFilter();

	HandleLateLoad();
}

public void OnPluginEnd()
{
	TerminateTracking();

	if(g_bPlayerTickStartEnabled)
	{
		Tick_Stop();
	}
}

public void OnClientPutInServer(int client)
{
	if(!IsValidClient(client))
		return;

	g_iCurrentValidPlayerCount += 1;

	if(g_iCurrentValidPlayerCount < g_icvarPlayerCountCondition)
		return;

	if(!g_bPlayerTickStartEnabled)
	{
		Tick_Start();
	}
	else
	{
		Tick_AddPlayer(client);
	}
}


public void OnClientDisconnect(int client)
{	
	if(!IsValidClient(client))
		return;
	
	g_iCurrentValidPlayerCount -= 1;

	if(!g_bPlayerTickStartEnabled)
		return;

	if(g_iCurrentValidPlayerCount >= g_icvarPlayerCountCondition)
	{
		Tick_RemovePlayer(client);
	}
	else
	{
		Tick_Stop();
	}
}

public bool OnClientPreConnectEx(const char[] name, char password[255], const char[] ip, const char[] steamID, char rejectReason[255])
{
	LogBRSCDebugMessage("[OnClientPreConnectEx] steamID: %s, GetClientCount(false): %d, GetClientCount(true): %d, MaxClients: %d", steamID, GetClientCount(false), GetClientCount(true), MaxClients);

	if (!GetConVarInt(g_hcvarEnabled))
	{
		LogBRSCDebugMessage("[OnClientPreConnectEx] Plugin Disabled");
		return true;
	}

	if (GetClientCount(false) < MaxClients)
	{
		LogBRSCDebugMessage("[OnClientPreConnectEx] GetClientCount(false) < MaxClients");
		return true;	
	}

	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, steamID);

	FilterState filter = Filter_Continue;

	Call_StartForward(g_fwdFilter);
	Call_PushString(steamID);
	Call_PushCell(admin);
	Call_PushCellRef(filter);
	int error = Call_Finish();

	if(error != SP_ERROR_NONE)
	{
		return true;
	}

	bool accessToReservation = filter == Filter_Accepted;

	if(accessToReservation)
	{
		LogBRSCMessage("Client with steamID '%s' used reservation slot", steamID);

		LogBRSCDebugMessage("[OnClientPreConnectEx] Finding client to be kicked...");

		int target = SelectKickClient();

		if(target)
		{
			LogBRSCDebugMessage("[OnClientPreConnectEx] Found client to be kicked");

			Database db = connectToDatabase();

			if(db != null)
			{
				char targetSteamID[32];
				GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID));

				LogBRSCDebugMessage("[OnClientPreConnectEx] Resetting the total play time of target player: %s...", targetSteamID);
				ResetTimePlayed(db, targetSteamID);

				LogBRSCDebugMessage("[OnClientPreConnectEx] Inserting the usage of reservation slots of player: (%s, %s)...", steamID, targetSteamID);
				InsertUsage(db, steamID, targetSteamID);

				delete db;
			}
			else
			{
				LogBRSCDebugMessage("[OnClientPreConnectEx] Database failed...");
			}

			char rReason[255];
			GetConVarString(g_hcvarReason, rReason, sizeof(rReason));
			LogBRSCDebugMessage("[OnClientPreConnectEx] Kicking target player...");

			if(!StrEqual(g_sRedirectionServerAddress, ""))
			{
				ClientCommand(target, "redirect %s", g_sRedirectionServerAddress);
			}

			KickClientEx(target, "%s", rReason);

			AddTracking(steamID);
		}
		else
		{
			LogBRSCDebugMessage("[OnClientPreConnectEx] Could not find client to be kicked");
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
	
	Database db = null;
	char steamID[32];
	int currentTime;

	int ikickType = GetConVarInt(g_hcvarKickType);
	LogBRSCDebugMessage("[SelectKickClient] Kick type convar int is %d", ikickType);

	if(ikickType == 3)
	{
		db = connectToDatabase();
		if(db == null)
		{
			ikickType = 2;
			LogBRSCDebugMessage("[SelectKickClient] DB failure, setting iKickType to %d", ikickType);
		}
		else
		{
			LogBRSCDebugMessage("[SelectKickClient] DB success");
		}
		currentTime = GetTime();
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		LogBRSCDebugMessage("[SelectKickClient] client num %d: ", i);

		if (!IsValidClient(i))
		{
			LogBRSCDebugMessage("[SelectKickClient] Not valid client ");
			continue;
		}
	
		int flags = GetUserFlagBits(i);
		
		if (IsFakeClient(i) || flags & ADMFLAG_ROOT || flags & ADMFLAG_GENERIC || CheckCommandAccess(i, "sm_reskick_immunity", ADMFLAG_GENERIC, false))
		{
			LogBRSCDebugMessage("[SelectKickClient] Client is root or generic admin ");

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

		LogBRSCDebugMessage("[SelectKickClient] kickPriority: %f", value);

		if (IsClientObserver(i))
		{
			LogBRSCDebugMessage("[SelectKickClient] Client is spectator");

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
		LogBRSCDebugMessage("[SelectKickClient] client who has highest priority is %d with value %f", highestSpecValueId, highestSpecValue);

		return highestSpecValueId;
	}

	LogBRSCDebugMessage("[SelectKickClient] client who has highest priority is %d with value %f", highestValueId, highestValue);
	
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
