/*
	Replays table queries: registering stored replays and looking them up for playback and menus.
*/



enum struct ReplayEntry
{
	int replayType;
	char objectKey[RP_MAX_KEY_LENGTH];
	int fileSize;
	bool inStore;
	char mapName[64];
	char alias[MAX_NAME_LENGTH];
	char created[32];
	char code[RP_CODE_BUFFER];
	int mode;
	int runTimeMS;
	int teleports;
	int course;
	int jumpType;
	int distance;
	int block;
	int strafes;
	int sync;
	int pre;
	int max;
	int rank;
}

enum struct ReplayMapEntry
{
	char name[64];
	int count;
}



// =====[ PUBLIC ]=====

void DB_InsertReplay(int replayType, int recordID, int steamID, const char[] objectKey, int fileSize, bool inStore, const char[] mapName, const char[] markerPath)
{
	DataPack data = new DataPack();
	data.WriteCell(replayType);
	data.WriteCell(recordID);
	data.WriteCell(steamID);
	data.WriteString(objectKey);
	data.WriteCell(fileSize);
	data.WriteCell(inStore);
	data.WriteString(mapName);
	data.WriteString(markerPath);
	data.WriteCell(1);
	InsertReplayAttempt(data);
}

void DB_LookupReplayByCode(int client, const char[] code)
{
	char codeEscaped[RP_CODE_BUFFER * 2 + 1];
	SQL_EscapeString(gH_DB, code, codeEscaped, sizeof(codeEscaped));
	char query[512];
	FormatEx(query, sizeof(query), sql_replays_getbycode, codeEscaped);
	LookupReplay(client, query);
}

