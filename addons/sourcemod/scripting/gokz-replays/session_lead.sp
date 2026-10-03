#define LEAD_DISTANCE_OPTION_NAME "GOKZ Replays - Lead Distance"
#define LEAD_DISTANCE_OPTION_DESCRIPTION "Lead Bot Distance - 0 = Close, 1 = Normal, 2 = Far"
#define LEAD_RESYNC_FACTOR 2.0
#define LEAD_TRAIL_MAX_SEGMENT 256.0
#define LEAD_RESYNC_MIN_TICKS 64

enum
{
	LeadDistance_Close = 0,
	LeadDistance_Normal,
	LeadDistance_Far,
	LEADDISTANCE_COUNT
};

static const float leadResumeDistance[LEADDISTANCE_COUNT] = { 120.0, 200.0, 320.0 };
static const float leadWaitDistance[LEADDISTANCE_COUNT] = { 300.0, 500.0, 800.0 };
static const char leadDistancePhrases[LEADDISTANCE_COUNT][] =
{
	"Lead Distance - Close",
	"Lead Distance - Normal",
	"Lead Distance - Far"
};
static const int leadTrailColour[4] = { 42, 165, 247, 255 };

static bool leadResync[MAXPLAYERS + 1];
static float trailLastOrigin[MAXPLAYERS + 1][3];
static int trailTicks[MAXPLAYERS + 1];
static int beamSprite;
static TopMenu optionsTopMenu;
static TopMenuObject itemLeadDistance;



// =====[ PUBLIC ]=====

void Lead_Reset(int client)
{
	leadResync[client] = false;
	trailTicks[client] = 0;
}

void Lead_Begin(int client)
{
	ResyncToPlayer(client);

	char alias[MAX_NAME_LENGTH];
	Session_GetAlias(client, alias, sizeof(alias));
	char runTime[32];
	Session_FormatRunTime(client, runTime, sizeof(runTime));
	char timeType[16];
	Session_FormatTimeType(client, timeType, sizeof(timeType));
	GOKZ_PrintToChat(client, true, "%t", "Lead - Started", alias, runTime, timeType);
}

void Lead_Update(int client)
{
	int bot = Session_GetBot(client);
	if (!IsPlayerAlive(client))
	{
		WaitForPlayer(client, bot);
		return;
	}
	if (leadResync[client])
	{
		ResyncToPlayer(client);
		return;
	}

	float playerOrigin[3];
	GetClientAbsOrigin(client, playerOrigin);
	float botOrigin[3];
	GetClientAbsOrigin(Session_GetBotClient(client), botOrigin);
	float distance = GetVectorDistance(playerOrigin, botOrigin);

	int preset = GetLeadDistancePreset(client);
	float waitDistance = leadWaitDistance[preset];
	if (distance > waitDistance * LEAD_RESYNC_FACTOR && IsBotAwayFromPlayerRoute(client, bot))
	{
		ResyncToPlayer(client);
		return;
	}
	if (distance > waitDistance)
	{
		WaitForPlayer(client, bot);
		return;
	}
	if (Playback_GetTick(bot) >= Playback_GetLastTick(bot))
	{
		Session_SetState(client, ReplaySessionState_Finished);
		return;
	}
	if (distance < leadResumeDistance[preset])
	{
		Playback_SetPaused(bot, false);
		Session_SetState(client, ReplaySessionState_Running);
	}
}

void Lead_OnTimerStart(int client, int course)
{
	if (course != 0 || Session_GetState(client) == ReplaySessionState_Loading)
	{
		return;
	}
	int bot = Session_GetBot(client);
	Playback_SetTick(bot, Playback_GetRunStartTick());
	Playback_SetPaused(bot, false);
	Session_SetState(client, ReplaySessionState_Running);
	Session_ResetRouteHint(client);
	trailTicks[client] = 0;
}

void Lead_OnTeleport(int client)
{
	if (Session_GetState(client) == ReplaySessionState_Loading)
	{
		return;
	}
	leadResync[client] = true;
}

void Lead_OnBotRunCmdPost(int client, int botClient)
{
	if (Session_GetState(client) != ReplaySessionState_Running)
	{
		return;
	}
	trailTicks[client]++;
	if (trailTicks[client] % RP_LEAD_TRAIL_INTERVAL != 0)
	{
		return;
	}

	float origin[3];
	GetClientAbsOrigin(botClient, origin);
	bool hasLast = trailTicks[client] > RP_LEAD_TRAIL_INTERVAL;
	bool continuous = hasLast && GetVectorDistance(origin, trailLastOrigin[client]) < LEAD_TRAIL_MAX_SEGMENT;
	if (continuous)
	{
		DrawTrailSegment(client, trailLastOrigin[client], origin);
	}
	trailLastOrigin[client] = origin;
}

