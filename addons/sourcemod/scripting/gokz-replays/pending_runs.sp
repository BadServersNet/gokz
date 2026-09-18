/*
	Matches a written run replay with the TimeID that gokz-localdb assigned to the run.
	Whichever of the two arrives second finalizes the replay.
*/



enum struct PendingRun
{
	int userid;
	int course;
	int mode;
	int style;
	int runTimeMS;
	int teleportsUsed;
	float time;
	bool hasTimeID;
	int timeID;
	bool hasFile;
	char stagingPath[PLATFORM_MAX_PATH];
	Handle expiryTimer;
}

static ArrayList g_PendingRuns;



// =====[ PUBLIC ]=====

void PendingRuns_OnTimeInserted(int client, int course, int mode, int style, int runTimeMS, int timeID)
{
	int userid = GetClientUserId(client);
	int index = FindPendingRun(userid, course, mode, style, runTimeMS);
	if (index == -1)
	{
		PendingRun run;
		run.userid = userid;
		run.course = course;
		run.mode = mode;
		run.style = style;
		run.runTimeMS = runTimeMS;
		run.hasTimeID = true;
		run.timeID = timeID;
		run.expiryTimer = CreateExpiryTimer(userid, course, mode, style, runTimeMS);
		g_PendingRuns.PushArray(run);
		return;
	}

	PendingRun run;
	g_PendingRuns.GetArray(index, run);
	run.hasTimeID = true;
	run.timeID = timeID;
	g_PendingRuns.SetArray(index, run);
	FinalizeRun(index);
}

void PendingRuns_OnFileWritten(int client, int course, int mode, int style, float time, int teleportsUsed, const char[] stagingPath)
{
	int userid = GetClientUserId(client);
	int runTimeMS = GOKZ_DB_TimeFloatToInt(time);
	int index = FindPendingRun(userid, course, mode, style, runTimeMS);
	if (index == -1)
	{
		PendingRun run;
		run.userid = userid;
		run.course = course;
		run.mode = mode;
		run.style = style;
		run.runTimeMS = runTimeMS;
		run.teleportsUsed = teleportsUsed;
		run.time = time;
		run.hasFile = true;
		strcopy(run.stagingPath, sizeof(PendingRun::stagingPath), stagingPath);
		run.expiryTimer = CreateExpiryTimer(userid, course, mode, style, runTimeMS);
		g_PendingRuns.PushArray(run);
		return;
	}

	PendingRun run;
	g_PendingRuns.GetArray(index, run);
	run.teleportsUsed = teleportsUsed;
	run.time = time;
	run.hasFile = true;
	strcopy(run.stagingPath, sizeof(PendingRun::stagingPath), stagingPath);
	g_PendingRuns.SetArray(index, run);
	FinalizeRun(index);
}



// =====[ EVENTS ]=====

void OnPluginStart_PendingRuns()
{
	g_PendingRuns = new ArrayList(sizeof(PendingRun));
}

void OnMapEnd_PendingRuns()
{
	for (int i = 0; i < g_PendingRuns.Length; i++)
	{
		KillExpiryTimer(i);
	}
	g_PendingRuns.Clear();
}

void OnClientDisconnect_PendingRuns(int client)
{
	int userid = GetClientUserId(client);
	for (int i = g_PendingRuns.Length - 1; i >= 0; i--)
	{
		PendingRun run;
		g_PendingRuns.GetArray(i, run);
		if (run.userid != userid)
		{
			continue;
		}
		KillExpiryTimer(i);
		g_PendingRuns.Erase(i);
	}
}

public Action Timer_PendingRunExpired(Handle timer, DataPack data)
{
	data.Reset();
	int userid = data.ReadCell();
	int course = data.ReadCell();
	int mode = data.ReadCell();
	int style = data.ReadCell();
	int runTimeMS = data.ReadCell();
	delete data;

	int index = FindPendingRun(userid, course, mode, style, runTimeMS);
	if (index == -1)
	{
		return Plugin_Stop;
	}

	PendingRun run;
	g_PendingRuns.GetArray(index, run);
	run.expiryTimer = INVALID_HANDLE;
	g_PendingRuns.SetArray(index, run);
	ExpireRun(index);
	return Plugin_Stop;
}