void DB_PrintUrlForCode(int client, const char[] code)
{
	char codeEscaped[RP_CODE_BUFFER * 2 + 1];
	SQL_EscapeString(gH_DB, code, codeEscaped, sizeof(codeEscaped));
	char query[512];
	FormatEx(query, sizeof(query), sql_replays_getbycode, codeEscaped);

	DataPack data = new DataPack();
	data.WriteCell(client == 0 ? 0 : GetClientUserId(client));
	data.WriteCell(GetCmdReplySource());
	data.WriteString(code);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_PrintUrlForCode, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

void DB_LookupRunReplay(int client, int timeID)
{
	char query[512];
	FormatEx(query, sizeof(query), sql_replays_getbytime, timeID);
	LookupReplay(client, query);
}

void DB_LookupJumpReplay(int client, int jumpID)
{
	char query[512];
	FormatEx(query, sizeof(query), sql_replays_getbyjump, jumpID);
	LookupReplay(client, query);
}

void DB_FindReplayMap(int client, const char[] search, ReplayMenu kind)
{
	char searchEscaped[129];
	SQL_EscapeString(gH_DB, search, searchEscaped, sizeof(searchEscaped));
	char query[512];
	FormatEx(query, sizeof(query), sql_replays_findmap, searchEscaped, searchEscaped);

	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(client));
	data.WriteCell(kind);
	data.WriteString(search);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_FindReplayMap, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

void DB_OpenReplayMapMenu(int client, int steamID)
{
	char playerFilter[64];
	if (steamID != 0)
	{
		FormatEx(playerFilter, sizeof(playerFilter), " AND t.SteamID32=%d", steamID);
	}
	char query[1024];
	FormatEx(query, sizeof(query), sql_replays_getmaps, playerFilter, RP_MENU_MAP_COUNT);

	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(client));

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_ReplayMaps, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

void DB_OpenRunCourseMenu(int client, const char[] map, int mode)
{
	char mapEscaped[129];
	SQL_EscapeString(gH_DB, map, mapEscaped, sizeof(mapEscaped));
	char query[1024];
	FormatEx(query, sizeof(query), sql_replays_getcourses, mapEscaped, mode);

	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(client));

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_RunCourses, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

void DB_OpenRunList(int client, const char[] map, int mode, int course)
{
	char mapEscaped[129];
	SQL_EscapeString(gH_DB, map, mapEscaped, sizeof(mapEscaped));
	char query[4096];

	Transaction txn = SQL_CreateTransaction();
	FormatEx(query, sizeof(query), sql_replays_gettop, mapEscaped, course, mode, 1);
	txn.AddQuery(query);
	FormatEx(query, sizeof(query), sql_replays_gettoppro, mapEscaped, course, mode, 1);
	txn.AddQuery(query);
	FormatEx(query, sizeof(query), sql_replays_gettop, mapEscaped, course, mode, RP_MENU_LIST_COUNT);
	txn.AddQuery(query);
	ListReplayEntries(client, ReplayMenu_RunList, txn, 2);
}

void DB_OpenMyRunList(int client, int steamID, const char[] map, int mode, int course)
{
	char mapEscaped[129];
	SQL_EscapeString(gH_DB, map, mapEscaped, sizeof(mapEscaped));
	char query[4096];
	FormatEx(query, sizeof(query), sql_replays_getmine, steamID, mapEscaped, course, mode, RP_MENU_LIST_COUNT);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	ListReplayEntries(client, ReplayMenu_RunList, txn, 0);
}

void DB_OpenJumpList(int client, const char[] map, int mode, int jumpType)
{
	char mapFilter[192];
	FormatMapFilter(map, mapFilter, sizeof(mapFilter));
	char query[4096];
	FormatEx(query, sizeof(query), sql_replays_getjumps, jumpType, mode, mapFilter, RP_MENU_LIST_COUNT);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	ListReplayEntries(client, ReplayMenu_JumpList, txn, 0);
}

void DB_OpenRecentList(int client, const char[] map)
{
	char mapFilter[192];
	FormatMapFilter(map, mapFilter, sizeof(mapFilter));
	char query[4096];
	FormatEx(query, sizeof(query), sql_replays_getrecent, mapFilter, mapFilter, RP_MENU_LIST_COUNT);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	ListReplayEntries(client, ReplayMenu_RecentList, txn, 0);
}

void DB_LoadProgressRoute(const char[] map)
{
	char mapEscaped[129];
	SQL_EscapeString(gH_DB, map, mapEscaped, sizeof(mapEscaped));
	char query[4096];
	FormatEx(query, sizeof(query), sql_replays_getroute, mapEscaped, RP_PROGRESS_ROUTE_CANDIDATES);

	DataPack data = new DataPack();
	data.WriteString(map);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_ProgressRoute, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

void DB_LoadTimeDiffRoute(int client, const char[] map, int steamID, int mode)
{
	char mapEscaped[129];
	SQL_EscapeString(gH_DB, map, mapEscaped, sizeof(mapEscaped));
	char query[4096];
	FormatEx(query, sizeof(query), sql_replays_getpb, steamID, mapEscaped, mode, RP_PROGRESS_ROUTE_CANDIDATES);

	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(client));
	data.WriteString(map);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_TimeDiffRoute, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

void DB_LookupProgressReplay(int client, const char[] code)
{
	char codeEscaped[RP_CODE_BUFFER * 2 + 1];
	SQL_EscapeString(gH_DB, code, codeEscaped, sizeof(codeEscaped));
	char query[4096];
	FormatEx(query, sizeof(query), sql_replays_getruncode, codeEscaped);

	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(client));

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_ProgressReplay, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

void DB_PrintRecentReplayKeys(int client)
{
	char query[4096];
	FormatEx(query, sizeof(query), sql_replays_getrecent, "", "", RP_MENU_LIST_COUNT);

	DataPack data = new DataPack();
	data.WriteCell(client == 0 ? 0 : GetClientUserId(client));
	data.WriteCell(GetCmdReplySource());

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_PrintRecentReplayKeys, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}



// =====[ CALLBACKS ]=====

public void DB_TxnSuccess_InsertReplay(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int replayType = data.ReadCell();
	data.ReadCell();
	int steamID = data.ReadCell();
	char objectKey[RP_MAX_KEY_LENGTH];
	data.ReadString(objectKey, sizeof(objectKey));
	data.ReadCell();
	data.ReadCell();
	char mapName[64];
	data.ReadString(mapName, sizeof(mapName));
	char markerPath[PLATFORM_MAX_PATH];
	data.ReadString(markerPath, sizeof(markerPath));
	delete data;

	if (markerPath[0] != '\0' && FileExists(markerPath))
	{
		DeleteFile(markerPath);
	}

	Handle codeResult = results[numQueries - 1];
	if (!SQL_FetchRow(codeResult))
	{
		LogMessage("Registered replay \"%s\" (type %d) but no code was returned.", objectKey, replayType);
		return;
	}
	char code[RP_CODE_BUFFER];
	SQL_FetchString(codeResult, 0, code, sizeof(code));
	LogMessage("Registered replay \"%s\" (type %d, map %s, code %s).", objectKey, replayType, mapName, code);

	if (replayType != ReplayType_Run)
	{
		return;
	}
	AnnounceReplayCode(steamID, code);
}

public void DB_TxnFailure_InsertReplay(Handle db, DataPack data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	data.Reset();
	data.ReadCell();
	data.ReadCell();
	data.ReadCell();
	char objectKey[RP_MAX_KEY_LENGTH];
	data.ReadString(objectKey, sizeof(objectKey));
	data.ReadCell();
	data.ReadCell();
	char mapName[64];
	data.ReadString(mapName, sizeof(mapName));
	char markerPath[PLATFORM_MAX_PATH];
	data.ReadString(markerPath, sizeof(markerPath));
	int attempt = data.ReadCell();

	if (attempt >= RP_CODE_INSERT_ATTEMPTS)
	{
		delete data;
		LogError("Failed to register replay \"%s\" after %d attempts: %s", objectKey, attempt, error);
		return;
	}
	LogMessage("Registering replay \"%s\" failed on attempt %d, retrying: %s", objectKey, attempt, error);

	data.Reset();
	data.ReadCell();
	data.ReadCell();
	data.ReadCell();
	data.ReadString(objectKey, sizeof(objectKey));
	data.ReadCell();
	data.ReadCell();
	data.ReadString(mapName, sizeof(mapName));
	data.ReadString(markerPath, sizeof(markerPath));
	data.WriteCell(attempt + 1);
	InsertReplayAttempt(data);
}

public void DB_TxnSuccess_PrintUrlForCode(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int userid = data.ReadCell();
	ReplySource source = data.ReadCell();
	char code[RP_CODE_BUFFER];
	data.ReadString(code, sizeof(code));
	delete data;

	int client = userid == 0 ? 0 : GetClientOfUserId(userid);
	if (userid != 0 && !IsValidClient(client))
	{
		return;
	}
	if (!SQL_FetchRow(results[0]))
	{
		PrintToCaller(client, "[KZ] No replay has the code %s.", code);
		return;
	}

	char objectKey[RP_MAX_KEY_LENGTH];
	SQL_FetchString(results[0], ReplayDB_Lookup_ObjectKey, objectKey, sizeof(objectKey));
	PrintReplayUrl(client, source, objectKey);
}

public void DB_TxnSuccess_LookupReplay(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	delete data;

	if (!IsValidClient(client))
	{
		return;
	}
	if (!SQL_FetchRow(results[0]))
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Not Available");
		GOKZ_PlayErrorSound(client);
		Playback_OnFailed(client);
		return;
	}

	char objectKey[RP_MAX_KEY_LENGTH];
	SQL_FetchString(results[0], ReplayDB_Lookup_ObjectKey, objectKey, sizeof(objectKey));
	int fileSize = SQL_FetchInt(results[0], ReplayDB_Lookup_FileSize);
	bool inStore = SQL_FetchInt(results[0], ReplayDB_Lookup_InStore) != 0;
	RequestReplayPlayback(client, objectKey, fileSize, inStore);
}

public void DB_TxnSuccess_FindReplayMap(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	ReplayMenu kind = data.ReadCell();
	char search[64];
	data.ReadString(search, sizeof(search));
	delete data;

	if (!IsValidClient(client))
	{
		return;
	}
	if (!SQL_FetchRow(results[0]))
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Map Not Found", search);
		GOKZ_PlayErrorSound(client);
		return;
	}

	char map[64];
	SQL_FetchString(results[0], 0, map, sizeof(map));
	ReplayScope_SetMap(client, map);
	OpenReplayMenu(client, kind);
}

