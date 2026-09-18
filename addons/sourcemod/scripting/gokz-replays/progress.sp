/*
	Map progress: how far along a run replay's route each running player is.
	The server route is the fastest main course run replay of the current map.
	A player can instead follow any main course replay of the map by its code.
	Routes are reduced to evenly spaced points that remember the replay tick they
	were recorded at, so progress is the fraction of the run's time at the nearest point.
*/



enum ProgressStatus
{
	ProgressStatus_None = 0,
	ProgressStatus_Running,
	ProgressStatus_Finished
}

enum struct RoutePoint
{
	float origin[3];
	int tick;
}

static ConVar gCV_gokz_replay_progress_enabled;
static ConVar gCV_gokz_replay_progress_scoreboard;
static ConVar gCV_gokz_replay_progress_max_minutes;

static ArrayList g_Route;
static int g_RouteRunTicks;
static int g_RouteTimeMS;
static ArrayList clientRoute[MAXPLAYERS + 1];
static int clientRouteRunTicks[MAXPLAYERS + 1];
static ProgressStatus progressStatus[MAXPLAYERS + 1];
static float progressValue[MAXPLAYERS + 1];
static int lastRouteIndex[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void Progress_CreateConVars()
{
	gCV_gokz_replay_progress_enabled = AutoExecConfig_CreateConVar("gokz_replay_progress_enabled", "1", "Whether map progress along the server record route is tracked for running players.", _, true, 0.0, true, 1.0);
	gCV_gokz_replay_progress_scoreboard = AutoExecConfig_CreateConVar("gokz_replay_progress_scoreboard", "1", "Whether the scoreboard score of running players shows their map progress.", _, true, 0.0, true, 1.0);
	gCV_gokz_replay_progress_max_minutes = AutoExecConfig_CreateConVar("gokz_replay_progress_max_minutes", "30", "Server record replays longer than this many minutes are not used as a progress route (0 = no limit).", _, true, 0.0);
}

bool Progress_IsTracked(int client)
{
	return progressStatus[client] != ProgressStatus_None && IsValidClient(client) && HasRouteForClient(client);
}

float Progress_GetValue(int client)
{
	return progressValue[client];
}

bool Progress_GetClientProgress(int client, float &progress, int &rank, int &total)
{
	if (!HasRouteForClient(client) || progressStatus[client] == ProgressStatus_None)
	{
		return false;
	}

	progress = progressValue[client];
	rank = 1;
	total = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (progressStatus[i] == ProgressStatus_None || !IsValidClient(i))
		{
			continue;
		}
		total++;
		if (i != client && progressValue[i] > progress)
		{
			rank++;
		}
	}
	return true;
}

void Progress_OnRouteCandidates(ArrayList candidates)
{
	if (!IsProgressEnabled())
	{
		return;
	}

	int maxTimeMS = GetMaxRouteTimeMS();
	for (int i = 0; i < candidates.Length; i++)
	{
		ReplayEntry entry;
		candidates.GetArray(i, entry);
		if (maxTimeMS > 0 && entry.runTimeMS > maxTimeMS)
		{
			break;
		}
		char cachePath[PLATFORM_MAX_PATH];
		if (!Progress_IsReplayCached(entry, cachePath, sizeof(cachePath)))
		{
			continue;
		}
		LoadServerRoute(cachePath, entry.runTimeMS);
		return;
	}

	int downloadable = Progress_FindDownloadableCandidate(candidates, maxTimeMS);
	if (downloadable == -1)
	{
		LogMessage("No usable server record replay for the progress route on %s.", gC_CurrentMap);
		return;
	}
	ReplayEntry entry;
	candidates.GetArray(downloadable, entry);
	g_RouteTimeMS = entry.runTimeMS;
	Store_RequestRouteDownload(entry.objectKey, entry.fileSize, RouteDownload_Server, 0);
}

void Progress_OnRouteDownloaded(RouteDownloadKind kind, int routeUserid, const char[] cachePath)
{
	if (kind == RouteDownload_Server)
	{
		LoadServerRoute(cachePath, g_RouteTimeMS);
		return;
	}
	int client = GetClientOfUserId(routeUserid);
	if (!IsValidClient(client))
	{
		return;
	}
	if (kind == RouteDownload_PB)
	{
		TimeDiff_OnPBDownloaded(client, cachePath);
		return;
	}
	LoadClientRoute(client, cachePath);
}

