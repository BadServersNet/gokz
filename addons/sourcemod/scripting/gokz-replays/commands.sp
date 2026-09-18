void RegisterCommands()
{
	RegConsoleCmd("sm_replay", CommandReplay, "[KZ] Open the replay menu, or play a replay by code. Usage: !replay [all|map|code]");
	RegConsoleCmd("sm_replays", CommandReplay, "[KZ] Open the replay menu, or play a replay by code. Usage: !replays [all|map|code]");
	RegConsoleCmd("sm_runreplays", CommandRunReplays, "[KZ] Browse run replays. Usage: !runreplays [all|map]");
	RegConsoleCmd("sm_myreplays", CommandMyReplays, "[KZ] Browse your own run replays. Usage: !myreplays [all|map]");
	RegConsoleCmd("sm_jumpreplays", CommandJumpReplays, "[KZ] Browse jump replays. Usage: !jumpreplays [all|map]");
	RegConsoleCmd("sm_jsreplays", CommandJumpReplays, "[KZ] Browse jump replays. Usage: !jsreplays [all|map]");
	RegConsoleCmd("sm_recentreplays", CommandRecentReplays, "[KZ] Browse the most recent replays. Usage: !recentreplays [all|map]");
	RegConsoleCmd("sm_rrp", CommandRecentReplays, "[KZ] Browse the most recent replays. Usage: !rrp [all|map]");
	RegConsoleCmd("sm_progressreplay", CommandProgressReplay, "[KZ] Measure your map progress against a specific replay instead of the server record. Usage: !progressreplay [code]");
	RegConsoleCmd("sm_progressmenu", CommandProgressMenu, "[KZ] Toggle the live map progress leaderboard.");
	RegConsoleCmd("sm_timediff", CommandTimeDiff, "[KZ] Toggle periodic time diff messages against your PB replay. Usage: !timediff [seconds|auto|off]");
	RegConsoleCmd("sm_replaycontrols", CommandReplayControls, "[KZ] Toggle the replay control menu.");
	RegConsoleCmd("sm_rpcontrols", CommandReplayControls, "[KZ] Toggle the replay control menu.");
	RegConsoleCmd("sm_replaygoto", CommandReplayGoto, "[KZ] Skip to a specific time in the replay (hh:mm:ss).");
	RegConsoleCmd("sm_rpgoto", CommandReplayGoto, "[KZ] Skip to a specific time in the replay (hh:mm:ss).");
	RegAdminCmd("sm_replaystore_status", CommandReplayStoreStatus, ADMFLAG_ROOT, "[KZ] Show the replay store upload and download queues.");
	RegAdminCmd("sm_replaystore_check", CommandReplayStoreCheck, ADMFLAG_ROOT, "[KZ] Test the replay store credentials and bucket.");
	RegAdminCmd("sm_replaystore_flush", CommandReplayStoreFlush, ADMFLAG_ROOT, "[KZ] Rescan the replay outbox and retry pending uploads.");
	RegAdminCmd("sm_replaystore_url", CommandReplayStoreUrl, ADMFLAG_ROOT, "[KZ] Print the public download URL for a replay. Usage: sm_replaystore_url [code or key]");
}


public Action CommandReplayStoreUrl(int client, int args)
{
	if (!Store_IsReady() || !Store_HasPublicUrl())
	{
		ReplyToCommand(client, "[KZ] Download URLs require gokz_replay_store_public_url to be set.");
		return Plugin_Handled;
	}
	if (args < 1)
	{
		if (gH_DB == null)
		{
			ReplyToCommand(client, "[KZ] Usage: sm_replaystore_url <code or key>");
			return Plugin_Handled;
		}
		DB_PrintRecentReplayKeys(client);
		return Plugin_Handled;
	}

	char input[RP_MAX_KEY_LENGTH];
	GetCmdArg(1, input, sizeof(input));
	bool isKey = FindCharInString(input, '/') != -1;
	if (isKey)
	{
		PrintReplayUrl(client, GetCmdReplySource(), input);
		return Plugin_Handled;
	}

	char code[RP_CODE_BUFFER];
	if (!NormalizeReplayCode(input, code, sizeof(code)))
	{
		ReplyToCommand(client, "[KZ] \"%s\" is not a replay code or object key.", input);
		return Plugin_Handled;
	}
	if (gH_DB == null)
	{
		ReplyToCommand(client, "[KZ] The database is not connected.");
		return Plugin_Handled;
	}
	DB_PrintUrlForCode(client, code);
	return Plugin_Handled;
}

void PrintReplayUrl(int client, ReplySource source, const char[] key)
{
	char url[1024];
	Store_BuildPublicUrl(key, url, sizeof(url));
	PrintToCaller(client, "[KZ] Download URL for %s:", key);
	PrintToCaller(client, "%s", url);
	if (client != 0 && source == SM_REPLY_TO_CHAT)
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Store - Check Console");
	}
}

void PrintToCaller(int client, const char[] format, any ...)
{
	char message[1024];
	VFormat(message, sizeof(message), format, 3);
	if (client == 0)
	{
		PrintToServer(message);
		return;
	}
	PrintToConsole(client, message);
}

public Action CommandReplayStoreStatus(int client, int args)
{
	Store_PrintUploadStatus(client);
	Store_PrintDownloadStatus(client);
	return Plugin_Handled;
}

public Action CommandReplayStoreCheck(int client, int args)
{
	if (!Store_IsReady())
	{
		ReplyToCommand(client, "[KZ] The replay store is disabled or not configured.");
		return Plugin_Handled;
	}

	int userid = client == 0 ? 0 : GetClientUserId(client);
	gH_S3.List("gokz-replaystore-check/", OnReplayStoreCheckCompleted, userid, 1);
	ReplyToCommand(client, "[KZ] Checking the replay store...");
	return Plugin_Handled;
}

