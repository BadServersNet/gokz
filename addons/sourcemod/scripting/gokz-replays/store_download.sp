/*
	Serial replay download queue with progress reporting for the waiting players.
*/



enum RouteDownloadKind
{
	RouteDownload_None = 0,
	RouteDownload_Server,
	RouteDownload_Client,
	RouteDownload_PB
}

enum struct DownloadJob
{
	char objectKey[RP_MAX_KEY_LENGTH];
	char cachePath[PLATFORM_MAX_PATH];
	char map[64];
	int expectedSize;
	int requestID;
	int token;
	float lastProgressPrint;
	RouteDownloadKind routeKind;
	int routeUserid;
	ArrayList waiters;
}

static ArrayList g_DownloadQueue;
static bool g_DownloadInFlight;
static int g_DownloadToken;



// =====[ PUBLIC ]=====

void Store_RequestDownload(int client, const char[] key, int expectedSize)
{
	int existing = FindQueuedDownload(key);
	if (existing != -1)
	{
		AddWaiter(existing, client);
		GOKZ_PrintToChat(client, true, "%t", "Replay Download - Joined");
		return;
	}

	DownloadJob job;
	InitDownloadJob(job, key, expectedSize);
	job.waiters.Push(GetClientUserId(client));
	g_DownloadQueue.PushArray(job);

	char size[32];
	FormatFileSize(expectedSize, size, sizeof(size));
	GOKZ_PrintToChat(client, true, "%t", "Replay Download - Start", size);
	TryStartNextDownload();
}

void Store_RequestRouteDownload(const char[] key, int expectedSize, RouteDownloadKind kind, int routeUserid)
{
	if (FindQueuedDownload(key) != -1)
	{
		return;
	}

	DownloadJob job;
	InitDownloadJob(job, key, expectedSize);
	job.routeKind = kind;
	job.routeUserid = routeUserid;
	g_DownloadQueue.PushArray(job);
	TryStartNextDownload();
}

void Store_PrintDownloadStatus(int client)
{
	ReplyToCommand(client, "[KZ] Downloads queued: %d, in flight: %s", g_DownloadQueue.Length, g_DownloadInFlight ? "yes" : "no");
}



// =====[ EVENTS ]=====

void OnPluginStart_StoreDownload()
{
	g_DownloadQueue = new ArrayList(sizeof(DownloadJob));
}

void OnMapEnd_StoreDownload()
{
	CancelInFlightDownload();
	for (int i = 0; i < g_DownloadQueue.Length; i++)
	{
		DownloadJob job;
		g_DownloadQueue.GetArray(i, job);
		delete job.waiters;
	}
	g_DownloadQueue.Clear();
}

void OnClientDisconnect_StoreDownload(int client)
{
	int userid = GetClientUserId(client);
	for (int i = 0; i < g_DownloadQueue.Length; i++)
	{
		DownloadJob job;
		g_DownloadQueue.GetArray(i, job);
		int index = job.waiters.FindValue(userid);
		if (index != -1)
		{
			job.waiters.Erase(index);
		}
	}
}

void OnClientRebuilt_StoreDownload()
{
	if (!g_DownloadInFlight)
	{
		return;
	}
	g_DownloadInFlight = false;
	FailCurrentDownload();
}

public void OnDownloadProgress(S3Client client, int transferred, int total, any token)
{
	if (g_DownloadQueue.Length == 0)
	{
		return;
	}
	DownloadJob job;
	g_DownloadQueue.GetArray(0, job);
	if (job.token != token)
	{
		return;
	}

	float now = GetGameTime();
	if (now - job.lastProgressPrint < RP_DOWNLOAD_PROGRESS_INTERVAL)
	{
		return;
	}
	job.lastProgressPrint = now;
	g_DownloadQueue.SetArray(0, job);

	int size = total > 0 ? total : job.expectedSize;
	int percent = size > 0 ? RoundToFloor(float(transferred) / float(size) * 100.0) : 0;
	for (int i = 0; i < job.waiters.Length; i++)
	{
		int waiter = GetClientOfUserId(job.waiters.Get(i));
		if (IsValidClient(waiter))
		{
			PrintCenterText(waiter, "%t", "Replay Download - Progress", percent);
		}
	}
}

public void OnDownloadCompleted(S3Client client, S3Response response, any token)
{
	if (g_DownloadQueue.Length == 0)
	{
		return;
	}
	DownloadJob job;
	g_DownloadQueue.GetArray(0, job);
	if (job.token != token)
	{
		return;
	}
	g_DownloadInFlight = false;

	if (response.Status == S3Status_Ok)
	{
		FinishDownload(job);
	}
	else if (response.HttpStatus == 404)
	{
		NotifyWaiters(job, "Replay Not Available");
	}
	else
	{
		char error[256];
		response.GetError(error, sizeof(error));
		LogError("Replay download of \"%s\" failed (HTTP %d): %s", job.objectKey, response.HttpStatus, error);
		NotifyWaiters(job, "Replay Download - Failed");
	}

	delete job.waiters;
	g_DownloadQueue.Erase(0);
	TryStartNextDownload();
}



