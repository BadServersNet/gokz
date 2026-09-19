/*
	Entry points for playing a replay that may still have to be downloaded.
	Remembers which menu a request came from so it can be reopened when playback fails.
*/



enum PlaybackOrigin
{
	PlaybackOrigin_None = 0,
	PlaybackOrigin_Menu,
	PlaybackOrigin_Native
}

static PlaybackOrigin playbackOrigin[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void Playback_SetOrigin(int client, PlaybackOrigin origin)
{
	playbackOrigin[client] = origin;
}

void Playback_OnFailed(int client)
{
	PlaybackOrigin origin = playbackOrigin[client];
	playbackOrigin[client] = PlaybackOrigin_None;
	if (!IsValidClient(client))
	{
		return;
	}

	switch (origin)
	{
		case PlaybackOrigin_Menu:
		{
			ReopenReplayMenu(client);
		}
		case PlaybackOrigin_Native:
		{
			Call_OnPlaybackFailed(client);
		}
	}
}

void RequestReplayPlayback(int client, const char[] key, int fileSize, bool inStore)
{
	if (!CanClientLoadReplay(client))
	{
		Playback_OnFailed(client);
		return;
	}

	char cachePath[PLATFORM_MAX_PATH];
	KeyToCachePath(key, cachePath, sizeof(cachePath));
	bool cached = FileExists(cachePath) && (fileSize <= 0 || FileSize(cachePath) == fileSize);
	if (cached)
	{
		StartReplayFromCache(client, cachePath);
		return;
	}

	if (!inStore || !Store_IsReady())
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Not Available");
		GOKZ_PlayErrorSound(client);
		Playback_OnFailed(client);
		return;
	}

	Store_RequestDownload(client, key, fileSize);
}

void StartReplayFromCache(int client, const char[] cachePath)
{
	if (!StartReplayBot(client, cachePath))
	{
		Playback_OnFailed(client);
		return;
	}
	playbackOrigin[client] = PlaybackOrigin_None;
}

bool RequestRunPlayback(int client, int timeID)
{
	if (gH_DB == null || !CanClientLoadReplay(client))
	{
		return false;
	}
	playbackOrigin[client] = PlaybackOrigin_Native;
	DB_LookupRunReplay(client, timeID);
	return true;
}

void RequestCodePlayback(int client, const char[] code)
{
	if (gH_DB == null)
	{
		GOKZ_PrintToChat(client, true, "%t", "Replays Unavailable");
		GOKZ_PlayErrorSound(client);
		return;
	}
	if (!CanClientLoadReplay(client))
	{
		return;
	}
	playbackOrigin[client] = PlaybackOrigin_None;
	DB_LookupReplayByCode(client, code);
}

bool RequestJumpPlayback(int client, int jumpID)
{
	if (gH_DB == null || !CanClientLoadReplay(client))
	{
		return false;
	}
	playbackOrigin[client] = PlaybackOrigin_Native;
	DB_LookupJumpReplay(client, jumpID);
	return true;
}



// =====[ EVENTS ]=====

void OnClientPutInServer_PlaybackRequest(int client)
{
	playbackOrigin[client] = PlaybackOrigin_None;
}
