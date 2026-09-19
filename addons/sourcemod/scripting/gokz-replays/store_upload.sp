/*
	Serial upload queue backed by outbox markers on disk.
	A marker exists for every cached replay that still has to be uploaded,
	so pending uploads survive map changes and restarts. A failed upload
	holds the whole queue and is retried with backoff until it succeeds.
*/



enum struct UploadJob
{
	char objectKey[RP_MAX_KEY_LENGTH];
	int replayType;
	int recordID;
	int steamID;
	int fileSize;
	char map[64];
	int attempt;
	bool registeredLocally;
	int token;
}

static ArrayList g_UploadQueue;
static StringMap g_QueuedKeys;
static bool g_UploadInFlight;
static int g_UploadToken;
static Handle g_UploadBackoffTimer;
static char g_UploadLastError[256];
static int g_UploadLastStatus;



// =====[ PUBLIC ]=====

void Store_EnqueueUpload(const char[] key, int replayType, int recordID, int steamID, const char[] map)
{
	char cachePath[PLATFORM_MAX_PATH];
	KeyToCachePath(key, cachePath, sizeof(cachePath));
	char markerPath[PLATFORM_MAX_PATH];
	KeyToMarkerPath(key, markerPath, sizeof(markerPath));

	UploadJob job;
	strcopy(job.objectKey, sizeof(UploadJob::objectKey), key);
	job.replayType = replayType;
	job.recordID = recordID;
	job.steamID = steamID;
	job.fileSize = FileSize(cachePath);
	strcopy(job.map, sizeof(UploadJob::map), map);

	CreateMarker(markerPath);
	if (IsUploadQueued(key))
	{
		LogMessage("Replay upload of \"%s\" is already queued.", key);
		return;
	}
	g_UploadQueue.PushArray(job);
	g_QueuedKeys.SetValue(key, true);
	LogMessage("Queued replay upload \"%s\" (type %d, record %d, steamid %d, map %s, %d bytes, %d queued).", key, replayType, recordID, steamID, job.map, job.fileSize, g_UploadQueue.Length);
	TryStartNextUpload();
}

bool Store_ImportReplay(const char[] sourcePath, int replayType, int recordID, int steamID, const char[] map, int timestamp, int mode, int style, char[] key, int maxlength)
{
	if (!FormatImportKey(key, maxlength, replayType, recordID, steamID, map, timestamp, mode, style))
	{
		LogError("Cannot import replay \"%s\": unsupported replay type %d.", sourcePath, replayType);
		return false;
	}

	char cachePath[PLATFORM_MAX_PATH];
	KeyToCachePath(key, cachePath, sizeof(cachePath));
	EnsureDirectoryForPath(cachePath);
	if (!CopyReplayFile(sourcePath, cachePath))
	{
		return false;
	}

	LogMessage("Imported replay \"%s\" as \"%s\".", sourcePath, key);
	Store_EnqueueUpload(key, replayType, recordID, steamID, map);
	return true;
}

int Store_GetPendingUploadCount()
{
	return g_UploadQueue.Length;
}

int Store_ClearUploadQueue()
{
	int dropped = g_UploadQueue.Length;
	for (int i = 0; i < g_UploadQueue.Length; i++)
	{
		UploadJob job;
		g_UploadQueue.GetArray(i, job);
		LogMessage("Dropping queued replay upload \"%s\" and its outbox marker.", job.objectKey);
		char markerPath[PLATFORM_MAX_PATH];
		KeyToMarkerPath(job.objectKey, markerPath, sizeof(markerPath));
		if (FileExists(markerPath))
		{
			DeleteFile(markerPath);
		}
	}
	g_UploadQueue.Clear();
	g_QueuedKeys.Clear();
	g_UploadInFlight = false;
	KillBackoffTimer();
	LogMessage("Cleared the replay upload queue (%d uploads dropped).", dropped);
	return dropped;
}

void Store_FlushUploads()
{
	LogMessage("Flushing replay uploads (%d queued).", g_UploadQueue.Length);
	for (int i = 0; i < g_UploadQueue.Length; i++)
	{
		UploadJob job;
		g_UploadQueue.GetArray(i, job);
		job.attempt = 0;
		g_UploadQueue.SetArray(i, job);
	}
	KillBackoffTimer();
	RescanOutbox();
	TryStartNextUpload();
}

