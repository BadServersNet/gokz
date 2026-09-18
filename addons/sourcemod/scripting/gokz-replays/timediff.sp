/*
	Time diff: while a player runs the main course, periodically tells them in chat
	how far ahead of or behind their own best replay they are at their current position.
*/



#define TIMEDIFF_OPTION_NAME "GOKZ Replays - Time Diff"
#define TIMEDIFF_OPTION_DESCRIPTION "Time Diff vs PB Replay - 0 = Disabled, 1 = Enabled"
#define TIMEDIFF_INTERVAL_OPTION_NAME "GOKZ Replays - Time Diff Interval"
#define TIMEDIFF_INTERVAL_OPTION_DESCRIPTION "Seconds between time diff messages (0 = a twentieth of your PB)"
#define TIMEDIFF_INTERVAL_MAX 120
#define TIMEDIFF_INTERVAL_MIN 1.0
#define TIMEDIFF_AUTO_DIVISOR 20.0
#define TIMEDIFF_AUTO_FALLBACK 5.0

enum
{
	TimeDiff_Disabled = 0,
	TimeDiff_Enabled,
	TIMEDIFF_COUNT
};

static const int intervalPresets[] = { 0, 5, 10, 15, 30, 60 };

static ArrayList pbRoute[MAXPLAYERS + 1];
static int pbRunTicks[MAXPLAYERS + 1];
static int pbTimeMS[MAXPLAYERS + 1];
static int pbLastIndex[MAXPLAYERS + 1];
static float sinceLastMessage[MAXPLAYERS + 1];
static TopMenu optionsTopMenu;
static TopMenuObject itemTimeDiff;
static TopMenuObject itemInterval;



// =====[ PUBLIC ]=====

void TimeDiff_Toggle(int client)
{
	bool enabled = GOKZ_GetOption(client, TIMEDIFF_OPTION_NAME) == TimeDiff_Enabled;
	GOKZ_SetOption(client, TIMEDIFF_OPTION_NAME, enabled ? TimeDiff_Disabled : TimeDiff_Enabled);
}

void TimeDiff_SetInterval(int client, int seconds)
{
	GOKZ_SetOption(client, TIMEDIFF_INTERVAL_OPTION_NAME, seconds);
	GOKZ_SetOption(client, TIMEDIFF_OPTION_NAME, TimeDiff_Enabled);
}

void TimeDiff_Disable(int client)
{
	GOKZ_SetOption(client, TIMEDIFF_OPTION_NAME, TimeDiff_Disabled);
}

void TimeDiff_OnPBCandidates(int client, ArrayList candidates)
{
	for (int i = 0; i < candidates.Length; i++)
	{
		ReplayEntry entry;
		candidates.GetArray(i, entry);
		char cachePath[PLATFORM_MAX_PATH];
		if (!Progress_IsReplayCached(entry, cachePath, sizeof(cachePath)))
		{
			continue;
		}
		LoadPBRoute(client, cachePath, entry.runTimeMS);
		return;
	}

	int downloadable = Progress_FindDownloadableCandidate(candidates, 0);
	if (downloadable == -1)
	{
		return;
	}
	ReplayEntry entry;
	candidates.GetArray(downloadable, entry);
	pbTimeMS[client] = entry.runTimeMS;
	Store_RequestRouteDownload(entry.objectKey, entry.fileSize, RouteDownload_PB, GetClientUserId(client));
}

void TimeDiff_OnPBDownloaded(int client, const char[] cachePath)
{
	LoadPBRoute(client, cachePath, pbTimeMS[client]);
}

void TimeDiff_OnRunReplaySaved(int client, int course, float time, const char[] cachePath)
{
	if (course != 0)
	{
		return;
	}
	int timeMS = GOKZ_DB_TimeFloatToInt(time);
	bool faster = !HasPBRoute(client) || timeMS < pbTimeMS[client];
	if (!faster)
	{
		return;
	}
	LoadPBRoute(client, cachePath, timeMS);
}



// =====[ EVENTS ]=====