// =====[ PRIVATE ]=====

static void InitDownloadJob(DownloadJob job, const char[] key, int expectedSize)
{
	strcopy(job.objectKey, sizeof(DownloadJob::objectKey), key);
	KeyToCachePath(key, job.cachePath, sizeof(DownloadJob::cachePath));
	strcopy(job.map, sizeof(DownloadJob::map), gC_CurrentMap);
	job.expectedSize = expectedSize;
	job.waiters = new ArrayList();
}

static void TryStartNextDownload()
{
	if (g_DownloadInFlight || g_DownloadQueue.Length == 0)
	{
		return;
	}
	if (gH_S3 == null)
	{
		FailCurrentDownload();
		return;
	}

	DownloadJob job;
	g_DownloadQueue.GetArray(0, job);
	g_DownloadToken++;
	job.token = g_DownloadToken;
	EnsureDirectoryForPath(job.cachePath);
	job.requestID = gH_S3.GetFile(job.objectKey, job.cachePath, OnDownloadCompleted, job.token, OnDownloadProgress, true);
	g_DownloadQueue.SetArray(0, job);
	g_DownloadInFlight = true;
}

static void FinishDownload(DownloadJob job)
{
	bool sizeMismatch = job.expectedSize > 0 && FileSize(job.cachePath) != job.expectedSize;
	if (sizeMismatch)
	{
		LogError("Downloaded replay \"%s\" has an unexpected size; deleting it.", job.objectKey);
		DeleteFile(job.cachePath);
		NotifyWaiters(job, "Replay Download - Failed");
		return;
	}

	bool sameMap = StrEqual(job.map, gC_CurrentMap);
	if (job.routeKind != RouteDownload_None && sameMap)
	{
		Progress_OnRouteDownloaded(job.routeKind, job.routeUserid, job.cachePath);
	}
	for (int i = 0; i < job.waiters.Length; i++)
	{
		int waiter = GetClientOfUserId(job.waiters.Get(i));
		if (!IsValidClient(waiter))
		{
			continue;
		}
		GOKZ_PrintToChat(waiter, true, "%t", "Replay Download - Done");
		if (sameMap)
		{
			StartReplayFromCache(waiter, job.cachePath);
		}
		else
		{
			Playback_OnFailed(waiter);
		}
	}
}

static void FailCurrentDownload()
{
	if (g_DownloadQueue.Length == 0)
	{
		return;
	}
	DownloadJob job;
	g_DownloadQueue.GetArray(0, job);
	NotifyWaiters(job, "Replay Download - Failed");
	delete job.waiters;
	g_DownloadQueue.Erase(0);
	TryStartNextDownload();
}

static void CancelInFlightDownload()
{
	if (!g_DownloadInFlight)
	{
		return;
	}
	g_DownloadInFlight = false;
	if (gH_S3 == null || g_DownloadQueue.Length == 0)
	{
		return;
	}
	DownloadJob job;
	g_DownloadQueue.GetArray(0, job);
	gH_S3.Cancel(job.requestID);
}

static void NotifyWaiters(DownloadJob job, const char[] phrase)
{
	if (job.routeKind != RouteDownload_None)
	{
		LogMessage("The progress route replay \"%s\" could not be downloaded.", job.objectKey);
		Progress_OnRouteDownloadFailed(job.routeKind, job.routeUserid);
	}
	for (int i = 0; i < job.waiters.Length; i++)
	{
		int waiter = GetClientOfUserId(job.waiters.Get(i));
		if (IsValidClient(waiter))
		{
			GOKZ_PrintToChat(waiter, true, "%t", phrase);
			GOKZ_PlayErrorSound(waiter);
			Playback_OnFailed(waiter);
		}
	}
}

static int FindQueuedDownload(const char[] key)
{
	for (int i = 0; i < g_DownloadQueue.Length; i++)
	{
		DownloadJob job;
		g_DownloadQueue.GetArray(i, job);
		if (StrEqual(job.objectKey, key))
		{
			return i;
		}
	}
	return -1;
}

static void AddWaiter(int index, int client)
{
	DownloadJob job;
	g_DownloadQueue.GetArray(index, job);
	int userid = GetClientUserId(client);
	if (job.waiters.FindValue(userid) == -1)
	{
		job.waiters.Push(userid);
	}
}

static void FormatFileSize(int bytes, char[] buffer, int maxlength)
{
	if (bytes >= 1048576)
	{
		FormatEx(buffer, maxlength, "%.1f MB", float(bytes) / 1048576.0);
		return;
	}
	if (bytes >= 1024)
	{
		FormatEx(buffer, maxlength, "%.0f KB", float(bytes) / 1024.0);
		return;
	}
	FormatEx(buffer, maxlength, "%d B", bytes);
}