public void DB_TxnSuccess_ReplayMaps(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	delete data;

	if (!IsValidClient(client))
	{
		return;
	}

	ArrayList maps = new ArrayList(sizeof(ReplayMapEntry));
	while (SQL_FetchRow(results[0]))
	{
		ReplayMapEntry entry;
		SQL_FetchString(results[0], 0, entry.name, sizeof(ReplayMapEntry::name));
		entry.count = SQL_FetchInt(results[0], 1);
		maps.PushArray(entry);
	}
	DisplayReplayMapMenu(client, maps);
	delete maps;
}

public void DB_TxnSuccess_RunCourses(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	delete data;

	if (!IsValidClient(client))
	{
		return;
	}

	ArrayList courses = new ArrayList();
	while (SQL_FetchRow(results[0]))
	{
		int course = SQL_FetchInt(results[0], 0);
		if (GOKZ_IsValidCourse(course))
		{
			courses.Push(course);
		}
	}
	DisplayRunCourseMenu(client, courses);
	delete courses;
}

public void DB_TxnSuccess_ReplayEntries(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	ReplayMenu kind = data.ReadCell();
	int recordQueries = data.ReadCell();
	delete data;

	if (!IsValidClient(client))
	{
		return;
	}

	ArrayList entries = new ArrayList(sizeof(ReplayEntry));
	for (int i = 0; i < numQueries; i++)
	{
		ReadReplayEntries(results[i], entries);
	}
	int recordCount = CountRecordRows(results, recordQueries);
	if (IsDuplicateRecord(entries, recordCount))
	{
		entries.Erase(1);
		recordCount--;
	}
	RemoveRankedDuplicates(entries, recordCount);
	DisplayReplayEntries(client, kind, entries, recordCount);
	delete entries;
}

