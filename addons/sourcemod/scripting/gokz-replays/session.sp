static int sessionType[MAXPLAYERS + 1];
static int sessionState[MAXPLAYERS + 1];
static int sessionToken[MAXPLAYERS + 1];
static int sessionBot[MAXPLAYERS + 1];
static float sessionLoadStart[MAXPLAYERS + 1];
static char sessionCachePath[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
static ArrayList sessionRoute[MAXPLAYERS + 1];
static int sessionRunTicks[MAXPLAYERS + 1];
static int sessionRouteHint[MAXPLAYERS + 1];
static char sessionAlias[MAXPLAYERS + 1][MAX_NAME_LENGTH];
static int sessionRunTimeMS[MAXPLAYERS + 1];
static int sessionTeleports[MAXPLAYERS + 1];
static float sessionPlayerProgress[MAXPLAYERS + 1];
static bool sessionHasTimeDiff[MAXPLAYERS + 1];
static float sessionTimeDiff[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void Session_Command(int client, int type, int args)
{
	if (!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}
	if (args < 1)
	{
		Session_Toggle(client, type);
		return;
	}

	char input[32];
	GetCmdArg(1, input, sizeof(input));
	char code[RP_CODE_BUFFER];
	if (!NormalizeReplayCode(input, code, sizeof(code)))
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Code Invalid");
		GOKZ_PlayErrorSound(client);
		return;
	}
	Session_Request(client, type, code);
}

void Session_Toggle(int client, int type)
{
	if (sessionType[client] == type)
	{
		Session_Stop(client, true);
		return;
	}
	Session_Request(client, type, "");
}

void Session_Request(int client, int type, const char[] code)
{
	if (!CanStartSession(client, type))
	{
		return;
	}

	Session_Stop(client, false);
	sessionType[client] = type;
	sessionState[client] = ReplaySessionState_Loading;
	sessionLoadStart[client] = GetGameTime();

	if (code[0] == '\0')
	{
		DB_LoadSessionCandidates(client, sessionToken[client], gC_CurrentMap);
		return;
	}
	DB_LookupSessionReplay(client, sessionToken[client], code);
}

void Session_RequestEntry(int client, int type, ReplayEntry entry)
{
	if (!CanStartSession(client, type))
	{
		return;
	}

	Session_Stop(client, false);
	sessionType[client] = type;
	sessionState[client] = ReplaySessionState_Loading;
	sessionLoadStart[client] = GetGameTime();
	Session_OnReplayEntry(client, sessionToken[client], entry);
}

void Session_Stop(int client, bool announce)
{
	int type = sessionType[client];
	if (type == ReplaySession_None)
	{
		return;
	}
	int bot = sessionBot[client];
	ResetSession(client);
	if (bot != -1)
	{
		Playback_CancelBot(bot);
	}
	if (!announce)
	{
		return;
	}
	GOKZ_PrintToChat(client, true, "%t", type == ReplaySession_Lead ? "Lead - Stopped" : "Race - Stopped");
}

int Session_GetType(int client)
{
	return sessionType[client];
}

int Session_GetState(int client)
{
	return sessionState[client];
}

void Session_SetState(int client, int state)
{
	sessionState[client] = state;
}

int Session_GetBot(int client)
{
	return sessionBot[client];
}

int Session_GetBotClient(int client)
{
	return Playback_GetBotClient(sessionBot[client]);
}

float Session_GetRunTime(int client)
{
	return GOKZ_DB_TimeIntToFloat(sessionRunTimeMS[client]);
}

void Session_GetAlias(int client, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, sessionAlias[client]);
}

void Session_FormatRunTime(int client, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, GOKZ_FormatTime(Session_GetRunTime(client)));
}

void Session_FormatTimeType(int client, char[] buffer, int maxlength)
{
	int timeType = GOKZ_GetTimeTypeEx(sessionTeleports[client]);
	strcopy(buffer, maxlength, gC_TimeTypeNames[timeType]);
}

