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
	int progressPercent;
	float lastProgressPrint;
	RouteDownloadKind routeKind;
	int routeUserid;
	ArrayList waiters;
}

static ArrayList g_DownloadQueue;
static bool g_DownloadInFlight;
static int g_DownloadToken;
static int g_DownloadHUDToken[MAXPLAYERS + 1];

#define DOWNLOAD_PROGRESS_SEGMENTS 20
#define DOWNLOAD_COMPLETE_HOLD_TIME 5.0
#define DOWNLOAD_FAILURE_HOLD_TIME 2.0



// =====[ PUBLIC ]=====

void Store_RequestDownload(int client, const char[] key, int expectedSize)
{
	int existing = FindQueuedDownload(key);
	if (existing != -1)
	{
		AddWaiter(existing, client);
		return;
	}

	DownloadJob job;
	InitDownloadJob(job, key, expectedSize);
	job.waiters.Push(GetClientUserId(client));
	g_DownloadQueue.PushArray(job);

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
	ClearAllDownloadProgress();
	CancelInFlightDownload();
	for (int i = 0; i < g_DownloadQueue.Length; i++)
	{
		DownloadJob job;
		g_DownloadQueue.GetArray(i, job);
		delete job.waiters;
	}
	g_DownloadQueue.Clear();
}

void OnPluginEnd_StoreDownload()
{
	ClearAllDownloadProgress();
}

void OnClientDisconnect_StoreDownload(int client)
{
	g_DownloadHUDToken[client] = 0;
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

	int size = total > 0 ? total : job.expectedSize;
	float ratio = size > 0 ? float(transferred) / float(size) : 0.0;
	int calculatedPercent = RoundToFloor(ratio * 100.0);
	int percent = IntMin(IntMax(calculatedPercent, 0), 99);
	job.progressPercent = percent;
	g_DownloadQueue.SetArray(0, job);
	ShowDownloadProgress(job, percent);
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
		NotifyWaiters(job, "Replay Download - HUD Unavailable");
	}
	else
	{
		char error[256];
		response.GetError(error, sizeof(error));
		LogError("Replay download of \"%s\" failed (HTTP %d): %s", job.objectKey, response.HttpStatus, error);
		NotifyWaiters(job, "Replay Download - HUD Failed");
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
	g_DownloadToken++;
	job.token = g_DownloadToken;
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
	EnsureDirectoryForPath(job.cachePath);
	job.requestID = gH_S3.GetFile(job.objectKey, job.cachePath, OnDownloadCompleted, job.token, OnDownloadProgress, true);
	g_DownloadQueue.SetArray(0, job);
	g_DownloadInFlight = true;
	ShowDownloadProgress(job, 0);
}