void OnMapStart_TimeDiff()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		ClearPBRoute(client);
	}
	CreateTimer(1.0, Timer_TimeDiff, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void OnClientPutInServer_TimeDiff(int client)
{
	if (pbRoute[client] == null)
	{
		pbRoute[client] = new ArrayList(sizeof(RoutePoint));
	}
	ClearPBRoute(client);
	sinceLastMessage[client] = 0.0;
}

void OnClientDisconnect_TimeDiff(int client)
{
	ClearPBRoute(client);
}

void GOKZ_OnOptionsLoaded_TimeDiff(int client)
{
	RequestPBRoute(client);
}

void OnDatabaseConnect_TimeDiff()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidClient(client) && !IsFakeClient(client))
		{
			RequestPBRoute(client);
		}
	}
}

void GOKZ_OnOptionChanged_TimeDiff(int client, const char[] option, any newValue)
{
	if (StrEqual(option, gC_CoreOptionNames[Option_Mode]))
	{
		RequestPBRoute(client);
		return;
	}
	if (StrEqual(option, TIMEDIFF_OPTION_NAME))
	{
		sinceLastMessage[client] = 0.0;
		AnnounceToggle(client, newValue == TimeDiff_Enabled);
		return;
	}
	if (StrEqual(option, TIMEDIFF_INTERVAL_OPTION_NAME))
	{
		sinceLastMessage[client] = 0.0;
		AnnounceInterval(client);
	}
}

void GOKZ_OnTimerStart_TimeDiff(int client)
{
	sinceLastMessage[client] = 0.0;
	pbLastIndex[client] = 0;
}

void GOKZ_OnCountedTeleport_TimeDiff(int client)
{
	pbLastIndex[client] = -1;
}

void OnOptionsMenuReady_TimeDiff(TopMenu topMenu)
{
	GOKZ_RegisterOption(TIMEDIFF_OPTION_NAME, TIMEDIFF_OPTION_DESCRIPTION, OptionType_Int, TimeDiff_Disabled, 0, TIMEDIFF_COUNT - 1);
	GOKZ_RegisterOption(TIMEDIFF_INTERVAL_OPTION_NAME, TIMEDIFF_INTERVAL_OPTION_DESCRIPTION, OptionType_Int, 0, 0, TIMEDIFF_INTERVAL_MAX);

	if (optionsTopMenu == topMenu)
	{
		return;
	}
	optionsTopMenu = topMenu;
	TopMenuObject catGeneral = optionsTopMenu.FindCategory(GENERAL_OPTION_CATEGORY);
	itemTimeDiff = optionsTopMenu.AddItem(TIMEDIFF_OPTION_NAME, TopMenuHandler_TimeDiff, catGeneral);
	itemInterval = optionsTopMenu.AddItem(TIMEDIFF_INTERVAL_OPTION_NAME, TopMenuHandler_TimeDiffInterval, catGeneral);
}

public void TopMenuHandler_TimeDiff(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
	if (topobj_id != itemTimeDiff)
	{
		return;
	}
	if (action == TopMenuAction_DisplayOption)
	{
		bool enabled = GOKZ_GetOption(param, TIMEDIFF_OPTION_NAME) == TimeDiff_Enabled;
		FormatEx(buffer, maxlength, "%T - %T", "Options Menu - Time Diff", param, enabled ? "Options Menu - Enabled" : "Options Menu - Disabled", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		TimeDiff_Toggle(param);
		optionsTopMenu.Display(param, TopMenuPosition_LastCategory);
	}
}

public void TopMenuHandler_TimeDiffInterval(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
	if (topobj_id != itemInterval)
	{
		return;
	}
	if (action == TopMenuAction_DisplayOption)
	{
		char interval[32];
		FormatIntervalSetting(param, interval, sizeof(interval));
		FormatEx(buffer, maxlength, "%T - %s", "Options Menu - Time Diff Interval", param, interval);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		int next = GetNextIntervalPreset(GOKZ_GetOption(param, TIMEDIFF_INTERVAL_OPTION_NAME));
		GOKZ_SetOption(param, TIMEDIFF_INTERVAL_OPTION_NAME, next);
		optionsTopMenu.Display(param, TopMenuPosition_LastCategory);
	}
}

public Action Timer_TimeDiff(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsComparing(client))
		{
			continue;
		}
		sinceLastMessage[client] += 1.0;
		if (sinceLastMessage[client] + 0.001 < GetEffectiveInterval(client))
		{
			continue;
		}
		sinceLastMessage[client] = 0.0;
		PrintTimeDiff(client);
	}
	return Plugin_Continue;
}



