char db_createReserveUsage[] = "CREATE TABLE IF NOT EXISTS `reserved_slots_usage` ( \
	`id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, \
	`steam_id` VARCHAR(32) NOT NULL, \
	`victim_steam_id` VARCHAR(32) NOT NULL, \
	`timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP() \
);";

char db_usageInsert[] = "INSERT INTO `reserved_slots_usage` (`steam_id`, `victim_steam_id`) VALUES ('%s', '%s');";
char db_usageSelect[] = "SELECT NOT EXISTS(SELECT 1 FROM `reserved_slots_usage` WHERE `steam_id` = '%s' GROUP BY `steam_id` HAVING MAX(`timestamp`) >= NOW() - INTERVAL %d MINUTE) AND NOT EXISTS(SELECT 1 FROM `reserved_slots_usage` WHERE `victim_steam_id` = '%s' GROUP BY `victim_steam_id` HAVING MAX(`timestamp`) >= NOW() - INTERVAL %d MINUTE);";
char db_usageNonDonorSelect[] = "SELECT (SELECT COUNT(*) FROM `reserved_slots_usage` WHERE `victim_steam_id` = '%s' AND `steam_id` != `victim_steam_id` AND TIMESTAMPDIFF(DAY, `timestamp`, CURRENT_TIMESTAMP()) < 2) - 2 * (SELECT COUNT(*) FROM `reserved_slots_usage` WHERE `steam_id` = '%s' AND `steam_id` != `victim_steam_id` AND TIMESTAMPDIFF(DAY, `timestamp`, CURRENT_TIMESTAMP()) < 2) >= 2;";

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
	static bool db_createTableSuccess = false;

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