int Session_FindNearestTick(int client)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);
	int nearest = Progress_FindRoutePoint(sessionRoute[client], origin, -1);
	sessionRouteHint[client] = nearest;
	RoutePoint point;
	sessionRoute[client].GetArray(nearest, point);
	return point.tick + Playback_GetRunStartTick();
}

void Session_ResetRouteHint(int client)
{
	sessionRouteHint[client] = -1;
}

float Session_GetBotProgress(int client)
{
	int bot = sessionBot[client];
	int runTicks = sessionRunTicks[client];
	if (bot == -1 || runTicks <= 0)
	{
		return 0.0;
	}
	int elapsed = Playback_GetTick(bot) - Playback_GetRunStartTick();
	float progress = float(elapsed) / float(runTicks);
	return FloatMax(0.0, FloatMin(progress, 1.0));
}

bool Session_GetInfo(int client, ReplaySessionInfo info)
{
	if (!IsValidClient(client) || sessionType[client] == ReplaySession_None)
	{
		return false;
	}
	info.type = sessionType[client];
	info.state = sessionState[client];
	strcopy(info.alias, sizeof(ReplaySessionInfo::alias), sessionAlias[client]);
	info.runTime = Session_GetRunTime(client);
	info.playerProgress = sessionPlayerProgress[client];
	info.botProgress = Session_GetBotProgress(client);
	info.hasTimeDiff = sessionHasTimeDiff[client];
	info.timeDiff = sessionTimeDiff[client];
	if (info.type == ReplaySession_Race)
	{
		Race_FillInfo(client, info);
	}
	return true;
}

void Session_OnCandidates(int client, int token, ArrayList candidates)
{
	if (!IsLoadingToken(client, token))
	{
		return;
	}
	for (int i = 0; i < candidates.Length; i++)
	{
		ReplayEntry entry;
		candidates.GetArray(i, entry);
		char cachePath[PLATFORM_MAX_PATH];
		if (Progress_IsReplayCached(entry, cachePath, sizeof(cachePath)))
		{
			Session_OnReplayEntry(client, token, entry);
			return;
		}
	}

	int downloadable = Progress_FindDownloadableCandidate(candidates, 0);
	if (downloadable == -1)
	{
		FailSession(client, "Session - No Replay");
		return;
	}
	ReplayEntry entry;
	candidates.GetArray(downloadable, entry);
	Session_OnReplayEntry(client, token, entry);
}

void Session_OnReplayNotFound(int client, int token)
{
	if (!IsLoadingToken(client, token))
	{
		return;
	}
	FailSession(client, "Session - Not A Run");
}

void Session_OnReplayEntry(int client, int token, ReplayEntry entry)
{
	if (!IsLoadingToken(client, token))
	{
		return;
	}
	if (!StrEqual(entry.mapName, gC_CurrentMap, false))
	{
		GOKZ_PrintToChat(client, true, "%t", "Session - Wrong Map", entry.mapName);
		FailSession(client, "");
		return;
	}
	if (entry.replayType != ReplayType_Run || entry.course != 0)
	{
		FailSession(client, "Session - Wrong Course");
		return;
	}

	strcopy(sessionAlias[client], sizeof(sessionAlias[]), entry.alias);
	sessionRunTimeMS[client] = entry.runTimeMS;
	sessionTeleports[client] = entry.teleports;
	KeyToCachePath(entry.objectKey, sessionCachePath[client], sizeof(sessionCachePath[]));

	char cachePath[PLATFORM_MAX_PATH];
	if (Progress_IsReplayCached(entry, cachePath, sizeof(cachePath)))
	{
		StartSessionBot(client, cachePath);
		return;
	}
	if (!entry.inStore || !Store_IsReady())
	{
		FailSession(client, "Session - Unavailable");
		return;
	}
	GOKZ_PrintToChat(client, true, "%t", sessionType[client] == ReplaySession_Lead ? "Lead - Loading" : "Race - Loading", entry.alias);
	Store_RequestDownload(client, entry.objectKey, entry.fileSize);
}

