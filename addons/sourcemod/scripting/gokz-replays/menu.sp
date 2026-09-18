/*
	Replay menu navigation. Every menu browses replays within a scope: the current map,
	a specific map, or all maps. Lists of replays are displayed by menu_entries.sp.
*/



enum ReplayMenu
{
	ReplayMenu_None = 0,
	ReplayMenu_Hub,
	ReplayMenu_Runs,
	ReplayMenu_MyRuns,
	ReplayMenu_RunMaps,
	ReplayMenu_RunModes,
	ReplayMenu_RunCourses,
	ReplayMenu_RunList,
	ReplayMenu_JumpModes,
	ReplayMenu_JumpTypes,
	ReplayMenu_JumpList,
	ReplayMenu_RecentList
}

#define ITEM_INFO_HUB_RUNS "runs"
#define ITEM_INFO_HUB_MINE "mine"
#define ITEM_INFO_HUB_JUMPS "jumps"
#define ITEM_INFO_HUB_RECENT "recent"
#define ITEM_INFO_HUB_SCOPE "scope"

static bool scopeAll[MAXPLAYERS + 1];
static char scopeMap[MAXPLAYERS + 1][64];
static bool listMine[MAXPLAYERS + 1];
static int listMode[MAXPLAYERS + 1];
static int listCourse[MAXPLAYERS + 1];
static int listJumpType[MAXPLAYERS + 1];
static ReplayMenu currentMenu[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void OpenReplayMenuWithScope(int client, const char[] scopeArg, ReplayMenu kind)
{
	if (!IsReplayMenuAvailable(client))
	{
		return;
	}
	if (scopeArg[0] == '\0')
	{
		ReplayScope_SetCurrentMap(client);
		OpenReplayMenu(client, kind);
		return;
	}
	if (StrEqual(scopeArg, "all", false))
	{
		ReplayScope_SetAll(client);
		OpenReplayMenu(client, kind);
		return;
	}
	DB_FindReplayMap(client, scopeArg, kind);
}

void OpenReplayMenu(int client, ReplayMenu kind)
{
	if (!IsReplayMenuAvailable(client))
	{
		return;
	}

	switch (kind)
	{
		case ReplayMenu_Hub:
		{
			DisplayReplayHubMenu(client);
		}
		case ReplayMenu_Runs:
		{
			OpenRunFlow(client, false);
		}
		case ReplayMenu_MyRuns:
		{
			OpenRunFlow(client, true);
		}
		case ReplayMenu_RunMaps:
		{
			int steamID = listMine[client] ? GetSteamAccountID(client) : 0;
			DB_OpenReplayMapMenu(client, steamID);
		}
		case ReplayMenu_RunModes:
		{
			DisplayRunModeMenu(client);
		}
		case ReplayMenu_RunCourses:
		{
			DB_OpenRunCourseMenu(client, scopeMap[client], listMode[client]);
		}
		case ReplayMenu_RunList:
		{
			OpenRunList(client);
		}
		case ReplayMenu_JumpModes:
		{
			DisplayJumpModeMenu(client);
		}
		case ReplayMenu_JumpTypes:
		{
			DisplayJumpTypeMenu(client);
		}
		case ReplayMenu_JumpList:
		{
			char map[64];
			ReplayScope_GetFilterMap(client, map, sizeof(map));
			DB_OpenJumpList(client, map, listMode[client], listJumpType[client]);
		}
		case ReplayMenu_RecentList:
		{
			char map[64];
			ReplayScope_GetFilterMap(client, map, sizeof(map));
			DB_OpenRecentList(client, map);
		}
	}
}

void ReopenReplayMenu(int client)
{
	if (currentMenu[client] == ReplayMenu_None)
	{
		return;
	}
	OpenReplayMenu(client, currentMenu[client]);
}

void OpenParentReplayMenu(int client, ReplayMenu kind)
{
	ReplayMenu parent = GetParentReplayMenu(client, kind);
	if (parent == ReplayMenu_None)
	{
		currentMenu[client] = ReplayMenu_None;
		return;
	}
	OpenReplayMenu(client, parent);
}

void ReplayMenu_SetCurrent(int client, ReplayMenu kind)
{
	currentMenu[client] = kind;
}

ReplayMenu ReplayMenu_GetCurrent(int client)
{
	return currentMenu[client];
}

bool ReplayMenu_IsMine(int client)
{
	return listMine[client];
}

int ReplayMenu_GetMode(int client)
{
	return listMode[client];
}

int ReplayMenu_GetCourse(int client)
{
	return listCourse[client];
}

int ReplayMenu_GetJumpType(int client)
{
	return listJumpType[client];
}

void ReplayScope_SetMap(int client, const char[] map)
{
	strcopy(scopeMap[client], sizeof(scopeMap[]), map);
	scopeAll[client] = false;
}

bool ReplayScope_IsAll(int client)
{
	return scopeAll[client];
}

void ReplayScope_GetRunMap(int client, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, scopeMap[client]);
}

