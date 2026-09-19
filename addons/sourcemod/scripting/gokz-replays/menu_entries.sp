/*
	Lists of replays (runs, jumps, recent) and the info panel used to watch or download one.
*/



#define ITEM_INFO_ENTRY_WATCH "watch"
#define ITEM_INFO_ENTRY_CODE "code"
#define ITEM_INFO_ENTRY_URL "url"

static ArrayList g_Entries[MAXPLAYERS + 1];
static int selectedEntry[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void DisplayReplayEntries(int client, ReplayMenu kind, ArrayList entries, int recordCount)
{
	if (entries.Length == 0)
	{
		NotifyNoEntries(client, kind);
		OpenParentReplayMenu(client, kind);
		return;
	}

	ReplayMenu_SetCurrent(client, kind);
	g_Entries[client].Clear();

	Menu menu = new Menu(MenuHandler_ReplayEntries);
	SetEntriesMenuTitle(client, menu, kind);
	for (int i = 0; i < entries.Length; i++)
	{
		ReplayEntry entry;
		entries.GetArray(i, entry);
		char display[128];
		FormatEntryDisplay(client, kind, entry, i, recordCount, display, sizeof(display));
		int index = g_Entries[client].PushArray(entry);
		menu.AddItem(IntToStringEx(index), display);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}



// =====[ EVENTS ]=====

void OnClientPutInServer_ReplayEntries(int client)
{
	if (g_Entries[client] == null)
	{
		g_Entries[client] = new ArrayList(sizeof(ReplayEntry));
	}
	g_Entries[client].Clear();
	selectedEntry[client] = -1;
}

public int MenuHandler_ReplayEntries(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		SelectEntry(param1, StringToInt(info));
	}
	ReplayMenu_HandleClose(menu, action, param1, param2, ReplayMenu_GetCurrent(param1));
	return 0;
}

public int MenuHandler_ReplayInfo(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		SelectInfoItem(param1, info);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ReopenReplayMenu(param1);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		ReplayMenu_SetCurrent(param1, ReplayMenu_None);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}



// =====[ PRIVATE ]=====

static void SetEntriesMenuTitle(int client, Menu menu, ReplayMenu kind)
{
	char scopeName[64];
	ReplayScope_FormatName(client, scopeName, sizeof(scopeName));
	int mode = ReplayMenu_GetMode(client);

	switch (kind)
	{
		case ReplayMenu_RunList:
		{
			char section[64];
			FormatRunSectionName(client, section, sizeof(section));
			char map[64];
			ReplayScope_GetRunMap(client, map, sizeof(map));
			char courseName[32];
			FormatCourseName(client, ReplayMenu_GetCourse(client), courseName, sizeof(courseName));
			menu.SetTitle("%T", "Replay Menu (Run List) - Title", client, section, map, gC_ModeNames[mode], courseName);
		}
		case ReplayMenu_JumpList:
		{
			char section[64];
			FormatEx(section, sizeof(section), "%T", "Replay Menu - Jump Replays", client);
			int jumpType = ReplayMenu_GetJumpType(client);
			menu.SetTitle("%T", "Replay Menu (Jump List) - Title", client, section, scopeName, gC_ModeNames[mode], gC_JumpTypes[jumpType]);
		}
		case ReplayMenu_RecentList:
		{
			char section[64];
			FormatEx(section, sizeof(section), "%T", "Replay Menu - Recent Replays", client);
			menu.SetTitle("%T", "Replay Menu (List) - Title", client, section, scopeName);
		}
	}
}

static void NotifyNoEntries(int client, ReplayMenu kind)
{
	char scopeName[64];
	ReplayScope_FormatName(client, scopeName, sizeof(scopeName));
	int mode = ReplayMenu_GetMode(client);

	switch (kind)
	{
		case ReplayMenu_RunList:
		{
			NotifyNoRunEntries(client);
		}
		case ReplayMenu_JumpList:
		{
			int jumpType = ReplayMenu_GetJumpType(client);
			GOKZ_PrintToChat(client, true, "%t", "No Jump Replays Found", gC_ModeNames[mode], gC_JumpTypes[jumpType], scopeName);
		}
		case ReplayMenu_RecentList:
		{
			GOKZ_PrintToChat(client, true, "%t", "No Recent Replays Found", scopeName);
		}
	}
	GOKZ_PlayErrorSound(client);
}

static void NotifyNoRunEntries(int client)
{
	char map[64];
	ReplayScope_GetRunMap(client, map, sizeof(map));
	char courseName[32];
	FormatCourseName(client, ReplayMenu_GetCourse(client), courseName, sizeof(courseName));
	if (ReplayMenu_IsMine(client))
	{
		GOKZ_PrintToChat(client, true, "%t", "No Replays Found (Mine)", map, courseName);
		return;
	}
	GOKZ_PrintToChat(client, true, "%t", "No Replays Found (Course)", map, courseName);
}

static void FormatEntryDisplay(int client, ReplayMenu kind, ReplayEntry entry, int index, int recordCount, char[] buffer, int maxlength)
{
	switch (kind)
	{
		case ReplayMenu_RunList:
		{
			FormatRunListDisplay(client, entry, index, recordCount, buffer, maxlength);
		}
		case ReplayMenu_JumpList:
		{
			FormatJumpListDisplay(client, entry, index + 1, buffer, maxlength);
		}
		case ReplayMenu_RecentList:
		{
			FormatRecentDisplay(client, entry, buffer, maxlength);
		}
	}
}

static void FormatRunListDisplay(int client, ReplayEntry entry, int index, int recordCount, char[] buffer, int maxlength)
{
	int timeType = GOKZ_GetTimeTypeEx(entry.teleports);
	if (index < recordCount)
	{
		FormatEx(buffer, maxlength, "[SR %s] %s - %s", gC_TimeTypeNames[timeType], GOKZ_FormatTime(GOKZ_DB_TimeIntToFloat(entry.runTimeMS)), entry.alias);
		return;
	}
	if (ReplayMenu_IsMine(client))
	{
		FormatEx(buffer, maxlength, "#%d %s %s - %s", entry.rank, GOKZ_FormatTime(GOKZ_DB_TimeIntToFloat(entry.runTimeMS)), gC_TimeTypeNames[timeType], entry.created);
		return;
	}
	FormatEx(buffer, maxlength, "#%d %s %s - %s", entry.rank, GOKZ_FormatTime(GOKZ_DB_TimeIntToFloat(entry.runTimeMS)), gC_TimeTypeNames[timeType], entry.alias);
}

static void FormatJumpListDisplay(int client, ReplayEntry entry, int rank, char[] buffer, int maxlength)
{
	char jump[48];
	FormatJumpSummary(client, entry, jump, sizeof(jump));
	char mapSuffix[72];
	FormatMapSuffix(client, entry, mapSuffix, sizeof(mapSuffix));
	FormatEx(buffer, maxlength, "#%d %s - %s%s", rank, jump, entry.alias, mapSuffix);
}

static void FormatRecentDisplay(int client, ReplayEntry entry, char[] buffer, int maxlength)
{
	char summary[64];
	if (entry.replayType == ReplayType_Run)
	{
		FormatRunSummary(entry, summary, sizeof(summary));
	}
	else
	{
		FormatJumpSummary(client, entry, summary, sizeof(summary));
	}
	char mapSuffix[72];
	FormatMapSuffix(client, entry, mapSuffix, sizeof(mapSuffix));
	FormatEx(buffer, maxlength, "[%s] %s - %s%s", gC_ModeNamesShort[entry.mode], summary, entry.alias, mapSuffix);
}

static void FormatRunSummary(ReplayEntry entry, char[] buffer, int maxlength)
{
	int timeType = GOKZ_GetTimeTypeEx(entry.teleports);
	if (entry.course == 0)
	{
		FormatEx(buffer, maxlength, "#%d %s %s", entry.rank, GOKZ_FormatTime(GOKZ_DB_TimeIntToFloat(entry.runTimeMS)), gC_TimeTypeNames[timeType]);
		return;
	}
	FormatEx(buffer, maxlength, "#%d %s %s B%d", entry.rank, GOKZ_FormatTime(GOKZ_DB_TimeIntToFloat(entry.runTimeMS)), gC_TimeTypeNames[timeType], entry.course);
}

static void FormatJumpSummary(int client, ReplayEntry entry, char[] buffer, int maxlength)
{
	float distance = float(entry.distance) / GOKZ_DB_JS_DISTANCE_PRECISION;
	if (entry.block > 0)
	{
		FormatEx(buffer, maxlength, "%s %d %T (%.2f)", gC_JumpTypesShort[entry.jumpType], entry.block, "Block", client, distance);
		return;
	}
	FormatEx(buffer, maxlength, "%s %.2f", gC_JumpTypesShort[entry.jumpType], distance);
}

static void FormatMapSuffix(int client, ReplayEntry entry, char[] buffer, int maxlength)
{
	if (!ReplayScope_IsAll(client))
	{
		buffer[0] = '\0';
		return;
	}
	char mapName[64];
	FormatEntryMapName(client, entry, mapName, sizeof(mapName));
	FormatEx(buffer, maxlength, " (%s)", mapName);
}

static void FormatEntryMapName(int client, ReplayEntry entry, char[] buffer, int maxlength)
{
	if (entry.mapName[0] != '\0')
	{
		strcopy(buffer, maxlength, entry.mapName);
		return;
	}
	FormatEx(buffer, maxlength, "%T", "Replay Info - Unknown Map", client);
}

static bool IsEntryOnThisMap(ReplayEntry entry)
{
	bool mapUnknown = entry.mapName[0] == '\0';
	return mapUnknown || StrEqual(entry.mapName, gC_CurrentMap, false);
}

static bool CanDownloadEntry(ReplayEntry entry)
{
	return entry.inStore && Store_IsReady() && Store_HasPublicUrl();
}

static bool GetSelectedEntry(int client, ReplayEntry entry)
{
	int index = selectedEntry[client];
	if (index < 0 || index >= g_Entries[client].Length)
	{
		return false;
	}
	g_Entries[client].GetArray(index, entry);
	return true;
}

static void SelectEntry(int client, int index)
{
	if (index < 0 || index >= g_Entries[client].Length)
	{
		return;
	}
	selectedEntry[client] = index;
	ReplayEntry entry;
	g_Entries[client].GetArray(index, entry);
	ShowEntryInfo(client, entry);
}

static void SelectInfoItem(int client, const char[] info)
{
	if (StrEqual(info, ITEM_INFO_ENTRY_WATCH))
	{
		WatchSelectedEntry(client);
	}
	else if (StrEqual(info, ITEM_INFO_ENTRY_CODE))
	{
		PrintSelectedEntryCode(client);
	}
	else if (StrEqual(info, ITEM_INFO_ENTRY_URL))
	{
		PrintSelectedEntryUrl(client);
	}
}

static void WatchSelectedEntry(int client)
{
	ReplayEntry entry;
	if (!GetSelectedEntry(client, entry))
	{
		return;
	}
	if (!IsEntryOnThisMap(entry))
	{
		ShowEntryInfo(client, entry);
		return;
	}
	Playback_SetOrigin(client, PlaybackOrigin_Menu);
	RequestReplayPlayback(client, entry.objectKey, entry.fileSize, entry.inStore);
}

static void PrintSelectedEntryUrl(int client)
{
	ReplayEntry entry;
	if (!GetSelectedEntry(client, entry))
	{
		return;
	}
	if (CanDownloadEntry(entry))
	{
		PrintReplayUrl(client, SM_REPLY_TO_CHAT, entry.objectKey);
	}
	ShowEntryInfo(client, entry);
}

static void PrintSelectedEntryCode(int client)
{
	ReplayEntry entry;
	if (!GetSelectedEntry(client, entry))
	{
		return;
	}
	GOKZ_PrintToChat(client, true, "%t", "Replay Info - Code Chat", entry.code);
	PrintToConsole(client, "[KZ] Replay code: %s", entry.code);
	ShowEntryInfo(client, entry);
}

static void ShowEntryInfo(int client, ReplayEntry entry)
{
	char title[512];
	FormatEntryInfoTitle(client, entry, title, sizeof(title));
	Menu menu = new Menu(MenuHandler_ReplayInfo);
	menu.SetTitle("%s", title);

	char display[64];
	bool onThisMap = IsEntryOnThisMap(entry);
	FormatEx(display, sizeof(display), "%T", "Replay Info - Watch", client);
	menu.AddItem(ITEM_INFO_ENTRY_WATCH, display, onThisMap ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(display, sizeof(display), "%T", "Replay Info - Output Code", client);
	menu.AddItem(ITEM_INFO_ENTRY_CODE, display);
	bool canDownload = CanDownloadEntry(entry);
	FormatEx(display, sizeof(display), "%T", "Replay Info - Download URL", client);
	menu.AddItem(ITEM_INFO_ENTRY_URL, display, canDownload ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

static void FormatEntryInfoTitle(int client, ReplayEntry entry, char[] title, int maxlength)
{
	char mapName[64];
	FormatEntryMapName(client, entry, mapName, sizeof(mapName));
	char record[256];
	if (entry.replayType == ReplayType_Run)
	{
		FormatRunInfo(client, entry, record, sizeof(record));
	}
	else
	{
		FormatJumpInfo(client, entry, record, sizeof(record));
	}

	FormatEx(title, maxlength, "%T\n \n%T\n%T\n%T\n%s\n%T\n%T\n ",
		"Replay Info - Title", client,
		"Replay Info - Player", client, entry.alias,
		"Replay Info - Map", client, mapName,
		"Replay Info - Mode", client, gC_ModeNames[entry.mode],
		record,
		"Replay Info - Recorded", client, entry.created,
		"Replay Info - Code", client, entry.code);
	if (IsEntryOnThisMap(entry))
	{
		return;
	}
	Format(title, maxlength, "%s\n%T\n ", title, "Replay Info - Wrong Map", client, entry.mapName);
}

static void FormatRunInfo(int client, ReplayEntry entry, char[] buffer, int maxlength)
{
	char courseName[32];
	FormatCourseName(client, entry.course, courseName, sizeof(courseName));
	int timeType = GOKZ_GetTimeTypeEx(entry.teleports);
	FormatEx(buffer, maxlength, "%T\n%T\n%T",
		"Replay Info - Course", client, courseName,
		"Replay Info - Run", client, GOKZ_FormatTime(GOKZ_DB_TimeIntToFloat(entry.runTimeMS)), gC_TimeTypeNames[timeType], entry.teleports,
		"Replay Info - Rank", client, entry.rank, gC_TimeTypeNames[timeType]);
}

static void FormatJumpInfo(int client, ReplayEntry entry, char[] buffer, int maxlength)
{
	char jump[128];
	float distance = float(entry.distance) / GOKZ_DB_JS_DISTANCE_PRECISION;
	if (entry.block > 0)
	{
		FormatEx(jump, sizeof(jump), "%T", "Replay Info - Block Jump", client, gC_JumpTypes[entry.jumpType], entry.block, distance);
	}
	else
	{
		FormatEx(jump, sizeof(jump), "%T", "Replay Info - Jump", client, gC_JumpTypes[entry.jumpType], distance);
	}

	float sync = float(entry.sync) / GOKZ_DB_JS_SYNC_PRECISION;
	float pre = float(entry.pre) / GOKZ_DB_JS_PRE_PRECISION;
	float max = float(entry.max) / GOKZ_DB_JS_MAX_PRECISION;
	FormatEx(buffer, maxlength, "%s\n%T", jump, "Replay Info - Jump Stats", client, entry.strafes, sync, pre, max);
}
