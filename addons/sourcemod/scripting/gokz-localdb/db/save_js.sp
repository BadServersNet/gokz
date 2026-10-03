public void OnLanding_SaveJumpstat(Jump jump)
{
	if (!gB_ClientSetUp[jump.jumper] || IsFakeClient(jump.jumper))
	{
		return;
	}

	int mode = GOKZ_GetCoreOption(jump.jumper, Option_Mode);
	
	if (!JS_IsSaveableJump(jump))
	{
		return;
	}

	DB_SaveJump(jump, mode, false);
	if (jump.block > 0)
	{
		DB_SaveJump(jump, mode, true);
	}
}

static bool JS_IsSaveableJump(Jump jump)
{
	if (jump.type == JumpType_Invalid || jump.type == JumpType_FullInvalid || jump.type == JumpType_Fall || jump.type == JumpType_Other)
	{
		return false;
	}
	if (jump.distance > JS_MAX_JUMP_DISTANCE)
	{
		return false;
	}
	if (jump.type == JumpType_LadderJump)
	{
		return jump.distance >= JS_MIN_LAJ_BLOCK_DISTANCE;
	}
	return jump.distance >= JS_MIN_BLOCK_DISTANCE && jump.offset >= -JS_OFFSET_EPSILON;
}

static void DB_SaveJump(Jump jump, int mode, bool blockJump)
{
	int steamid = GetSteamAccountID(jump.jumper);
	DataPack data = JSRecord_FillDataPack(jump, steamid, mode, blockJump);
	int distance = RoundToNearest(jump.distance * GOKZ_DB_JS_DISTANCE_PRECISION);
	int block = blockJump ? jump.block : 0;
	int sync = RoundToNearest(jump.sync * GOKZ_DB_JS_SYNC_PRECISION);
	int pre = RoundToNearest(jump.preSpeed * GOKZ_DB_JS_PRE_PRECISION);
	int max = RoundToNearest(jump.maxSpeed * GOKZ_DB_JS_MAX_PRECISION);
	int airtime = RoundToNearest(jump.duration * GetTickInterval() * GOKZ_DB_JS_AIRTIME_PRECISION);
	char query[1024];
	Transaction txn = SQL_CreateTransaction();
	if (g_DBType == DatabaseType_MySQL)
	{
		FormatEx(query, sizeof(query), "SELECT SteamID32 FROM Players WHERE SteamID32=%d FOR UPDATE", steamid);
	}
	else
	{
		FormatEx(query, sizeof(query), "SELECT SteamID32 FROM Players WHERE SteamID32=%d", steamid);
	}
	txn.AddQuery(query);
	if (g_DBType == DatabaseType_MySQL)
	{
		FormatEx(query, sizeof(query), mysql_jumpstats_getrecord, steamid, jump.type, mode, blockJump);
	}
	else
	{
		FormatEx(query, sizeof(query), sql_jumpstats_getrecord, steamid, jump.type, mode, blockJump);
	}
	txn.AddQuery(query);
	FormatEx(query, sizeof(query), sql_jumpstats_insert, steamid, jump.type, mode, distance, blockJump, block, jump.strafes, sync, pre, max, airtime);
	txn.AddQuery(query);
	DB_AddLastInsertIdQuery(txn);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_SaveJSRecord, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

static DataPack JSRecord_FillDataPack(Jump jump, int steamid, int mode, bool blockJump)
{
	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(jump.jumper));
	data.WriteCell(steamid);
	data.WriteCell(jump.type);
	data.WriteCell(mode);
	data.WriteCell(RoundToNearest(jump.distance * GOKZ_DB_JS_DISTANCE_PRECISION));
	data.WriteCell(blockJump ? jump.block : 0);
	data.WriteCell(jump.strafes);
	data.WriteCell(RoundToNearest(jump.sync * GOKZ_DB_JS_SYNC_PRECISION));
	data.WriteCell(RoundToNearest(jump.preSpeed * GOKZ_DB_JS_PRE_PRECISION));
	data.WriteCell(RoundToNearest(jump.maxSpeed * GOKZ_DB_JS_MAX_PRECISION));
	data.WriteCell(RoundToNearest(jump.duration * GetTickInterval() * GOKZ_DB_JS_AIRTIME_PRECISION));
	return data;
}

public void DB_TxnSuccess_SaveJSRecord(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	data.ReadCell();
	int jumpType = data.ReadCell();
	int mode = data.ReadCell();
	int distance = data.ReadCell();
	int block = data.ReadCell();
	int strafes = data.ReadCell();
	int sync = data.ReadCell();
	int pre = data.ReadCell();
	int max = data.ReadCell();
	int airtime = data.ReadCell();
	int jumpID = DB_ReadLastInsertId(results[3]);
	delete data;

	if (!IsValidClient(client) || GOKZ_JS_GetOption(client, JSOption_JumpstatsMaster) == JSToggleOption_Disabled)
	{
		return;
	}

	if (SQL_FetchRow(results[1]))
	{
		int previousDistance = SQL_FetchInt(results[1], JumpstatDB_Lookup_Distance);
		int previousBlock = SQL_FetchInt(results[1], JumpstatDB_Lookup_Block);
		bool improved = block > previousBlock || (block == previousBlock && distance > previousDistance);
		if (!improved)
		{
			return;
		}
	}

	float distanceFloat = float(distance) / GOKZ_DB_JS_DISTANCE_PRECISION;
	float syncFloat = float(sync) / GOKZ_DB_JS_SYNC_PRECISION;
	float preFloat = float(pre) / GOKZ_DB_JS_PRE_PRECISION;
	float maxFloat = float(max) / GOKZ_DB_JS_MAX_PRECISION;
	
	if (block == 0)
	{
		gI_PBJSCache[client][mode][jumpType][JumpstatDB_Cache_Distance] = distance;
		GOKZ_PrintToChat(client, true, "%t", "Jump Record", 
			client, 
			gC_JumpTypes[jumpType], 
			distanceFloat, 
			gC_ModeNamesShort[mode]);
	}
	else
	{
		gI_PBJSCache[client][mode][jumpType][JumpstatDB_Cache_Block] = block;
		gI_PBJSCache[client][mode][jumpType][JumpstatDB_Cache_BlockDistance] = distance;
		GOKZ_PrintToChat(client, true, "%t", "Block Jump Record", 
			client, 
			block, 
			gC_JumpTypes[jumpType], 
			distanceFloat, 
			gC_ModeNamesShort[mode], 
			block);
	}
	
	Call_OnJumpstatPB(client, jumpType, mode, distanceFloat, block, strafes, syncFloat, preFloat, maxFloat, airtime, jumpID);
}