bool Session_OnReplayCached(int client, const char[] cachePath)
{
	if (!IsAwaitingDownload(client) || !StrEqual(cachePath, sessionCachePath[client]))
	{
		return false;
	}
	StartSessionBot(client, cachePath);
	return true;
}

bool Session_OnDownloadFailed(int client)
{
	if (!IsAwaitingDownload(client))
	{
		return false;
	}
	FailSession(client, "");
	return true;
}

bool Session_ClaimsBot(int bot)
{
	return FindSlotOwner(bot) != 0;
}

void Session_OnBotJoined(int bot, int botClient)
{
	if (FindSlotOwner(bot) == 0)
	{
		return;
	}
	Playback_SetPaused(bot, true);
	SDKHook(botClient, SDKHook_SetTransmit, Hook_SessionBotTransmit);
}

void Session_OnBotLeft(int bot)
{
	int owner = FindSlotOwner(bot);
	if (owner == 0)
	{
		return;
	}
	ResetSession(owner);
	GOKZ_PrintToChat(owner, true, "%t", "Session - Bot Left");
	GOKZ_PlayErrorSound(owner);
}

bool Session_IsBotOwned(int bot)
{
	return FindSlotOwner(bot) != 0;
}

int Session_GetBotOwner(int botClient)
{
	if (!IsValidClient(botClient) || !IsFakeClient(botClient))
	{
		return 0;
	}
	int bot = GetBotFromClient(botClient);
	if (bot == -1 || !Playback_IsBotInGame(bot))
	{
		return 0;
	}
	return FindSlotOwner(bot);
}

bool Session_GetBotTag(int bot, char[] buffer, int maxlength)
{
	int owner = FindSlotOwner(bot);
	if (owner == 0)
	{
		return false;
	}
	strcopy(buffer, maxlength, sessionType[owner] == ReplaySession_Lead ? "LEAD" : "RACE");
	return true;
}



// =====[ EVENTS ]=====

void OnMapStart_Session()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		ResetSession(client);
	}
	OnMapStart_Lead();
	CreateTimer(RP_SESSION_UPDATE_INTERVAL, Timer_UpdateSessions, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void OnClientPutInServer_Session(int client)
{
	if (sessionRoute[client] == null)
	{
		sessionRoute[client] = new ArrayList(sizeof(RoutePoint));
	}
	sessionBot[client] = -1;
	ResetSession(client);
}

void OnClientDisconnect_Session(int client)
{
	Session_Stop(client, false);
}

void GOKZ_OnTimerStart_Post_Session(int client, int course)
{
	switch (sessionType[client])
	{
		case ReplaySession_Lead:
		{
			Lead_OnTimerStart(client, course);
		}
		case ReplaySession_Race:
		{
			Race_OnTimerStart_Post(client, course);
		}
	}
}

void GOKZ_OnTimerEnd_Session(int client, int course, float time)
{
	if (sessionType[client] != ReplaySession_Race)
	{
		return;
	}
	Race_OnTimerEnd(client, course, time);
}

void GOKZ_OnTimerStopped_Session(int client)
{
	if (sessionType[client] != ReplaySession_Race)
	{
		return;
	}
	Race_OnTimerStopped(client);
}

void GOKZ_OnPause_Session(int client)
{
	if (sessionType[client] != ReplaySession_Race)
	{
		return;
	}
	Race_OnPause(client);
}

void GOKZ_OnResume_Session(int client)
{
	if (sessionType[client] != ReplaySession_Race)
	{
		return;
	}
	Race_OnResume(client);
}

void GOKZ_OnCountedTeleport_Session(int client)
{
	sessionRouteHint[client] = -1;
	if (sessionType[client] != ReplaySession_Lead)
	{
		return;
	}
	Lead_OnTeleport(client);
}

void OnPlayerRunCmdPost_Session(int client)
{
	if (!IsFakeClient(client))
	{
		return;
	}
	int owner = Session_GetBotOwner(client);
	if (owner == 0 || sessionType[owner] != ReplaySession_Lead)
	{
		return;
	}
	Lead_OnBotRunCmdPost(owner, client);
}

void OnRaceInfoChanged_Session(int raceID, RaceInfo prop, int newValue)
{
	if (prop != RaceInfo_Status || newValue != RaceStatus_Countdown)
	{
		return;
	}
	for (int client = 1; client <= MaxClients; client++)
	{
		if (sessionType[client] == ReplaySession_None || GOKZ_RC_GetRaceID(client) != raceID)
		{
			continue;
		}
		Session_Stop(client, true);
	}
}

public Action Timer_UpdateSessions(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (sessionType[client] == ReplaySession_None)
		{
			continue;
		}
		UpdateSession(client);
	}
	return Plugin_Continue;
}