public Action CommandReplayStoreFlush(int client, int args)
{
	Store_FlushUploads();
	ReplyToCommand(client, "[KZ] Replay outbox rescanned.");
	return Plugin_Handled;
}

public void OnReplayStoreCheckCompleted(S3Client s3, S3Response response, S3ObjectList objects, const char[] nextToken, any userid)
{
	int client = userid == 0 ? 0 : GetClientOfUserId(userid);
	if (userid != 0 && !IsValidClient(client))
	{
		return;
	}

	char error[256];
	response.GetError(error, sizeof(error));
	char message[512];
	FormatReplayStoreCheckResult(response.Status, response.HttpStatus, error, message, sizeof(message));
	PrintReplayStoreCheckResult(client, message);
}

static void FormatReplayStoreCheckResult(S3Status status, int httpStatus, const char[] error, char[] buffer, int maxlength)
{
	if (status == S3Status_Ok)
	{
		FormatEx(buffer, maxlength, "[KZ] Replay store check passed: the credentials and bucket are valid.");
		return;
	}
	if (httpStatus == 403)
	{
		FormatEx(buffer, maxlength, "[KZ] Replay store check failed (403): check the access key, secret key and server clock. %s", error);
		return;
	}
	FormatEx(buffer, maxlength, "[KZ] Replay store check failed (HTTP %d): %s", httpStatus, error);
}

static void PrintReplayStoreCheckResult(int client, const char[] message)
{
	if (client == 0)
	{
		PrintToServer(message);
		return;
	}
	PrintToConsole(client, message);
	GOKZ_PrintToChat(client, false, "%s", message);
}

public Action CommandReplay(int client, int args)
{
	if (args < 1)
	{
		OpenReplayMenuWithScope(client, "", ReplayMenu_Hub);
		return Plugin_Handled;
	}

	char input[64];
	GetCmdArg(1, input, sizeof(input));
	char code[RP_CODE_BUFFER];
	bool isCode = NormalizeReplayCode(input, code, sizeof(code));
	if (isCode)
	{
		RequestCodePlayback(client, code);
		return Plugin_Handled;
	}
	OpenReplayMenuWithScope(client, input, ReplayMenu_Hub);
	return Plugin_Handled;
}

public Action CommandRunReplays(int client, int args)
{
	return OpenScopedReplayMenu(client, ReplayMenu_Runs);
}

public Action CommandMyReplays(int client, int args)
{
	return OpenScopedReplayMenu(client, ReplayMenu_MyRuns);
}

public Action CommandJumpReplays(int client, int args)
{
	return OpenScopedReplayMenu(client, ReplayMenu_JumpModes);
}

public Action CommandRecentReplays(int client, int args)
{
	return OpenScopedReplayMenu(client, ReplayMenu_RecentList);
}

static Action OpenScopedReplayMenu(int client, ReplayMenu kind)
{
	char scopeArg[64];
	GetCmdArg(1, scopeArg, sizeof(scopeArg));
	OpenReplayMenuWithScope(client, scopeArg, kind);
	return Plugin_Handled;
}

public Action CommandProgressReplay(int client, int args)
{
	if (args < 1)
	{
		Progress_ResetClientRoute(client, true);
		return Plugin_Handled;
	}

	char input[32];
	GetCmdArg(1, input, sizeof(input));
	char code[RP_CODE_BUFFER];
	if (!NormalizeReplayCode(input, code, sizeof(code)))
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Code Invalid");
		GOKZ_PlayErrorSound(client);
		return Plugin_Handled;
	}
	Progress_RequestClientRoute(client, code);
	return Plugin_Handled;
}

public Action CommandProgressMenu(int client, int args)
{
	ProgressMenu_Toggle(client);
	return Plugin_Handled;
}

public Action CommandTimeDiff(int client, int args)
{
	if (args < 1)
	{
		TimeDiff_Toggle(client);
		return Plugin_Handled;
	}

	char input[16];
	GetCmdArg(1, input, sizeof(input));
	if (StrEqual(input, "off", false))
	{
		TimeDiff_Disable(client);
		return Plugin_Handled;
	}
	if (StrEqual(input, "auto", false))
	{
		TimeDiff_SetInterval(client, 0);
		return Plugin_Handled;
	}
	int seconds = StringToInt(input);
	if (seconds < 1 || seconds > TIMEDIFF_INTERVAL_MAX)
	{
		GOKZ_PrintToChat(client, true, "%t", "Time Diff - Usage", TIMEDIFF_INTERVAL_MAX);
		GOKZ_PlayErrorSound(client);
		return Plugin_Handled;
	}
	TimeDiff_SetInterval(client, seconds);
	return Plugin_Handled;
}

public Action CommandReplayControls(int client, int args)
{
	ToggleReplayControls(client);
	return Plugin_Handled;
}

public Action CommandReplayGoto(int client, int args)
{
	int seconds;
	char timeString[32], split[3][32];
	
	GetCmdArgString(timeString, sizeof(timeString));
	int res = ExplodeString(timeString, ":", split, 3, 32, false);
	switch (res)
	{
		case 1:
		{
			seconds = StringToInt(split[0]);
		}
		
		case 2:
		{
			seconds = StringToInt(split[0]) * 60 + StringToInt(split[1]);
		}
		
		case 3:
		{
			seconds = StringToInt(split[0]) * 3600 + StringToInt(split[1]) * 60 + StringToInt(split[2]);
		}
		
		default:
		{
			GOKZ_PrintToChat(client, true, "%t", "Replay Controls - Invalid Time");
			return Plugin_Handled;
		}
	}
	
	TrySkipToTime(client, seconds);
	return Plugin_Handled;
}