void Store_PrintUploadStatus(int client)
{
	int queued = g_UploadQueue.Length;
	ReplyToCommand(client, "[KZ] Replay store: %s, client %s, configs %s", Store_IsEnabled() ? "enabled" : "disabled", gH_S3 != null ? "configured" : "not configured", Store_IsConfigLoaded() ? "loaded" : "not loaded yet");
	ReplyToCommand(client, "[KZ] Uploads queued: %d, in flight: %s, waiting for backoff: %s", queued, g_UploadInFlight ? "yes" : "no", g_UploadBackoffTimer != INVALID_HANDLE ? "yes" : "no");
	for (int i = 0; i < queued && i < 5; i++)
	{
		UploadJob job;
		g_UploadQueue.GetArray(i, job);
		ReplyToCommand(client, "[KZ]   %s (%d bytes, %d failed attempts)", job.objectKey, job.fileSize, job.attempt);
	}
	if (g_UploadLastError[0] != '\0')
	{
		ReplyToCommand(client, "[KZ] Last upload error (HTTP %d): %s", g_UploadLastStatus, g_UploadLastError);
	}
}

void Store_OnClientRebuilt()
{
	g_UploadInFlight = false;
	KillBackoffTimer();
}

void Store_OnClientReady()
{
	TryStartNextUpload();
}



// =====[ EVENTS ]=====

void OnPluginStart_StoreUpload()
{
	g_UploadQueue = new ArrayList(sizeof(UploadJob));
	g_QueuedKeys = new StringMap();
	g_UploadBackoffTimer = INVALID_HANDLE;
}

void OnMapStart_StoreUpload()
{
	EnsureStoreDirectories();
	RescanOutbox();
	TryStartNextUpload();
}

void OnDatabaseConnect_StoreUpload()
{
	TryStartNextUpload();
}

public void OnUploadCompleted(S3Client client, S3Response response, any token)
{
	if (g_UploadQueue.Length == 0)
	{
		return;
	}
	UploadJob job;
	g_UploadQueue.GetArray(0, job);
	if (job.token != token)
	{
		return;
	}
	g_UploadInFlight = false;

	if (response.Status == S3Status_Ok)
	{
		g_UploadLastError[0] = '\0';
		char etag[64];
		response.GetETag(etag, sizeof(etag));
		LogMessage("Replay upload of \"%s\" succeeded (HTTP %d, %d bytes, etag %s, %d left in queue).", job.objectKey, response.HttpStatus, job.fileSize, etag, g_UploadQueue.Length - 1);
		DB_InsertReplay(job.replayType, job.recordID, job.steamID, job.objectKey, job.fileSize, true, job.map);
		DequeueFirstUpload(job);
		TryStartNextUpload();
		return;
	}

	response.GetError(g_UploadLastError, sizeof(g_UploadLastError));
	g_UploadLastStatus = response.HttpStatus;
	job.attempt++;
	g_UploadQueue.SetArray(0, job);
	LogError("Replay upload of \"%s\" failed (attempt %d, HTTP %d): %s", job.objectKey, job.attempt, g_UploadLastStatus, g_UploadLastError);

	int maxAttempts = Store_GetUploadMaxAttempts();
	bool parkJob = maxAttempts > 0 && job.attempt >= maxAttempts;
	if (parkJob)
	{
		LogError("Replay upload of \"%s\" is parked until the next map change or sm_replaystore_flush.", job.objectKey);
		DequeueFirstUpload(job);
		TryStartNextUpload();
		return;
	}

	float delay = FloatMin(RP_UPLOAD_BACKOFF_CAP, RP_UPLOAD_BACKOFF_BASE * Pow(2.0, float(job.attempt - 1)));
	LogMessage("Retrying replay upload of \"%s\" in %.0f seconds.", job.objectKey, delay);
	g_UploadBackoffTimer = CreateTimer(delay, Timer_UploadBackoff);
}

public Action Timer_UploadBackoff(Handle timer)
{
	g_UploadBackoffTimer = INVALID_HANDLE;
	TryStartNextUpload();
	return Plugin_Stop;
}



// =====[ PRIVATE ]=====

static void TryStartNextUpload()
{
	bool busy = g_UploadInFlight || g_UploadBackoffTimer != INVALID_HANDLE;
	if (busy || g_UploadQueue.Length == 0 || gH_DB == null || !Store_IsConfigLoaded())
	{
		return;
	}

	if (!Store_IsEnabled())
	{
		RegisterQueueLocally();
		return;
	}
	if (gH_S3 == null)
	{
		LogMessage("Replay store client is not configured; %d uploads are waiting.", g_UploadQueue.Length);
		return;
	}

	UploadJob job;
	g_UploadQueue.GetArray(0, job);
	g_UploadToken++;
	job.token = g_UploadToken;
	g_UploadQueue.SetArray(0, job);
	g_UploadInFlight = true;
	char cachePath[PLATFORM_MAX_PATH];
	KeyToCachePath(job.objectKey, cachePath, sizeof(cachePath));
	LogMessage("Starting replay upload of \"%s\" from \"%s\" (%d bytes, attempt %d, %d queued).", job.objectKey, cachePath, job.fileSize, job.attempt + 1, g_UploadQueue.Length);
	gH_S3.PutFile(job.objectKey, cachePath, OnUploadCompleted, job.token);
}