public Action Hook_SessionBotTransmit(int entity, int client)
{
	int owner = Session_GetBotOwner(entity);
	if (owner == 0 || client == owner || client == entity)
	{
		return Plugin_Continue;
	}
	int target = GetObserverTarget(client);
	if (target == entity || target == owner)
	{
		return Plugin_Continue;
	}
	return Plugin_Handled;
}



// =====[ PRIVATE ]=====

static bool CanStartSession(int client, int type)
{
	if (gH_DB == null)
	{
		GOKZ_PrintToChat(client, true, "%t", "Replays Unavailable");
		GOKZ_PlayErrorSound(client);
		return false;
	}
	if (!IsPlayerAlive(client))
	{
		GOKZ_PrintToChat(client, true, "%t", "Session - Must Be Alive");
		GOKZ_PlayErrorSound(client);
		return false;
	}
	if (IsInPlayerRace(client))
	{
		GOKZ_PrintToChat(client, true, "%t", "Session - In Race");
		GOKZ_PlayErrorSound(client);
		return false;
	}
	bool isRace = type == ReplaySession_Race;
	bool isTimerRunning = GOKZ_GetTimerRunning(client);
	if (isRace && isTimerRunning)
	{
		GOKZ_PrintToChat(client, true, "%t", "Race - Timer Running");
		GOKZ_PlayErrorSound(client);
		return false;
	}
	return true;
}

static bool IsInPlayerRace(int client)
{
	if (!gB_GOKZRacing)
	{
		return false;
	}
	return GOKZ_RC_GetStatus(client) != RacerStatus_Available;
}

static bool IsLoadingToken(int client, int token)
{
	if (!IsValidClient(client) || sessionToken[client] != token)
	{
		return false;
	}
	return sessionState[client] == ReplaySessionState_Loading && sessionBot[client] == -1;
}

static bool IsAwaitingDownload(int client)
{
	bool loading = sessionState[client] == ReplaySessionState_Loading && sessionBot[client] == -1;
	return loading && sessionCachePath[client][0] != '\0';
}

static void ResetSession(int client)
{
	sessionToken[client]++;
	sessionType[client] = ReplaySession_None;
	sessionState[client] = ReplaySessionState_None;
	sessionBot[client] = -1;
	sessionCachePath[client][0] = '\0';
	sessionAlias[client][0] = '\0';
	sessionRunTimeMS[client] = 0;
	sessionTeleports[client] = 0;
	sessionRunTicks[client] = 0;
	sessionRouteHint[client] = -1;
	sessionPlayerProgress[client] = 0.0;
	sessionHasTimeDiff[client] = false;
	sessionTimeDiff[client] = 0.0;
	if (sessionRoute[client] != null)
	{
		sessionRoute[client].Clear();
	}
	Lead_Reset(client);
	Race_Reset(client);
}