public void DB_DeleteBestJump(int client, int steamAccountID, int jumpType, int mode, int isBlock)
{
	DataPack data = new DataPack();
	data.WriteCell(client == 0 ? -1 : GetClientUserId(client)); // -1 if called from server console
	data.WriteCell(steamAccountID);
	data.WriteCell(jumpType);
	data.WriteCell(mode);
	data.WriteCell(isBlock);
	
	char query[1024];
	
	if (g_DBType == DatabaseType_SQLite)
	{
		FormatEx(query, sizeof(query), sqlite_jumpstats_deleterecord, steamAccountID, jumpType, mode, isBlock);
	}
	else
	{
		FormatEx(query, sizeof(query), mysql_jumpstats_deleterecord, steamAccountID, jumpType, mode, isBlock);
	}
	
	Transaction txn = SQL_CreateTransaction();
	if (g_DBType == DatabaseType_MySQL)
	{
		char lockQuery[256];
		FormatEx(lockQuery, sizeof(lockQuery), "SELECT SteamID32 FROM Players WHERE SteamID32=%d FOR UPDATE", steamAccountID);
		txn.AddQuery(lockQuery);
	}
	txn.AddQuery(query);
	
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_BestJumpDeleted, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

public void DB_TxnSuccess_BestJumpDeleted(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	char blockString[16] = "";
	
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	int steamAccountID = data.ReadCell();
	int jumpType = data.ReadCell();
	int mode = data.ReadCell();
	bool isBlock = data.ReadCell() == 1;
	delete data;
	
	if (isBlock)
	{
		FormatEx(blockString, sizeof(blockString), "%T ", "Block", client);
	}
	
	ClearCache(client);
	
	GOKZ_PrintToChatAndLog(client, true, "%t", "Best Jump Deleted", 
		gC_ModeNames[mode], 
		blockString, 
		gC_JumpTypes[jumpType],
		steamAccountID & 1,
		steamAccountID >> 1);
}

public void DB_DeleteAllJumps(int client, int steamAccountID)
{
	DataPack data = new DataPack();
	data.WriteCell(client == 0 ? -1 : GetClientUserId(client)); // -1 if called from server console
	data.WriteCell(steamAccountID);
	
	char query[1024];
	
	if (g_DBType == DatabaseType_SQLite)
	{
		FormatEx(query, sizeof(query), sqlite_jumpstats_deleteallrecords, steamAccountID);
	}
	else
	{
		FormatEx(query, sizeof(query), mysql_jumpstats_deleteallrecords, steamAccountID);
	}
	
	Transaction txn = SQL_CreateTransaction();
	if (g_DBType == DatabaseType_MySQL)
	{
		char lockQuery[256];
		FormatEx(lockQuery, sizeof(lockQuery), "SELECT SteamID32 FROM Players WHERE SteamID32=%d FOR UPDATE", steamAccountID);
		txn.AddQuery(lockQuery);
	}
	txn.AddQuery(query);
	
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_AllJumpsDeleted, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

public void DB_TxnSuccess_AllJumpsDeleted(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	int steamAccountID = data.ReadCell();
	delete data;
	
	ClearCache(client);
	
	GOKZ_PrintToChatAndLog(client, true, "%t", "All Jumps Deleted", 
		steamAccountID & 1,
		steamAccountID >> 1);
}

public void DB_DeleteJump(int client, int jumpID)
{
	DataPack data = new DataPack();
	data.WriteCell(client == 0 ? -1 : GetClientUserId(client)); // -1 if called from server console
	data.WriteCell(jumpID);

	char query[1024];
	if (g_DBType == DatabaseType_SQLite)
	{
		FormatEx(query, sizeof(query), sqlite_jumpstats_deletejump, jumpID);
	}
	else
	{
		FormatEx(query, sizeof(query), mysql_jumpstats_deletejump, jumpID);
	}

	Transaction txn = SQL_CreateTransaction();
	if (g_DBType == DatabaseType_MySQL)
	{
		char lockQuery[256];
		FormatEx(lockQuery, sizeof(lockQuery), "SELECT SteamID32 FROM Players WHERE SteamID32=(SELECT SteamID32 FROM Jumpstats WHERE JumpID=%d FOR UPDATE) FOR UPDATE", jumpID);
		txn.AddQuery(lockQuery);
	}
	txn.AddQuery(query);

	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_JumpDeleted, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

public void DB_TxnSuccess_JumpDeleted(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	int jumpID = data.ReadCell();
	delete data;

	GOKZ_PrintToChatAndLog(client, true, "%t", "Jump Deleted", 
		jumpID);
}
