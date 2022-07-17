// Plugin_Stop: Grants access
// Plugin_Continue: Keep continue to other function

enum FilterState
{
	Filter_Continue = 0,
	Filter_Accepted,
	Filter_Denied
};

void SetUpFilter()
{
	g_fwdFilter = new PrivateForward(ET_Hook, Param_String, Param_Cell, Param_CellByRef);

	g_fwdFilter.AddFunction(null, Filter_GenericAdmin);
	g_fwdFilter.AddFunction(null, Filter_ReservationUser);
	g_fwdFilter.AddFunction(null, Filter_ReservationToken);
}

Action Filter_GenericAdmin(const char[] steamID, AdminId admin, FilterState &state)
{
	if(GetAdminFlag(admin, Admin_Generic))
	{
		state = Filter_Accepted;	
		return Plugin_Stop;
	}

	return Plugin_Continue;	
}

Action Filter_ReservationUser(const char[] steamID, AdminId admin, FilterState &state)
{
	if(GetAdminFlag(admin, Admin_Reservation))
	{
		Database db = connectToDatabase();

		if(db == null)
		{
			state = Filter_Accepted;		
			return Plugin_Stop;
		}

		if(!checkIfUsageExceeded(db, steamID))
		{
			state = Filter_Accepted;
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

Action Filter_ReservationToken(const char[] steamID, AdminId admin, FilterState &state)
{
	Database db = connectToDatabase();

	if(db == null)
	{
		return Plugin_Continue;
	}

	if(checkNonDonorAllowed(db, steamID))
	{
		state = Filter_Accepted;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}