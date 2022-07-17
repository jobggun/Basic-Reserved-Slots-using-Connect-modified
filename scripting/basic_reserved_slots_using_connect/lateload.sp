static bool g_bLateLoad = false;

void SetLateLoad()
{
	g_bLateLoad = true;
}

void HandleLateLoad()
{
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