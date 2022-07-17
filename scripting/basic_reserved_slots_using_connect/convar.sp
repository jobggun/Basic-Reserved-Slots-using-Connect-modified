ConVar g_hcvarKickType;
ConVar g_hcvarEnabled;
ConVar g_hcvarReason;
ConVar g_hcvarCooldownTime;
ConVar g_hcvarPlayerCountCondition;
ConVar g_hcvarRedirectionServerAddress;

int g_icvarCooldownTime = 60;
int g_icvarPlayerCountCondition = 28;

char g_sRedirectionServerAddress[128] = "";

void SetUpConVars()
{
	CreateConVar("sm_brsc_version", PLUGIN_VERSION, "Basic Reserved Slots using Connect - version cvar", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hcvarEnabled = CreateConVar("sm_brsc_enabled", "1", "Enables/disables this plugin", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hcvarKickType = CreateConVar("sm_brsc_type", "1", "Who gets kicked out: 1 - Highest ping player, 2 - Longest connection time player, 3 - Longest time played in database, 0 - Random player", FCVAR_NONE, true, 0.0, true, 3.0);
	g_hcvarReason = CreateConVar("sm_brsc_reason", "Kicked to make room for an admin", "Reason used when kicking players", FCVAR_NONE);
	g_hcvarCooldownTime = CreateConVar("sm_brsc_cooldown_time", "60", "Cooldown time for re use of reservation slot", FCVAR_NONE);
	g_hcvarPlayerCountCondition = CreateConVar("sm_brsc_player_count", "28", "Minimum players count for kick player queue", FCVAR_NONE);
	g_hcvarRedirectionServerAddress = CreateConVar("sm_brsc_redirection_server_address", "", "Redirected server address for kicked players (\"\" for No redirection)", FCVAR_NONE);

	HookConVarChange(g_hcvarCooldownTime, ConVarCooldownTime);
	HookConVarChange(g_hcvarPlayerCountCondition, ConVarPlayerCountCondition);
	HookConVarChange(g_hcvarRedirectionServerAddress, ConVarRedirectionServerAddress);

	AutoExecConfig(true, "Basic_Reserved_Slots_using_Connect");
}

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
		Tick_Start();
	}
	else if(iOldValue < iNewValue && g_iCurrentValidPlayerCount < g_icvarPlayerCountCondition && g_bPlayerTickStartEnabled)
	{
		Tick_Stop();
	}
}

void ConVarRedirectionServerAddress(ConVar convar, const char[] oldValue, const char[] newValue)
{
	strcopy(g_sRedirectionServerAddress, sizeof(g_sRedirectionServerAddress), newValue);
}