// =====[ PRIVATE ]=====

static bool HasPBRoute(int client)
{
	return pbRoute[client] != null && pbRoute[client].Length > 0;
}

static void ClearPBRoute(int client)
{
	if (pbRoute[client] != null)
	{
		pbRoute[client].Clear();
	}
	pbRunTicks[client] = 0;
	pbTimeMS[client] = 0;
	pbLastIndex[client] = -1;
}

static void RequestPBRoute(int client)
{
	if (gH_DB == null || !IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}
	ClearPBRoute(client);
	int steamID = GetSteamAccountID(client);
	int mode = GOKZ_GetCoreOption(client, Option_Mode);
	DB_LoadTimeDiffRoute(client, gC_CurrentMap, steamID, mode);
}

static void LoadPBRoute(int client, const char[] cachePath, int runTimeMS)
{
	int runTicks;
	if (!Progress_LoadRoute(cachePath, pbRoute[client], runTicks))
	{
		return;
	}
	pbRunTicks[client] = runTicks;
	pbTimeMS[client] = runTimeMS;
}

static bool IsComparing(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client) || !HasPBRoute(client))
	{
		return false;
	}
	if (GOKZ_GetOption(client, TIMEDIFF_OPTION_NAME) != TimeDiff_Enabled)
	{
		return false;
	}
	bool running = GOKZ_GetTimerRunning(client) && !GOKZ_GetPaused(client) && GOKZ_GetCourse(client) == 0;
	return running && IsPlayerAlive(client);
}

static float GetEffectiveInterval(int client)
{
	int seconds = GOKZ_GetOption(client, TIMEDIFF_INTERVAL_OPTION_NAME);
	if (seconds > 0)
	{
		return float(seconds);
	}
	if (pbTimeMS[client] <= 0)
	{
		return TIMEDIFF_AUTO_FALLBACK;
	}
	float interval = float(pbTimeMS[client]) / 1000.0 / TIMEDIFF_AUTO_DIVISOR;
	return FloatMax(interval, TIMEDIFF_INTERVAL_MIN);
}

static int GetNextIntervalPreset(int current)
{
	for (int i = 0; i < sizeof(intervalPresets); i++)
	{
		if (intervalPresets[i] > current)
		{
			return intervalPresets[i];
		}
	}
	return intervalPresets[0];
}

static void FormatIntervalSetting(int client, char[] buffer, int maxlength)
{
	int seconds = GOKZ_GetOption(client, TIMEDIFF_INTERVAL_OPTION_NAME);
	if (seconds > 0)
	{
		FormatEx(buffer, maxlength, "%T", "Time Diff - Seconds", client, seconds);
		return;
	}
	FormatEx(buffer, maxlength, "%T", "Time Diff - Auto Interval", client);
}

static void AnnounceToggle(int client, bool enabled)
{
	if (!enabled)
	{
		GOKZ_PrintToChat(client, true, "%t", "Time Diff - Disabled");
		return;
	}
	char interval[32];
	FormatIntervalSetting(client, interval, sizeof(interval));
	GOKZ_PrintToChat(client, true, "%t", "Time Diff - Enabled", interval);
	if (!HasPBRoute(client))
	{
		GOKZ_PrintToChat(client, true, "%t", "Time Diff - No PB Replay");
	}
}

static void AnnounceInterval(int client)
{
	char interval[32];
	FormatIntervalSetting(client, interval, sizeof(interval));
	GOKZ_PrintToChat(client, true, "%t", "Time Diff - Interval Set", interval);
}

static void PrintTimeDiff(int client)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);
	int nearest = Progress_FindRoutePoint(pbRoute[client], origin, pbLastIndex[client]);
	pbLastIndex[client] = nearest;
	RoutePoint point;
	pbRoute[client].GetArray(nearest, point);
	float replayTime = float(point.tick) * GetTickInterval();
	float diff = GOKZ_GetTime(client) - replayTime;

	if (diff < -0.005)
	{
		GOKZ_PrintToChat(client, true, "%t", "Time Diff - Ahead", FloatAbs(diff));
		return;
	}
	if (diff > 0.005)
	{
		GOKZ_PrintToChat(client, true, "%t", "Time Diff - Behind", diff);
		return;
	}
	GOKZ_PrintToChat(client, true, "%t", "Time Diff - Even");
}