static void FinishDownload(DownloadJob job)
{
	bool sizeMismatch = job.expectedSize > 0 && FileSize(job.cachePath) != job.expectedSize;
	if (sizeMismatch)
	{
		LogError("Downloaded replay \"%s\" has an unexpected size; deleting it.", job.objectKey);
		DeleteFile(job.cachePath);
		NotifyWaiters(job, "Replay Download - HUD Failed");
		return;
	}

	ShowDownloadCompleted(job);
	HoldDownloadResult(job, DOWNLOAD_COMPLETE_HOLD_TIME);

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
	NotifyWaiters(job, "Replay Download - HUD Failed");
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
	ShowDownloadFailure(job, phrase);
	HoldDownloadResult(job, DOWNLOAD_FAILURE_HOLD_TIME);

	if (job.routeKind != RouteDownload_None)
	{
		if (job.routeKind == RouteDownload_Client)
		{
			int routeClient = GetClientOfUserId(job.routeUserid);
			ShowDownloadFailureForClient(job, routeClient, phrase);
			HoldClientDownloadResult(job.routeUserid, job.token, DOWNLOAD_FAILURE_HOLD_TIME);
		}
		LogMessage("The progress route replay \"%s\" could not be downloaded.", job.objectKey);
		Progress_OnRouteDownloadFailed(job.routeKind, job.routeUserid);
	}
	for (int i = 0; i < job.waiters.Length; i++)
	{
		int waiter = GetClientOfUserId(job.waiters.Get(i));
		if (IsValidClient(waiter))
		{
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
	if (index == 0 && g_DownloadInFlight)
	{
		ShowDownloadProgress(job, job.progressPercent);
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

static void ShowDownloadProgress(DownloadJob job, int percent)
{
	char completeBar[DOWNLOAD_PROGRESS_SEGMENTS * 4];
	char remainingBar[DOWNLOAD_PROGRESS_SEGMENTS * 4];
	BuildDownloadProgressBar(percent, completeBar, sizeof(completeBar), remainingBar, sizeof(remainingBar));
	char size[32];
	FormatFileSize(job.expectedSize, size, sizeof(size));

	for (int i = 0; i < job.waiters.Length; i++)
	{
		int userid = job.waiters.Get(i);
		int client = GetClientOfUserId(userid);
		if (!IsValidClient(client))
		{
			continue;
		}

		char text[HUD_MAX_HINT_SIZE];
		FormatEx(text, sizeof(text), "%T", "Replay Download - Progress", client, size, completeBar, remainingBar, percent);
		g_DownloadHUDToken[client] = job.token;
		ShowDownloadHUDText(client, text);
	}
}

static void ShowDownloadCompleted(DownloadJob job)
{
	char completeBar[DOWNLOAD_PROGRESS_SEGMENTS * 4];
	char remainingBar[DOWNLOAD_PROGRESS_SEGMENTS * 4];
	BuildDownloadProgressBar(100, completeBar, sizeof(completeBar), remainingBar, sizeof(remainingBar));
	char size[32];
	FormatFileSize(job.expectedSize, size, sizeof(size));

	for (int i = 0; i < job.waiters.Length; i++)
	{
		int client = GetClientOfUserId(job.waiters.Get(i));
		if (!IsValidClient(client))
		{
			continue;
		}

		char text[HUD_MAX_HINT_SIZE];
		FormatEx(text, sizeof(text), "%T", "Replay Download - Completed", client, size, completeBar, remainingBar, 100);
		g_DownloadHUDToken[client] = job.token;
		ShowDownloadHUDText(client, text);
	}
}

static void ShowDownloadFailure(DownloadJob job, const char[] phrase)
{
	for (int i = 0; i < job.waiters.Length; i++)
	{
		int client = GetClientOfUserId(job.waiters.Get(i));
		ShowDownloadFailureForClient(job, client, phrase);
	}
}

static void ShowDownloadFailureForClient(DownloadJob job, int client, const char[] phrase)
{
	if (!IsValidClient(client))
	{
		return;
	}

	char size[32];
	FormatFileSize(job.expectedSize, size, sizeof(size));
	char text[HUD_MAX_HINT_SIZE];
	FormatEx(text, sizeof(text), "%T", phrase, client, size);
	g_DownloadHUDToken[client] = job.token;
	ShowDownloadHUDText(client, text);
}

static void BuildDownloadProgressBar(int percent, char[] completeBar, int completeLength, char[] remainingBar, int remainingLength)
{
	int completeSegments = RoundToFloor(float(percent) / 100.0 * float(DOWNLOAD_PROGRESS_SEGMENTS));
	for (int i = 0; i < DOWNLOAD_PROGRESS_SEGMENTS; i++)
	{
		if (i < completeSegments)
		{
			StrCat(completeBar, completeLength, "■");
			continue;
		}
		StrCat(remainingBar, remainingLength, "■");
	}
}

static void ShowDownloadHUDText(int client, const char[] text)
{
	if (gB_GOKZHUD)
	{
		GOKZ_HUD_SetInfoPanelOverride(client, text);
		return;
	}

	char buffer[HUD_MAX_HINT_SIZE];
	FormatEx(buffer, sizeof(buffer), "</font>%s", text);
	for (int i = strlen(buffer); i < sizeof(buffer) - 1; i++)
	{
		buffer[i] = ' ';
	}
	buffer[sizeof(buffer) - 1] = '\0';

	Protobuf message = view_as<Protobuf>(StartMessageOne("TextMsg", client, USERMSG_BLOCKHOOKS));
	message.SetInt("msg_dst", 4);
	message.AddString("params", "#SFUI_ContractKillStart");
	message.AddString("params", buffer);
	message.AddString("params", NULL_STRING);
	message.AddString("params", NULL_STRING);
	message.AddString("params", NULL_STRING);
	message.AddString("params", NULL_STRING);
	EndMessage();
}

static void HoldDownloadResult(DownloadJob job, float holdTime)
{
	for (int i = 0; i < job.waiters.Length; i++)
	{
		int userid = job.waiters.Get(i);
		HoldClientDownloadResult(userid, job.token, holdTime);
	}
}

static void HoldClientDownloadResult(int userid, int token, float holdTime)
{
	DataPack data;
	CreateDataTimer(holdTime, Timer_ClearDownloadProgress, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(userid);
	data.WriteCell(token);
}

public Action Timer_ClearDownloadProgress(Handle timer, DataPack data)
{
	data.Reset();
	int userid = data.ReadCell();
	int token = data.ReadCell();
	int client = GetClientOfUserId(userid);
	ClearClientDownloadProgress(client, token);
	return Plugin_Stop;
}

static void ClearAllDownloadProgress()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		int token = g_DownloadHUDToken[client];
		ClearClientDownloadProgress(client, token);
	}
}

static void ClearClientDownloadProgress(int client, int token)
{
	if (!IsValidClient(client) || token == 0 || g_DownloadHUDToken[client] != token)
	{
		return;
	}
	g_DownloadHUDToken[client] = 0;
	ShowDownloadHUDText(client, "");
}
