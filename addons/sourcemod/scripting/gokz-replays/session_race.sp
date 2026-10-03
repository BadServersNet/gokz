#define RACE_TIE_THRESHOLD 0.005

static bool raceBotFinished[MAXPLAYERS + 1];
static bool raceWon[MAXPLAYERS + 1];
static float raceResultDiff[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void Race_Reset(int client)
{
	raceBotFinished[client] = false;
	raceWon[client] = false;
	raceResultDiff[client] = 0.0;
}

void Race_Begin(int client)
{
	ResetHeat(client);
	GOKZ_StopTimer(client, false);
	if (GOKZ_SetStartPositionToMapStart(client, 0))
	{
		GOKZ_TeleportToStart(client);
	}
	else
	{
		GOKZ_PrintToChat(client, true, "%t", "Race - No Start");
	}

	char alias[MAX_NAME_LENGTH];
	Session_GetAlias(client, alias, sizeof(alias));
	char runTime[32];
	Session_FormatRunTime(client, runTime, sizeof(runTime));
	char timeType[16];
	Session_FormatTimeType(client, timeType, sizeof(timeType));
	GOKZ_PrintToChat(client, true, "%t", "Race - Started", alias, runTime, timeType);
}

void Race_FillInfo(int client, ReplaySessionInfo info)
{
	info.botFinished = raceBotFinished[client];
	info.won = raceWon[client];
	info.resultDiff = raceResultDiff[client];
}

void Race_Update(int client)
{
	int state = Session_GetState(client);
	if (state != ReplaySessionState_Running && state != ReplaySessionState_Finished)
	{
		return;
	}
	SyncBotToTimer(client);
	CheckBotFinished(client);
}

void Race_OnTimerStart_Post(int client, int course)
{
	if (!IsRaceStarted(client))
	{
		return;
	}
	if (course != 0)
	{
		ResetHeat(client);
		return;
	}
	ResetHeat(client);
	Playback_SetPaused(Session_GetBot(client), false);
	Session_SetState(client, ReplaySessionState_Running);
}

void Race_OnTimerEnd(int client, int course, float time)
{
	if (Session_GetState(client) != ReplaySessionState_Running || course != 0)
	{
		return;
	}
	float runTime = Session_GetRunTime(client);
	float diff = time - runTime;
	raceResultDiff[client] = FloatAbs(diff);
	raceWon[client] = diff < 0.0;
	Session_SetState(client, ReplaySessionState_Finished);
	AnnounceResult(client, time, runTime, diff);
}

void Race_OnTimerStopped(int client)
{
	if (Session_GetState(client) != ReplaySessionState_Running)
	{
		return;
	}
	ResetHeat(client);
}

void Race_OnPause(int client)
{
	if (Session_GetState(client) != ReplaySessionState_Running)
	{
		return;
	}
	Playback_SetPaused(Session_GetBot(client), true);
}

void Race_OnResume(int client)
{
	if (Session_GetState(client) != ReplaySessionState_Running)
	{
		return;
	}
	Playback_SetPaused(Session_GetBot(client), false);
}



// =====[ PRIVATE ]=====

static bool IsRaceStarted(int client)
{
	int state = Session_GetState(client);
	return state == ReplaySessionState_Ready
		 || state == ReplaySessionState_Running
		 || state == ReplaySessionState_Finished;
}

static void ResetHeat(int client)
{
	int bot = Session_GetBot(client);
	Playback_SetTick(bot, Playback_GetRunStartTick());
	Playback_SetPaused(bot, true);
	Session_ResetRouteHint(client);
	raceBotFinished[client] = false;
	raceWon[client] = false;
	raceResultDiff[client] = 0.0;
	Session_SetState(client, ReplaySessionState_Ready);
}

static void SyncBotToTimer(int client)
{
	if (!GOKZ_GetTimerRunning(client) || GOKZ_GetPaused(client) || raceBotFinished[client])
	{
		return;
	}
	int bot = Session_GetBot(client);
	int timerTicks = RoundToFloor(GOKZ_GetTime(client) / GetTickInterval());
	int desired = Playback_GetRunStartTick() + timerTicks;
	if (desired > Playback_GetLastTick(bot))
	{
		return;
	}
	int drift = Playback_GetTick(bot) - desired;
	if (drift > RP_SESSION_SYNC_TOLERANCE || drift < -RP_SESSION_SYNC_TOLERANCE)
	{
		Playback_SetTick(bot, desired);
	}
}

static void CheckBotFinished(int client)
{
	int bot = Session_GetBot(client);
	if (raceBotFinished[client] || Playback_GetTick(bot) < Playback_GetRunEndTick(bot))
	{
		return;
	}
	raceBotFinished[client] = true;
	if (Session_GetState(client) != ReplaySessionState_Running)
	{
		return;
	}

	char alias[MAX_NAME_LENGTH];
	Session_GetAlias(client, alias, sizeof(alias));
	char runTime[32];
	Session_FormatRunTime(client, runTime, sizeof(runTime));
	GOKZ_PrintToChat(client, true, "%t", "Race - Bot Finished", alias, runTime);
}

static void AnnounceResult(int client, float time, float runTime, float diff)
{
	char alias[MAX_NAME_LENGTH];
	Session_GetAlias(client, alias, sizeof(alias));
	char playerTime[32];
	strcopy(playerTime, sizeof(playerTime), GOKZ_FormatTime(time));
	char botTime[32];
	strcopy(botTime, sizeof(botTime), GOKZ_FormatTime(runTime));
	float margin = FloatAbs(diff);

	if (margin < RACE_TIE_THRESHOLD)
	{
		GOKZ_PrintToChat(client, true, "%t", "Race - Tied", alias, playerTime);
		return;
	}
	if (diff < 0.0)
	{
		GOKZ_PrintToChat(client, true, "%t", "Race - Won", alias, margin, playerTime, botTime);
		return;
	}
	GOKZ_PrintToChat(client, true, "%t", "Race - Lost", alias, margin, playerTime, botTime);
}