void Progress_OnRouteDownloadFailed(RouteDownloadKind kind, int routeUserid)
{
	if (kind != RouteDownload_Client)
	{
		return;
	}
	int client = GetClientOfUserId(routeUserid);
	if (!IsValidClient(client))
	{
		return;
	}
	GOKZ_PrintToChat(client, true, "%t", "Replay Download - Failed");
	GOKZ_PlayErrorSound(client);
}

void Progress_OnRunReplaySaved(int client, int course, float time, const char[] cachePath)
{
	TimeDiff_OnRunReplaySaved(client, course, time, cachePath);
	if (!IsProgressEnabled() || course != 0)
	{
		return;
	}
	int timeMS = GOKZ_DB_TimeFloatToInt(time);
	bool faster = !HasServerRoute() || timeMS < g_RouteTimeMS;
	if (!faster)
	{
		return;
	}
	int maxTimeMS = GetMaxRouteTimeMS();
	if (maxTimeMS > 0 && timeMS > maxTimeMS)
	{
		return;
	}
	LoadServerRoute(cachePath, timeMS);
}

void Progress_RequestClientRoute(int client, const char[] code)
{
	if (gH_DB == null)
	{
		GOKZ_PrintToChat(client, true, "%t", "Replays Unavailable");
		GOKZ_PlayErrorSound(client);
		return;
	}
	DB_LookupProgressReplay(client, code);
}

void Progress_OnClientRouteReplay(int client, ReplayEntry entry)
{
	if (!StrEqual(entry.mapName, gC_CurrentMap, false))
	{
		GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Wrong Map", entry.mapName);
		GOKZ_PlayErrorSound(client);
		return;
	}
	if (entry.course != 0)
	{
		GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Wrong Course");
		GOKZ_PlayErrorSound(client);
		return;
	}

	char cachePath[PLATFORM_MAX_PATH];
	if (Progress_IsReplayCached(entry, cachePath, sizeof(cachePath)))
	{
		LoadClientRoute(client, cachePath);
		AnnounceClientRoute(client, entry);
		return;
	}
	if (!entry.inStore || !Store_IsReady())
	{
		GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Unavailable");
		GOKZ_PlayErrorSound(client);
		return;
	}
	AnnounceClientRoute(client, entry);
	GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Loading");
	Store_RequestRouteDownload(entry.objectKey, entry.fileSize, RouteDownload_Client, GetClientUserId(client));
}

void Progress_ResetClientRoute(int client, bool announce)
{
	if (clientRoute[client] != null)
	{
		clientRoute[client].Clear();
	}
	clientRouteRunTicks[client] = 0;
	if (announce)
	{
		GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Reset");
	}
}



// =====[ EVENTS ]=====

void OnPluginStart_Progress()
{
	g_Route = new ArrayList(sizeof(RoutePoint));
}

void OnMapStart_Progress()
{
	ClearServerRoute();
	for (int client = 1; client <= MaxClients; client++)
	{
		Progress_ResetClientRoute(client, false);
	}
	CreateTimer(RP_PROGRESS_UPDATE_INTERVAL, Timer_UpdateProgress, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	if (Store_IsConfigLoaded())
	{
		RequestServerRoute();
	}
}

void OnConfigsExecuted_Progress()
{
	if (HasServerRoute())
	{
		return;
	}
	RequestServerRoute();
}

void OnDatabaseConnect_Progress()
{
	if (HasServerRoute())
	{
		return;
	}
	RequestServerRoute();
}

void OnClientPutInServer_Progress(int client)
{
	if (clientRoute[client] == null)
	{
		clientRoute[client] = new ArrayList(sizeof(RoutePoint));
	}
	Progress_ResetClientRoute(client, false);
	ResetClientProgress(client);
}

void OnClientDisconnect_Progress(int client)
{
	Progress_ResetClientRoute(client, false);
	ResetClientProgress(client);
}

void GOKZ_OnTimerStart_Progress(int client, int course)
{
	if (IsFakeClient(client))
	{
		return;
	}
	if (course != 0)
	{
		ResetClientProgress(client);
		return;
	}
	progressStatus[client] = ProgressStatus_Running;
	progressValue[client] = 0.0;
	lastRouteIndex[client] = 0;
	UpdateScoreboard(client);
}

void GOKZ_OnCountedTeleport_Progress(int client)
{
	lastRouteIndex[client] = -1;
}

void GOKZ_OnTimerEnd_Progress(int client, int course)
{
	if (course != 0 || progressStatus[client] != ProgressStatus_Running)
	{
		return;
	}
	progressStatus[client] = ProgressStatus_Finished;
	progressValue[client] = 1.0;
	UpdateScoreboard(client);
}

void GOKZ_OnTimerStopped_Progress(int client)
{
	if (progressStatus[client] != ProgressStatus_Running)
	{
		return;
	}
	ResetClientProgress(client);
}

public Action Timer_UpdateProgress(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsTrackingClient(client) || !HasRouteForClient(client))
		{
			continue;
		}
		UpdateClientProgress(client);
	}
	return Plugin_Continue;
}