// =====[ PRIVATE ]=====

static int FindPendingRun(int userid, int course, int mode, int style, int runTimeMS)
{
	for (int i = 0; i < g_PendingRuns.Length; i++)
	{
		PendingRun run;
		g_PendingRuns.GetArray(i, run);
		bool sameRun = run.userid == userid && run.course == course && run.mode == mode && run.style == style && run.runTimeMS == runTimeMS;
		if (sameRun)
		{
			return i;
		}
	}
	return -1;
}

static Handle CreateExpiryTimer(int userid, int course, int mode, int style, int runTimeMS)
{
	DataPack data = new DataPack();
	data.WriteCell(userid);
	data.WriteCell(course);
	data.WriteCell(mode);
	data.WriteCell(style);
	data.WriteCell(runTimeMS);
	return CreateTimer(RP_TIMEID_WAIT_TIME, Timer_PendingRunExpired, data);
}

static void KillExpiryTimer(int index)
{
	PendingRun run;
	g_PendingRuns.GetArray(index, run);
	if (run.expiryTimer == INVALID_HANDLE)
	{
		return;
	}
	KillTimer(run.expiryTimer);
	run.expiryTimer = INVALID_HANDLE;
	g_PendingRuns.SetArray(index, run);
}

static void FinalizeRun(int index)
{
	PendingRun run;
	g_PendingRuns.GetArray(index, run);
	KillExpiryTimer(index);
	g_PendingRuns.Erase(index);

	int client = GetClientOfUserId(run.userid);
	if (!IsValidClient(client))
	{
		return;
	}

	if (run.timeID <= 0)
	{
		LogError("Run replay for %N could not be stored because no TimeID was assigned.", client);
		FireReplaySavedForwards(client, run, run.stagingPath);
		return;
	}

	char key[RP_MAX_KEY_LENGTH];
	FormatRunKey(key, sizeof(key), gC_CurrentMap, run.timeID);
	char cachePath[PLATFORM_MAX_PATH];
	KeyToCachePath(key, cachePath, sizeof(cachePath));
	EnsureDirectoryForPath(cachePath);
	if (!RenameFile(cachePath, run.stagingPath))
	{
		LogError("Failed to move replay \"%s\" to \"%s\".", run.stagingPath, cachePath);
		FireReplaySavedForwards(client, run, run.stagingPath);
		return;
	}

	int steamID = GetSteamAccountID(client);
	Store_EnqueueUpload(key, ReplayType_Run, run.timeID, steamID, gC_CurrentMap);
	Progress_OnRunReplaySaved(client, run.course, run.time, cachePath);
	FireReplaySavedForwards(client, run, cachePath);
}

static void ExpireRun(int index)
{
	PendingRun run;
	g_PendingRuns.GetArray(index, run);
	g_PendingRuns.Erase(index);

	int client = GetClientOfUserId(run.userid);
	if (!IsValidClient(client))
	{
		return;
	}
	if (!run.hasFile)
	{
		return;
	}

	LogError("Run replay for %N was not matched with a TimeID within %.0f seconds; it will not be stored.", client, RP_TIMEID_WAIT_TIME);
	FireReplaySavedForwards(client, run, run.stagingPath);
}

static void FireReplaySavedForwards(int client, PendingRun run, const char[] filePath)
{
	int timeType = GOKZ_GetTimeTypeEx(run.teleportsUsed);
	Call_OnReplaySaved(client, ReplayType_Run, gC_CurrentMap, run.course, timeType, run.time, filePath);
	Call_OnTimerEnd_Post(client, filePath, run.course, run.time, run.teleportsUsed);
}