void ReplayScope_FormatName(int client, char[] buffer, int maxlength)
{
	if (scopeAll[client])
	{
		FormatEx(buffer, maxlength, "%T", "Replay Menu - All Maps", client);
		return;
	}
	strcopy(buffer, maxlength, scopeMap[client]);
}

void FormatCourseName(int client, int course, char[] buffer, int maxlength)
{
	if (course == 0)
	{
		FormatEx(buffer, maxlength, "%T", "Replay Menu - Main Course", client);
		return;
	}
	FormatEx(buffer, maxlength, "%T", "Replay Menu - Bonus", client, course);
}

void FormatRunSectionName(int client, char[] buffer, int maxlength)
{
	if (listMine[client])
	{
		FormatEx(buffer, maxlength, "%T", "Replay Menu - My Run Replays", client);
		return;
	}
	FormatEx(buffer, maxlength, "%T", "Replay Menu - Run Replays", client);
}



// =====[ EVENTS ]=====

void OnClientPutInServer_ReplayMenu(int client)
{
	ReplayScope_SetCurrentMap(client);
	listMine[client] = false;
	listMode[client] = 0;
	listCourse[client] = 0;
	listJumpType[client] = 0;
	currentMenu[client] = ReplayMenu_None;
}

public int MenuHandler_ReplayHub(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		SelectHubItem(param1, info);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		currentMenu[param1] = ReplayMenu_None;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public int MenuHandler_ReplayMaps(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char map[64];
		menu.GetItem(param2, map, sizeof(map));
		strcopy(scopeMap[param1], sizeof(scopeMap[]), map);
		OpenReplayMenu(param1, ReplayMenu_RunModes);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		OpenParentReplayMenu(param1, ReplayMenu_RunMaps);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public int MenuHandler_RunModes(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		listMode[param1] = param2;
		OpenReplayMenu(param1, ReplayMenu_RunCourses);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		OpenParentReplayMenu(param1, ReplayMenu_RunModes);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public int MenuHandler_RunCourses(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		listCourse[param1] = StringToInt(info);
		OpenReplayMenu(param1, ReplayMenu_RunList);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		OpenParentReplayMenu(param1, ReplayMenu_RunCourses);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public int MenuHandler_JumpModes(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		listMode[param1] = param2;
		OpenReplayMenu(param1, ReplayMenu_JumpTypes);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		OpenParentReplayMenu(param1, ReplayMenu_JumpModes);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public int MenuHandler_JumpTypes(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		listJumpType[param1] = StringToInt(info);
		OpenReplayMenu(param1, ReplayMenu_JumpList);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		OpenParentReplayMenu(param1, ReplayMenu_JumpTypes);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}



// =====[ MENUS ]=====

void DisplayReplayMapMenu(int client, ArrayList maps)
{
	if (maps.Length == 0)
	{
		NotifyNoRunMaps(client);
		OpenParentReplayMenu(client, ReplayMenu_RunMaps);
		return;
	}

	ReplayMenu_SetCurrent(client, ReplayMenu_RunMaps);
	Menu menu = new Menu(MenuHandler_ReplayMaps);
	char section[64];
	FormatRunSectionName(client, section, sizeof(section));
	menu.SetTitle("%T", "Replay Menu (Maps) - Title", client, section);
	for (int i = 0; i < maps.Length; i++)
	{
		ReplayMapEntry entry;
		maps.GetArray(i, entry);
		char display[80];
		FormatEx(display, sizeof(display), "%T", "Replay Menu - Map Item", client, entry.name, entry.count);
		menu.AddItem(entry.name, display);
	}
	menu.Display(client, MENU_TIME_FOREVER);
}

void DisplayRunCourseMenu(int client, ArrayList courses)
{
	if (courses.Length == 0)
	{
		GOKZ_PrintToChat(client, true, "%t", "No Replays Found (Mode)", gC_ModeNames[listMode[client]], scopeMap[client]);
		GOKZ_PlayErrorSound(client);
		OpenParentReplayMenu(client, ReplayMenu_RunCourses);
		return;
	}

	ReplayMenu_SetCurrent(client, ReplayMenu_RunCourses);
	Menu menu = new Menu(MenuHandler_RunCourses);
	char section[64];
	FormatRunSectionName(client, section, sizeof(section));
	menu.SetTitle("%T", "Replay Menu (Course) - Title", client, section, scopeMap[client], gC_ModeNames[listMode[client]]);
	for (int i = 0; i < courses.Length; i++)
	{
		int course = courses.Get(i);
		char display[32];
		FormatCourseName(client, course, display, sizeof(display));
		menu.AddItem(IntToStringEx(course), display);
	}
	menu.Display(client, MENU_TIME_FOREVER);
}



// =====[ PRIVATE ]=====

static bool IsReplayMenuAvailable(int client)
{
	if (gH_DB != null)
	{
		return true;
	}
	GOKZ_PrintToChat(client, true, "%t", "Replays Unavailable");
	GOKZ_PlayErrorSound(client);
	return false;
}

static void ReplayScope_SetCurrentMap(int client)
{
	ReplayScope_SetMap(client, gC_CurrentMap);
}

static void ReplayScope_SetAll(int client)
{
	scopeAll[client] = true;
	scopeMap[client][0] = '\0';
}

static void ReplayScope_GetFilterMap(int client, char[] buffer, int maxlength)
{
	if (scopeAll[client])
	{
		buffer[0] = '\0';
		return;
	}
	strcopy(buffer, maxlength, scopeMap[client]);
}

static void ReplayScope_Toggle(int client)
{
	if (scopeAll[client])
	{
		ReplayScope_SetCurrentMap(client);
		return;
	}
	ReplayScope_SetAll(client);
}

static ReplayMenu GetParentReplayMenu(int client, ReplayMenu kind)
{
	switch (kind)
	{
		case ReplayMenu_RunMaps, ReplayMenu_JumpModes, ReplayMenu_RecentList:
		{
			return ReplayMenu_Hub;
		}
		case ReplayMenu_RunModes:
		{
			return scopeAll[client] ? ReplayMenu_RunMaps : ReplayMenu_Hub;
		}
		case ReplayMenu_RunCourses:
		{
			return ReplayMenu_RunModes;
		}
		case ReplayMenu_RunList:
		{
			return ReplayMenu_RunCourses;
		}
		case ReplayMenu_JumpTypes:
		{
			return ReplayMenu_JumpModes;
		}
		case ReplayMenu_JumpList:
		{
			return ReplayMenu_JumpTypes;
		}
	}
	return ReplayMenu_None;
}

static void OpenRunFlow(int client, bool mine)
{
	listMine[client] = mine;
	if (scopeAll[client])
	{
		OpenReplayMenu(client, ReplayMenu_RunMaps);
		return;
	}
	OpenReplayMenu(client, ReplayMenu_RunModes);
}

static void OpenRunList(int client)
{
	if (listMine[client])
	{
		int steamID = GetSteamAccountID(client);
		DB_OpenMyRunList(client, steamID, scopeMap[client], listMode[client], listCourse[client]);
		return;
	}
	DB_OpenRunList(client, scopeMap[client], listMode[client], listCourse[client]);
}

static void SelectHubItem(int client, const char[] info)
{
	if (StrEqual(info, ITEM_INFO_HUB_RUNS))
	{
		OpenReplayMenu(client, ReplayMenu_Runs);
	}
	else if (StrEqual(info, ITEM_INFO_HUB_MINE))
	{
		OpenReplayMenu(client, ReplayMenu_MyRuns);
	}
	else if (StrEqual(info, ITEM_INFO_HUB_JUMPS))
	{
		OpenReplayMenu(client, ReplayMenu_JumpModes);
	}
	else if (StrEqual(info, ITEM_INFO_HUB_RECENT))
	{
		OpenReplayMenu(client, ReplayMenu_RecentList);
	}
	else if (StrEqual(info, ITEM_INFO_HUB_SCOPE))
	{
		ReplayScope_Toggle(client);
		OpenReplayMenu(client, ReplayMenu_Hub);
	}
}

static void NotifyNoRunMaps(int client)
{
	if (listMine[client])
	{
		GOKZ_PrintToChat(client, true, "%t", "No Replays Found (Mine, Any Map)");
	}
	else
	{
		GOKZ_PrintToChat(client, true, "%t", "No Replays Found (Any Map)");
	}
	GOKZ_PlayErrorSound(client);
}

static void DisplayReplayHubMenu(int client)
{
	ReplayMenu_SetCurrent(client, ReplayMenu_Hub);
	Menu menu = new Menu(MenuHandler_ReplayHub);
	char scopeName[64];
	ReplayScope_FormatName(client, scopeName, sizeof(scopeName));
	menu.SetTitle("%T", "Replay Menu (Hub) - Title", client, scopeName);

	char display[64];
	FormatEx(display, sizeof(display), "%T", "Replay Menu - Run Replays", client);
	menu.AddItem(ITEM_INFO_HUB_RUNS, display);
	FormatEx(display, sizeof(display), "%T", "Replay Menu - My Run Replays", client);
	menu.AddItem(ITEM_INFO_HUB_MINE, display);
	FormatEx(display, sizeof(display), "%T", "Replay Menu - Jump Replays", client);
	menu.AddItem(ITEM_INFO_HUB_JUMPS, display);
	FormatEx(display, sizeof(display), "%T", "Replay Menu - Recent Replays", client);
	menu.AddItem(ITEM_INFO_HUB_RECENT, display);
	FormatScopeToggle(client, display, sizeof(display));
	menu.AddItem(ITEM_INFO_HUB_SCOPE, display);
	menu.Display(client, MENU_TIME_FOREVER);
}

static void FormatScopeToggle(int client, char[] buffer, int maxlength)
{
	if (scopeAll[client])
	{
		FormatEx(buffer, maxlength, "%T", "Replay Menu - Show Current Map", client, gC_CurrentMap);
		return;
	}
	FormatEx(buffer, maxlength, "%T", "Replay Menu - Show All Maps", client);
}

static void DisplayRunModeMenu(int client)
{
	ReplayMenu_SetCurrent(client, ReplayMenu_RunModes);
	Menu menu = new Menu(MenuHandler_RunModes);
	char section[64];
	FormatRunSectionName(client, section, sizeof(section));
	menu.SetTitle("%T", "Replay Menu (Mode) - Title", client, section, scopeMap[client]);
	GOKZ_MenuAddModeItems(client, menu, false);
	menu.Display(client, MENU_TIME_FOREVER);
}

static void DisplayJumpModeMenu(int client)
{
	ReplayMenu_SetCurrent(client, ReplayMenu_JumpModes);
	Menu menu = new Menu(MenuHandler_JumpModes);
	char section[64];
	FormatEx(section, sizeof(section), "%T", "Replay Menu - Jump Replays", client);
	char scopeName[64];
	ReplayScope_FormatName(client, scopeName, sizeof(scopeName));
	menu.SetTitle("%T", "Replay Menu (Mode) - Title", client, section, scopeName);
	GOKZ_MenuAddModeItems(client, menu, false);
	menu.Display(client, MENU_TIME_FOREVER);
}

static void DisplayJumpTypeMenu(int client)
{
	ReplayMenu_SetCurrent(client, ReplayMenu_JumpTypes);
	Menu menu = new Menu(MenuHandler_JumpTypes);
	char section[64];
	FormatEx(section, sizeof(section), "%T", "Replay Menu - Jump Replays", client);
	char scopeName[64];
	ReplayScope_FormatName(client, scopeName, sizeof(scopeName));
	menu.SetTitle("%T", "Replay Menu (Type) - Title", client, section, scopeName, gC_ModeNames[listMode[client]]);
	for (int jumpType = 0; jumpType < JUMPTYPE_COUNT - 3; jumpType++)
	{
		menu.AddItem(IntToStringEx(jumpType), gC_JumpTypes[jumpType]);
	}
	menu.Display(client, MENU_TIME_FOREVER);
}