// =====[ PRIVATE ]=====

static bool IsProgressEnabled()
{
	return gCV_gokz_replay_progress_enabled.BoolValue;
}

static int GetMaxRouteTimeMS()
{
	return RoundToNearest(gCV_gokz_replay_progress_max_minutes.FloatValue * 60000.0);
}

static bool HasServerRoute()
{
	return g_Route != null && g_Route.Length > 0;
}

static bool HasClientRoute(int client)
{
	return clientRoute[client] != null && clientRoute[client].Length > 0;
}

static bool HasRouteForClient(int client)
{
	return HasClientRoute(client) || HasServerRoute();
}

static void RequestServerRoute()
{
	if (!IsProgressEnabled() || gH_DB == null)
	{
		return;
	}
	DB_LoadProgressRoute(gC_CurrentMap);
}

bool Progress_IsReplayCached(ReplayEntry entry, char[] cachePath, int maxlength)
{
	KeyToCachePath(entry.objectKey, cachePath, maxlength);
	if (!FileExists(cachePath))
	{
		return false;
	}
	return entry.fileSize <= 0 || FileSize(cachePath) == entry.fileSize;
}

int Progress_FindDownloadableCandidate(ArrayList candidates, int maxTimeMS)
{
	if (!Store_IsReady())
	{
		return -1;
	}
	for (int i = 0; i < candidates.Length; i++)
	{
		ReplayEntry entry;
		candidates.GetArray(i, entry);
		if (maxTimeMS > 0 && entry.runTimeMS > maxTimeMS)
		{
			return -1;
		}
		if (entry.inStore)
		{
			return i;
		}
	}
	return -1;
}

static void ClearServerRoute()
{
	g_Route.Clear();
	g_RouteRunTicks = 0;
	g_RouteTimeMS = 0;
}

static void ResetClientProgress(int client)
{
	bool wasTracked = progressStatus[client] != ProgressStatus_None;
	progressStatus[client] = ProgressStatus_None;
	progressValue[client] = 0.0;
	if (wasTracked)
	{
		UpdateScoreboard(client);
	}
}

static bool IsTrackingClient(int client)
{
	if (progressStatus[client] != ProgressStatus_Running)
	{
		return false;
	}
	return IsValidClient(client) && !IsFakeClient(client) && IsPlayerAlive(client);
}

static void AnnounceClientRoute(int client, ReplayEntry entry)
{
	int timeType = GOKZ_GetTimeTypeEx(entry.teleports);
	GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Set", entry.alias, GOKZ_FormatTime(GOKZ_DB_TimeIntToFloat(entry.runTimeMS)), gC_TimeTypeNames[timeType]);
}

static void UpdateClientProgress(int client)
{
	ArrayList route = HasClientRoute(client) ? clientRoute[client] : g_Route;
	int runTicks = HasClientRoute(client) ? clientRouteRunTicks[client] : g_RouteRunTicks;

	float origin[3];
	GetClientAbsOrigin(client, origin);
	int nearest = Progress_FindRoutePoint(route, origin, lastRouteIndex[client]);
	lastRouteIndex[client] = nearest;
	RoutePoint point;
	route.GetArray(nearest, point);
	progressValue[client] = float(point.tick) / float(runTicks);
	UpdateScoreboard(client);
}