static bool FormatImportKey(char[] key, int maxlength, int replayType, int recordID, int steamID, const char[] map, int timestamp, int mode, int style)
{
	switch (replayType)
	{
		case ReplayType_Run:
		{
			FormatRunKey(key, maxlength, map, recordID);
			return true;
		}
		case ReplayType_Jump:
		{
			FormatJumpKey(key, maxlength, steamID, recordID, timestamp);
			return true;
		}
		case ReplayType_Cheater:
		{
			bool validMode = mode >= 0 && mode < MODE_COUNT;
			bool validStyle = style >= 0 && style < STYLE_COUNT;
			if (!validMode || !validStyle)
			{
				return false;
			}
			FormatCheaterKey(key, maxlength, steamID, timestamp, map, mode, style);
			return true;
		}
	}
	return false;
}

static void RegisterQueueLocally()
{
	int registered = 0;
	for (int i = 0; i < g_UploadQueue.Length; i++)
	{
		UploadJob job;
		g_UploadQueue.GetArray(i, job);
		if (job.registeredLocally)
		{
			continue;
		}
		DB_InsertReplay(job.replayType, job.recordID, job.steamID, job.objectKey, job.fileSize, false, job.map);
		job.registeredLocally = true;
		g_UploadQueue.SetArray(i, job);
		registered++;
	}
	if (registered > 0)
	{
		LogMessage("Replay store is disabled; registered %d queued replays locally without upload (%d still queued).", registered, g_UploadQueue.Length);
	}
}

static bool IsUploadQueued(const char[] key)
{
	bool queued;
	return g_QueuedKeys.GetValue(key, queued);
}

static void DequeueFirstUpload(UploadJob job)
{
	g_UploadQueue.Erase(0);
	g_QueuedKeys.Remove(job.objectKey);
}

static void CreateMarker(const char[] markerPath)
{
	if (FileExists(markerPath))
	{
		return;
	}
	File marker = OpenFile(markerPath, "wb");
	if (marker == null)
	{
		LogError("Failed to create replay outbox marker \"%s\".", markerPath);
		return;
	}
	delete marker;
}

static void KillBackoffTimer()
{
	if (g_UploadBackoffTimer == INVALID_HANDLE)
	{
		return;
	}
	KillTimer(g_UploadBackoffTimer);
	g_UploadBackoffTimer = INVALID_HANDLE;
}

static void RescanOutbox()
{
	char outboxPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, outboxPath, sizeof(outboxPath), RP_DIRECTORY_OUTBOX);
	DirectoryListing dir = OpenDirectory(outboxPath);
	if (dir == null)
	{
		LogMessage("Replay outbox \"%s\" could not be opened.", outboxPath);
		return;
	}

	int markers = 0;
	char fileName[PLATFORM_MAX_PATH];
	FileType type;
	while (dir.GetNext(fileName, sizeof(fileName), type))
	{
		if (type != FileType_File)
		{
			continue;
		}
		markers++;
		EnqueueMarker(fileName);
	}
	delete dir;
	LogMessage("Replay outbox rescanned: %d markers found, %d uploads queued.", markers, g_UploadQueue.Length);
}

static void EnqueueMarker(const char[] fileName)
{
	char key[RP_MAX_KEY_LENGTH];
	if (!MarkerNameToKey(fileName, key, sizeof(key)))
	{
		return;
	}
	if (IsUploadQueued(key))
	{
		return;
	}

	char cachePath[PLATFORM_MAX_PATH];
	KeyToCachePath(key, cachePath, sizeof(cachePath));

	int replayType;
	int steamID;
	char mapName[64];
	if (!FileExists(cachePath) || !ReadReplayFileInfo(cachePath, replayType, steamID, mapName, sizeof(mapName)))
	{
		LogError("Replay outbox marker \"%s\" has no readable replay file; removing it.", fileName);
		char markerPath[PLATFORM_MAX_PATH];
		KeyToMarkerPath(key, markerPath, sizeof(markerPath));
		DeleteFile(markerPath);
		return;
	}

	ParseRunKeyMap(key, mapName, sizeof(mapName));
	int recordID = ParseKeyRecordID(key);
	Store_EnqueueUpload(key, replayType, recordID, steamID, mapName);
}
