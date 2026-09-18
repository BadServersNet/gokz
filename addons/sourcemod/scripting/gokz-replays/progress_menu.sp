/*
	Live panel listing every tracked player's map progress, best first.
*/



#define PROGRESS_MENU_MAX_ROWS 8
#define PROGRESS_MENU_ITEM_EXIT 1

enum struct ProgressRow
{
	int client;
	float progress;
}

static bool progressMenuOpen[MAXPLAYERS + 1];
static Handle progressMenuTimer[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void ProgressMenu_Toggle(int client)
{
	if (progressMenuOpen[client])
	{
		CloseProgressMenu(client);
		return;
	}
	progressMenuOpen[client] = true;
	ShowProgressMenu(client);
	progressMenuTimer[client] = CreateTimer(1.0, Timer_RefreshProgressMenu, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}



// =====[ EVENTS ]=====

void OnClientPutInServer_ProgressMenu(int client)
{
	progressMenuOpen[client] = false;
	progressMenuTimer[client] = INVALID_HANDLE;
}

void OnClientDisconnect_ProgressMenu(int client)
{
	CloseProgressMenu(client);
}

void OnMapEnd_ProgressMenu()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		progressMenuOpen[client] = false;
		progressMenuTimer[client] = INVALID_HANDLE;
	}
}

public Action Timer_RefreshProgressMenu(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client) || !progressMenuOpen[client])
	{
		return Plugin_Stop;
	}
	ShowProgressMenu(client);
	return Plugin_Continue;
}

public int PanelHandler_ProgressMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select && param2 == PROGRESS_MENU_ITEM_EXIT)
	{
		CloseProgressMenu(param1);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Exit)
	{
		CloseProgressMenu(param1);
	}
	return 0;
}



// =====[ PRIVATE ]=====

static void CloseProgressMenu(int client)
{
	progressMenuOpen[client] = false;
	if (progressMenuTimer[client] != INVALID_HANDLE)
	{
		KillTimer(progressMenuTimer[client]);
		progressMenuTimer[client] = INVALID_HANDLE;
	}
}

static void ShowProgressMenu(int client)
{
	ArrayList rows = CollectProgressRows();
	Panel panel = new Panel();
	char line[128];
	FormatEx(line, sizeof(line), "%T", "Progress Menu - Title", client);
	panel.SetTitle(line);

	if (rows.Length == 0)
	{
		FormatEx(line, sizeof(line), "%T", "Progress Menu - Empty", client);
		panel.DrawText(line);
	}
	int shown = rows.Length < PROGRESS_MENU_MAX_ROWS ? rows.Length : PROGRESS_MENU_MAX_ROWS;
	for (int i = 0; i < shown; i++)
	{
		ProgressRow row;
		rows.GetArray(i, row);
		FormatEx(line, sizeof(line), "%T", "Progress Menu - Row", client, i + 1, row.progress * 100.0, row.client);
		panel.DrawText(line);
	}
	delete rows;

	panel.DrawText(" ");
	FormatEx(line, sizeof(line), "%T", "Progress Menu - Exit", client);
	panel.DrawItem(line);
	panel.Send(client, PanelHandler_ProgressMenu, 2);
	delete panel;
}

static ArrayList CollectProgressRows()
{
	ArrayList rows = new ArrayList(sizeof(ProgressRow));
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!Progress_IsTracked(client))
		{
			continue;
		}
		ProgressRow row;
		row.client = client;
		row.progress = Progress_GetValue(client);
		rows.PushArray(row);
	}
	rows.SortCustom(SortRowsByProgress);
	return rows;
}

public int SortRowsByProgress(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList rows = view_as<ArrayList>(array);
	ProgressRow first;
	rows.GetArray(index1, first);
	ProgressRow second;
	rows.GetArray(index2, second);
	if (first.progress > second.progress)
	{
		return -1;
	}
	if (first.progress < second.progress)
	{
		return 1;
	}
	return 0;
}