int Progress_FindRoutePoint(ArrayList route, const float origin[3], int hint)
{
	if (hint >= 0 && hint < route.Length)
	{
		int first = IntMax(0, hint - RP_PROGRESS_SEARCH_WINDOW);
		int last = IntMin(route.Length - 1, hint + RP_PROGRESS_SEARCH_WINDOW);
		float windowDistance;
		int windowNearest = FindNearestInRange(route, origin, first, last, windowDistance);
		if (windowDistance <= RP_PROGRESS_SNAP_DISTANCE)
		{
			return windowNearest;
		}
	}

	float bestDistance;
	FindNearestInRange(route, origin, 0, route.Length - 1, bestDistance);
	return FindPreferredWithinTolerance(route, origin, bestDistance + RP_PROGRESS_TOLERANCE, hint);
}

static int FindNearestInRange(ArrayList route, const float origin[3], int first, int last, float &nearestDistance)
{
	int nearest = first;
	nearestDistance = -1.0;
	for (int i = first; i <= last; i++)
	{
		RoutePoint point;
		route.GetArray(i, point);
		float distance = GetVectorDistance(origin, point.origin);
		if (nearestDistance >= 0.0 && distance >= nearestDistance)
		{
			continue;
		}
		nearest = i;
		nearestDistance = distance;
	}
	return nearest;
}

static int FindPreferredWithinTolerance(ArrayList route, const float origin[3], float maxDistance, int hint)
{
	int preferred = 0;
	int preferredOffset = -1;
	for (int i = 0; i < route.Length; i++)
	{
		RoutePoint point;
		route.GetArray(i, point);
		float distance = GetVectorDistance(origin, point.origin);
		if (distance > maxDistance)
		{
			continue;
		}
		int offset = GetIndexDistance(i, hint);
		if (preferredOffset >= 0 && offset >= preferredOffset)
		{
			continue;
		}
		preferred = i;
		preferredOffset = offset;
	}
	return preferred;
}

static int GetIndexDistance(int index, int hint)
{
	if (hint < 0)
	{
		return index;
	}
	return index > hint ? index - hint : hint - index;
}

static void UpdateScoreboard(int client)
{
	if (!gCV_gokz_replay_progress_scoreboard.BoolValue || !IsValidClient(client))
	{
		return;
	}
	int score = RoundToNearest(progressValue[client] * 1000.0);
	CS_SetClientContributionScore(client, score);
}

static void LoadServerRoute(const char[] cachePath, int runTimeMS)
{
	int runTicks;
	if (!Progress_LoadRoute(cachePath, g_Route, runTicks))
	{
		return;
	}
	g_RouteRunTicks = runTicks;
	g_RouteTimeMS = runTimeMS;
	LogMessage("Loaded the progress route for %s from \"%s\" (%d points, %d ticks).", gC_CurrentMap, cachePath, g_Route.Length, g_RouteRunTicks);
}

static void LoadClientRoute(int client, const char[] cachePath)
{
	int runTicks;
	if (!Progress_LoadRoute(cachePath, clientRoute[client], runTicks))
	{
		GOKZ_PrintToChat(client, true, "%t", "Progress Replay - Unavailable");
		GOKZ_PlayErrorSound(client);
		return;
	}
	clientRouteRunTicks[client] = runTicks;
	lastRouteIndex[client] = -1;
}

bool Progress_LoadRoute(const char[] cachePath, ArrayList route, int &runTicks)
{
	ArrayList origins = new ArrayList(3);
	bool read = ReadReplayOrigins(cachePath, origins);
	if (!read)
	{
		delete origins;
		LogError("Failed to read a progress route from \"%s\".", cachePath);
		return false;
	}

	runTicks = BuildRoute(origins, route);
	delete origins;
	return true;
}

static int BuildRoute(ArrayList origins, ArrayList route)
{
	int padding = RoundToZero(RP_PLAYBACK_BREATHER_TIME / GetTickInterval());
	int total = origins.Length;
	int firstTick = padding;
	int lastTick = total - padding;
	if (lastTick - firstTick <= 0)
	{
		firstTick = 0;
		lastTick = total;
	}

	route.Clear();
	float last[3];
	for (int tick = firstTick; tick < lastTick; tick++)
	{
		float origin[3];
		origins.GetArray(tick, origin, 3);
		bool spaced = route.Length == 0 || GetVectorDistance(origin, last) >= RP_PROGRESS_POINT_SPACING;
		if (!spaced)
		{
			continue;
		}
		PushRoutePoint(route, origin, tick - firstTick);
		last = origin;
	}
	ThinRoute(route);
	return lastTick - firstTick;
}