void Lead_CycleDistance(int client)
{
	int next = (GetLeadDistancePreset(client) + 1) % LEADDISTANCE_COUNT;
	GOKZ_SetOption(client, LEAD_DISTANCE_OPTION_NAME, next);
}

void Lead_FormatDistance(int client, char[] buffer, int maxlength)
{
	int preset = GetLeadDistancePreset(client);
	FormatEx(buffer, maxlength, "%T", leadDistancePhrases[preset], client);
}



// =====[ EVENTS ]=====

void OnMapStart_Lead()
{
	beamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
}

void OnOptionsMenuReady_Lead(TopMenu topMenu)
{
	GOKZ_RegisterOption(LEAD_DISTANCE_OPTION_NAME, LEAD_DISTANCE_OPTION_DESCRIPTION, OptionType_Int, LeadDistance_Normal, 0, LEADDISTANCE_COUNT - 1);

	if (optionsTopMenu == topMenu)
	{
		return;
	}
	optionsTopMenu = topMenu;
	TopMenuObject catGeneral = optionsTopMenu.FindCategory(GENERAL_OPTION_CATEGORY);
	itemLeadDistance = optionsTopMenu.AddItem(LEAD_DISTANCE_OPTION_NAME, TopMenuHandler_LeadDistance, catGeneral);
}

void GOKZ_OnOptionChanged_Lead(int client, const char[] option)
{
	if (!StrEqual(option, LEAD_DISTANCE_OPTION_NAME))
	{
		return;
	}
	char distance[32];
	Lead_FormatDistance(client, distance, sizeof(distance));
	GOKZ_PrintToChat(client, true, "%t", "Lead - Distance Set", distance);
}

public void TopMenuHandler_LeadDistance(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
	if (topobj_id != itemLeadDistance)
	{
		return;
	}
	if (action == TopMenuAction_DisplayOption)
	{
		char distance[32];
		Lead_FormatDistance(param, distance, sizeof(distance));
		FormatEx(buffer, maxlength, "%T - %s", "Options Menu - Lead Distance", param, distance);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		Lead_CycleDistance(param);
		optionsTopMenu.Display(param, TopMenuPosition_LastCategory);
	}
}



// =====[ PRIVATE ]=====

static int GetLeadDistancePreset(int client)
{
	int preset = GOKZ_GetOption(client, LEAD_DISTANCE_OPTION_NAME);
	if (preset < 0 || preset >= LEADDISTANCE_COUNT)
	{
		return LeadDistance_Normal;
	}
	return preset;
}

static bool IsBotAwayFromPlayerRoute(int client, int bot)
{
	int tick = Session_FindNearestTick(client);
	int offset = Playback_GetTick(bot) - tick;
	return offset > LEAD_RESYNC_MIN_TICKS || offset < -LEAD_RESYNC_MIN_TICKS;
}

static void ResyncToPlayer(int client)
{
	leadResync[client] = false;
	trailTicks[client] = 0;
	int bot = Session_GetBot(client);
	int tick = Session_FindNearestTick(client);
	Playback_SetTick(bot, tick);
	Playback_SetPaused(bot, false);
	Session_SetState(client, ReplaySessionState_Running);
}

static void WaitForPlayer(int client, int bot)
{
	Playback_SetPaused(bot, true);
	Session_SetState(client, ReplaySessionState_Waiting);
}

static void DrawTrailSegment(int client, const float start[3], const float end[3])
{
	int clients[MAXPLAYERS];
	int count = CollectTrailViewers(client, clients);
	TE_SetupBeamPoints(start, end, beamSprite, 0, 0, 0, RP_LEAD_TRAIL_LIFE, 3.0, 3.0, 1, 0.0, leadTrailColour, 0);
	TE_Send(clients, count);
}

static int CollectTrailViewers(int client, int clients[MAXPLAYERS])
{
	int count = 0;
	for (int viewer = 1; viewer <= MaxClients; viewer++)
	{
		if (!IsValidClient(viewer) || IsFakeClient(viewer))
		{
			continue;
		}
		if (viewer != client && GetObserverTarget(viewer) != client)
		{
			continue;
		}
		clients[count] = viewer;
		count++;
	}
	return count;
}