public void DB_TxnSuccess_ProgressRoute(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	char map[64];
	data.ReadString(map, sizeof(map));
	delete data;

	if (!StrEqual(map, gC_CurrentMap))
	{
		return;
	}

	ArrayList candidates = new ArrayList(sizeof(ReplayEntry));
	ReadReplayEntries(results[0], candidates);
	Progress_OnRouteCandidates(candidates);
	delete candidates;
}

public void DB_TxnSuccess_TimeDiffRoute(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	char map[64];
	data.ReadString(map, sizeof(map));
	delete data;

	if (!IsValidClient(client) || !StrEqual(map, gC_CurrentMap))
	{
		return;
	}

	ArrayList candidates = new ArrayList(sizeof(ReplayEntry));
	ReadReplayEntries(results[0], candidates);
	TimeDiff_OnPBCandidates(client, candidates);
	delete candidates;
}

public void DB_TxnSuccess_ProgressReplay(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	delete data;

	if (!IsValidClient(client))
	{
		return;
	}
	if (!SQL_FetchRow(results[0]))
	{
		GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Not A Run");
		GOKZ_PlayErrorSound(client);
		return;
	}

	ReplayEntry entry;
	ReadReplayEntry(results[0], entry);
	Progress_OnClientRouteReplay(client, entry);
}