static void PushRoutePoint(ArrayList route, const float origin[3], int tick)
{
	RoutePoint point;
	point.origin = origin;
	point.tick = tick;
	route.PushArray(point);
}

static void ThinRoute(ArrayList route)
{
	int length = route.Length;
	if (length <= RP_PROGRESS_MAX_POINTS)
	{
		return;
	}
	int stride = RoundToCeil(float(length) / float(RP_PROGRESS_MAX_POINTS));
	int kept = 0;
	for (int i = 0; i < length; i += stride)
	{
		RoutePoint point;
		route.GetArray(i, point);
		route.SetArray(kept, point);
		kept++;
	}
	route.Resize(kept);
}

static bool ReadReplayOrigins(const char[] path, ArrayList origins)
{
	File file = OpenFile(path, "rb");
	if (file == null)
	{
		return false;
	}

	int magicNumber;
	file.ReadInt32(magicNumber);
	int formatVersion;
	file.ReadInt8(formatVersion);
	if (magicNumber != RP_MAGIC_NUMBER)
	{
		delete file;
		return false;
	}

	bool read = false;
	if (formatVersion == 1)
	{
		read = ReadFormatVersion1Origins(file, origins);
	}
	else if (formatVersion == RP_FORMAT_VERSION)
	{
		read = ReadFormatVersion2Origins(file, origins);
	}
	delete file;
	return read && origins.Length > 0;
}

static bool ReadFormatVersion1Origins(File file, ArrayList origins)
{
	SkipLengthPrefixedString(file);
	SkipLengthPrefixedString(file);
	file.Seek(24, SEEK_CUR);
	SkipLengthPrefixedString(file);
	SkipLengthPrefixedString(file);
	SkipLengthPrefixedString(file);

	int tickCount;
	file.ReadInt32(tickCount);
	any tickData[RP_V1_TICK_DATA_BLOCKSIZE];
	for (int i = 0; i < tickCount; i++)
	{
		if (file.Read(tickData, RP_V1_TICK_DATA_BLOCKSIZE, 4) != RP_V1_TICK_DATA_BLOCKSIZE)
		{
			return false;
		}
		float origin[3];
		origin[0] = view_as<float>(tickData[0]);
		origin[1] = view_as<float>(tickData[1]);
		origin[2] = view_as<float>(tickData[2]);
		origins.PushArray(origin, 3);
	}
	return true;
}

static bool ReadFormatVersion2Origins(File file, ArrayList origins)
{
	int replayType;
	file.ReadInt8(replayType);
	if (replayType != ReplayType_Run)
	{
		return false;
	}
	SkipLengthPrefixedString(file);
	SkipLengthPrefixedString(file);
	file.Seek(12, SEEK_CUR);
	SkipLengthPrefixedString(file);
	file.Seek(18, SEEK_CUR);
	int tickCount;
	file.ReadInt32(tickCount);
	file.Seek(17, SEEK_CUR);

	any tickData[RP_V2_TICK_DATA_BLOCKSIZE];
	for (int i = 0; i < tickCount; i++)
	{
		if (!ReadDeltaTick(file, tickData))
		{
			return false;
		}
		float origin[3];
		origin[0] = view_as<float>(tickData[RPDELTA_ORIGIN_X]);
		origin[1] = view_as<float>(tickData[RPDELTA_ORIGIN_Y]);
		origin[2] = view_as<float>(tickData[RPDELTA_ORIGIN_Z]);
		origins.PushArray(origin, 3);
	}
	return true;
}

static bool ReadDeltaTick(File file, any tickData[RP_V2_TICK_DATA_BLOCKSIZE])
{
	if (!file.ReadInt32(tickData[RPDELTA_DELTAFLAGS]))
	{
		return false;
	}
	for (int index = 1; index < RP_V2_TICK_DATA_BLOCKSIZE; index++)
	{
		int flag = (1 << index);
		if (!(tickData[RPDELTA_DELTAFLAGS] & flag))
		{
			continue;
		}
		if (!file.ReadInt32(tickData[index]))
		{
			return false;
		}
	}
	return true;
}
