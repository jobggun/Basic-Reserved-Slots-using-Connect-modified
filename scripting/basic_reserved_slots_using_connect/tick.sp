void Tick_Start()
{
	g_bPlayerTickStartEnabled = true;

	int currentTime = GetTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		g_iPlayerTickStartTime[i] = currentTime;
	}
}

void Tick_Stop()
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
        {
			continue;
        }

		time_played = currentTime - g_iPlayerTickStartTime[i];

		g_iPlayerTickStartTime[i] = 0;

		if(!GetClientAuthId(i, AuthId_Steam2, steamID, sizeof(steamID)))
        {
            continue;
        }

		InsertTimePlayed(db, steamID, time_played);
	}

	delete db;
}

void Tick_AddPlayer(int client)
{
	g_iPlayerTickStartTime[client] = GetTime();
}

void Tick_RemovePlayer(int client)
{
	int time_played;
	char steamID[32];

	int currentTime = GetTime();

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