public void DB_TxnSuccess_PrintRecentReplayKeys(Handle db, DataPack data, int numQueries, Handle[] results, any[] queryData)
{
	data.Reset();
	int userid = data.ReadCell();
	ReplySource source = data.ReadCell();
	delete data;

	int client = userid == 0 ? 0 : GetClientOfUserId(userid);
	if (userid != 0 && !IsValidClient(client))
	{
		return;
	}

	PrintToCaller(client, "[KZ] Recent replays (newest first). Use sm_replaystore_url <code> to get a download URL:");
	while (SQL_FetchRow(results[0]))
	{
		ReplayEntry entry;
		ReadReplayEntry(results[0], entry);
		PrintToCaller(client, "  %s   %s   %s   %s   %s", entry.code, entry.objectKey, entry.mapName, entry.alias, entry.created);
	}
	if (client != 0 && source == SM_REPLY_TO_CHAT)
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Store - Check Console");
	}
}

// =====[ PRIVATE ]=====

static void InsertReplayAttempt(DataPack data)
{
	data.Reset();
	int replayType = data.ReadCell();
	int recordID = data.ReadCell();
	int steamID = data.ReadCell();
	char objectKey[RP_MAX_KEY_LENGTH];
	data.ReadString(objectKey, sizeof(objectKey));
	int fileSize = data.ReadCell();
	bool inStore = data.ReadCell();
	char mapName[64];
	data.ReadString(mapName, sizeof(mapName));

	char timeIDValue[16] = "NULL";
	char jumpIDValue[16] = "NULL";
	char createdValue[128] = "CURRENT_TIMESTAMP";
	if (replayType == ReplayType_Run)
	{
		IntToString(recordID, timeIDValue, sizeof(timeIDValue));
		FormatEx(createdValue, sizeof(createdValue), sql_replays_created_from_time, recordID);
	}
	else if (replayType == ReplayType_Jump)
	{
		IntToString(recordID, jumpIDValue, sizeof(jumpIDValue));
		FormatEx(createdValue, sizeof(createdValue), sql_replays_created_from_jump, recordID);
	}

	char keyEscaped[RP_MAX_KEY_LENGTH * 2 + 1];
	SQL_EscapeString(gH_DB, objectKey, keyEscaped, sizeof(keyEscaped));
	char mapEscaped[129];
	SQL_EscapeString(gH_DB, mapName, mapEscaped, sizeof(mapEscaped));
	char code[RP_CODE_BUFFER];
	GenerateReplayCode(code, sizeof(code));

	char query[1024];
	Transaction txn = SQL_CreateTransaction();
	if (replayType == ReplayType_Jump)
	{
		FormatEx(query, sizeof(query), sql_replays_delete_by_jump, recordID);
		txn.AddQuery(query);
	}
	if (g_DBType == DatabaseType_SQLite)
	{
		FormatEx(query, sizeof(query), sqlite_replays_upsert, replayType, timeIDValue, jumpIDValue, steamID, keyEscaped, fileSize, inStore ? 1 : 0, mapEscaped, code, createdValue);
	}
	else
	{
		FormatEx(query, sizeof(query), mysql_replays_upsert, replayType, timeIDValue, jumpIDValue, steamID, keyEscaped, fileSize, inStore ? 1 : 0, mapEscaped, code, createdValue);
	}
	txn.AddQuery(query);
	FormatEx(query, sizeof(query), sql_replays_getcode, keyEscaped);
	txn.AddQuery(query);

	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_InsertReplay, DB_TxnFailure_InsertReplay, data, DBPrio_Normal);
}

static void AnnounceReplayCode(int steamID, const char[] code)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsValidClient(client) || IsFakeClient(client))
		{
			continue;
		}
		if (GetSteamAccountID(client) != steamID)
		{
			continue;
		}
		GOKZ_PrintToChat(client, true, "%t", "Replay Code", code);
		return;
	}
}

static int CountRecordRows(Handle[] results, int recordQueries)
{
	int count = 0;
	for (int i = 0; i < recordQueries; i++)
	{
		count += SQL_GetRowCount(results[i]);
	}
	return count;
}

static void RemoveRankedDuplicates(ArrayList entries, int recordCount)
{
	for (int i = entries.Length - 1; i >= recordCount; i--)
	{
		ReplayEntry ranked;
		entries.GetArray(i, ranked);
		if (IsRecordEntry(entries, recordCount, ranked))
		{
			entries.Erase(i);
		}
	}
}