static void FailSession(int client, const char[] phrase)
{
	ResetSession(client);
	if (phrase[0] != '\0')
	{
		GOKZ_PrintToChat(client, true, "%t", phrase);
	}
	GOKZ_PlayErrorSound(client);
}

static void StartSessionBot(int client, const char[] cachePath)
{
	int runTicks;
	if (!Progress_LoadRoute(cachePath, sessionRoute[client], runTicks) || sessionRoute[client].Length == 0)
	{
		FailSession(client, "Session - Unavailable");
		return;
	}
	int bot = Playback_StartSessionBot(client, cachePath);
	if (bot == -1)
	{
		ResetSession(client);
		return;
	}
	sessionRunTicks[client] = runTicks;
	sessionBot[client] = bot;
	sessionLoadStart[client] = GetGameTime();
}

static int FindSlotOwner(int bot)
{
	if (bot < 0)
	{
		return 0;
	}
	for (int client = 1; client <= MaxClients; client++)
	{
		if (sessionBot[client] == bot && sessionType[client] != ReplaySession_None)
		{
			return client;
		}
	}
	return 0;
}

static void UpdateSession(int client)
{
	if (sessionState[client] == ReplaySessionState_Loading)
	{
		UpdateLoadingSession(client);
		return;
	}
	UpdateComparison(client);
	switch (sessionType[client])
	{
		case ReplaySession_Lead:
		{
			Lead_Update(client);
		}
		case ReplaySession_Race:
		{
			Race_Update(client);
		}
	}
}

static void UpdateLoadingSession(int client)
{
	int bot = sessionBot[client];
	if (bot == -1)
	{
		CheckLookupTimeout(client);
		return;
	}
	if (!Playback_IsBotInGame(bot))
	{
		if (Playback_IsBotPending(bot))
		{
			return;
		}
		Playback_CancelBot(bot);
		FailSession(client, "No Bots Available");
		return;
	}
	int botClient = Playback_GetBotClient(bot);
	if (!IsPlayerAlive(botClient))
	{
		return;
	}
	BeginSession(client);
}

static void CheckLookupTimeout(int client)
{
	if (IsAwaitingDownload(client))
	{
		return;
	}
	float elapsed = GetGameTime() - sessionLoadStart[client];
	if (elapsed < RP_SESSION_LOOKUP_TIMEOUT)
	{
		return;
	}
	FailSession(client, "Session - Unavailable");
}

static void BeginSession(int client)
{
	int botClient = Session_GetBotClient(client);
	SetEntProp(botClient, Prop_Send, "m_CollisionGroup", RP_SESSION_BOT_COLLISION_GROUP);
	switch (sessionType[client])
	{
		case ReplaySession_Lead:
		{
			Lead_Begin(client);
		}
		case ReplaySession_Race:
		{
			Race_Begin(client);
		}
	}
}

static void UpdateComparison(int client)
{
	if (!IsPlayerAlive(client) || sessionRoute[client].Length == 0 || sessionRunTicks[client] <= 0)
	{
		sessionHasTimeDiff[client] = false;
		return;
	}
	float origin[3];
	GetClientAbsOrigin(client, origin);
	int nearest = Progress_FindRoutePoint(sessionRoute[client], origin, sessionRouteHint[client]);
	sessionRouteHint[client] = nearest;
	RoutePoint point;
	sessionRoute[client].GetArray(nearest, point);
	sessionPlayerProgress[client] = float(point.tick) / float(sessionRunTicks[client]);

	bool timing = GOKZ_GetTimerRunning(client) && GOKZ_GetCourse(client) == 0;
	sessionHasTimeDiff[client] = timing;
	if (!timing)
	{
		return;
	}
	float routeTime = float(point.tick) * GetTickInterval();
	sessionTimeDiff[client] = GOKZ_GetTime(client) - routeTime;
}