static bool IsRecordEntry(ArrayList entries, int recordCount, ReplayEntry ranked)
{
	for (int i = 0; i < recordCount; i++)
	{
		ReplayEntry record;
		entries.GetArray(i, record);
		if (StrEqual(record.objectKey, ranked.objectKey))
		{
			return true;
		}
	}
	return false;
}

static bool IsDuplicateRecord(ArrayList entries, int recordCount)
{
	if (recordCount < 2)
	{
		return false;
	}
	ReplayEntry overall;
	entries.GetArray(0, overall);
	ReplayEntry pro;
	entries.GetArray(1, pro);
	return StrEqual(overall.objectKey, pro.objectKey);
}

static void ReadReplayEntries(Handle result, ArrayList entries)
{
	while (SQL_FetchRow(result))
	{
		ReplayEntry entry;
		ReadReplayEntry(result, entry);
		entries.PushArray(entry);
	}
}

static void ReadReplayEntry(Handle result, ReplayEntry entry)
{
	entry.replayType = SQL_FetchInt(result, ReplayDB_Entry_ReplayType);
	SQL_FetchString(result, ReplayDB_Entry_ObjectKey, entry.objectKey, sizeof(ReplayEntry::objectKey));
	entry.fileSize = SQL_FetchInt(result, ReplayDB_Entry_FileSize);
	entry.inStore = SQL_FetchInt(result, ReplayDB_Entry_InStore) != 0;
	SQL_FetchString(result, ReplayDB_Entry_MapName, entry.mapName, sizeof(ReplayEntry::mapName));
	SQL_FetchString(result, ReplayDB_Entry_Alias, entry.alias, sizeof(ReplayEntry::alias));
	SQL_FetchString(result, ReplayDB_Entry_Created, entry.created, sizeof(ReplayEntry::created));
	SQL_FetchString(result, ReplayDB_Entry_Code, entry.code, sizeof(ReplayEntry::code));
	entry.mode = SQL_FetchInt(result, ReplayDB_Entry_Mode);
	entry.runTimeMS = SQL_FetchInt(result, ReplayDB_Entry_RunTime);
	entry.teleports = SQL_FetchInt(result, ReplayDB_Entry_Teleports);
	entry.course = SQL_FetchInt(result, ReplayDB_Entry_Course);
	entry.jumpType = SQL_FetchInt(result, ReplayDB_Entry_JumpType);
	entry.distance = SQL_FetchInt(result, ReplayDB_Entry_Distance);
	entry.block = SQL_FetchInt(result, ReplayDB_Entry_Block);
	entry.strafes = SQL_FetchInt(result, ReplayDB_Entry_Strafes);
	entry.sync = SQL_FetchInt(result, ReplayDB_Entry_Sync);
	entry.pre = SQL_FetchInt(result, ReplayDB_Entry_Pre);
	entry.max = SQL_FetchInt(result, ReplayDB_Entry_Max);
	entry.rank = SQL_FetchInt(result, ReplayDB_Entry_Rank);
}

static void FormatMapFilter(const char[] map, char[] buffer, int maxlength)
{
	if (map[0] == '\0')
	{
		buffer[0] = '\0';
		return;
	}
	char mapEscaped[129];
	SQL_EscapeString(gH_DB, map, mapEscaped, sizeof(mapEscaped));
	FormatEx(buffer, maxlength, " AND r.MapName='%s'", mapEscaped);
}

static void ListReplayEntries(int client, ReplayMenu kind, Transaction txn, int recordQueries)
{
	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(client));
	data.WriteCell(kind);
	data.WriteCell(recordQueries);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_ReplayEntries, DB_TxnFailure_Generic_DataPack, data, DBPrio_Low);
}

static void LookupReplay(int client, const char[] query)
{
	DataPack data = new DataPack();
	data.WriteCell(GetClientUserId(client));

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_LookupReplay, DB_TxnFailure_Generic_DataPack, data, DBPrio_Normal);
}
