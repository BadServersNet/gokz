/*
	Replay store ConVars and the S3 client lifecycle.
*/



static ConVar gCV_gokz_replay_store_enabled;
static ConVar gCV_gokz_replay_store_endpoint;
static ConVar gCV_gokz_replay_store_bucket;
static ConVar gCV_gokz_replay_store_region;
static ConVar gCV_gokz_replay_store_access_key;
static ConVar gCV_gokz_replay_store_secret_key;
static ConVar gCV_gokz_replay_store_public_url;
static ConVar gCV_gokz_replay_store_path_style;
static ConVar gCV_gokz_replay_store_timeout;
static ConVar gCV_gokz_replay_store_max_retries;
static ConVar gCV_gokz_replay_upload_max_attempts;
static ConVar gCV_gokz_replay_cache_max_age_days;
static ConVar gCV_gokz_replay_cache_purge_on_boot;

static Handle rebuildTimer;
static bool configLoaded;



// =====[ PUBLIC ]=====

void Store_OnConfigsExecuted()
{
	configLoaded = true;
	Store_PurgeUploadedCacheOnBoot();
	Store_RebuildClient();
	OnConfigsExecuted_Progress();
}

bool Store_IsConfigLoaded()
{
	return configLoaded;
}

void CreateConVars()
{
	AutoExecConfig_SetFile("gokz-replays", "sourcemod/gokz");
	AutoExecConfig_SetCreateFile(true);

	gCV_gokz_replay_store_enabled = AutoExecConfig_CreateConVar("gokz_replay_store_enabled", "0", "Whether replays are uploaded to and downloaded from the S3-compatible replay store.", _, true, 0.0, true, 1.0);
	gCV_gokz_replay_store_endpoint = AutoExecConfig_CreateConVar("gokz_replay_store_endpoint", "", "Replay store endpoint host, e.g. <account>.r2.cloudflarestorage.com or http://127.0.0.1:9000.");
	gCV_gokz_replay_store_bucket = AutoExecConfig_CreateConVar("gokz_replay_store_bucket", "", "Replay store bucket name.");
	gCV_gokz_replay_store_region = AutoExecConfig_CreateConVar("gokz_replay_store_region", "auto", "Replay store SigV4 region (auto for Cloudflare R2, us-east-1 for MinIO/AWS).");
	gCV_gokz_replay_store_access_key = AutoExecConfig_CreateConVar("gokz_replay_store_access_key", "", "Replay store access key id.", FCVAR_PROTECTED);
	gCV_gokz_replay_store_secret_key = AutoExecConfig_CreateConVar("gokz_replay_store_secret_key", "", "Replay store secret access key.", FCVAR_PROTECTED);
	gCV_gokz_replay_store_public_url = AutoExecConfig_CreateConVar("gokz_replay_store_public_url", "", "Optional public base URL used for unsigned replay downloads (e.g. an R2 custom domain).");
	gCV_gokz_replay_store_path_style = AutoExecConfig_CreateConVar("gokz_replay_store_path_style", "1", "Use path-style bucket addressing (1) or virtual-hosted addressing (0).", _, true, 0.0, true, 1.0);
	gCV_gokz_replay_store_timeout = AutoExecConfig_CreateConVar("gokz_replay_store_timeout", "60", "Seconds a replay transfer may stall before it is aborted.", _, true, 5.0);
	gCV_gokz_replay_store_max_retries = AutoExecConfig_CreateConVar("gokz_replay_store_max_retries", "3", "Retries per replay transfer for network errors and 5xx responses.", _, true, 0.0);
	gCV_gokz_replay_upload_max_attempts = AutoExecConfig_CreateConVar("gokz_replay_upload_max_attempts", "0", "Failed attempts before a replay upload is parked until the next map change or sm_replaystore_flush (0 = retry forever with backoff).", _, true, 0.0);
	gCV_gokz_replay_cache_max_age_days = AutoExecConfig_CreateConVar("gokz_replay_cache_max_age_days", "30", "Cached replays older than this many days are deleted at map start (0 = never).", _, true, 0.0);
	gCV_gokz_replay_cache_purge_on_boot = AutoExecConfig_CreateConVar("gokz_replay_cache_purge_on_boot", "1", "Delete every cached replay that has already been uploaded to the replay store when the server boots. Replays still waiting for upload are kept.", _, true, 0.0, true, 1.0);

	Progress_CreateConVars();

	gCV_gokz_replay_store_enabled.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_endpoint.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_bucket.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_region.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_access_key.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_secret_key.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_public_url.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_path_style.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_timeout.AddChangeHook(OnConVarChanged_Store);
	gCV_gokz_replay_store_max_retries.AddChangeHook(OnConVarChanged_Store);

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
}

void Store_RebuildClient()
{
	if (rebuildTimer != INVALID_HANDLE)
	{
		KillTimer(rebuildTimer);
		rebuildTimer = INVALID_HANDLE;
	}

	if (gH_S3 != null)
	{
		delete gH_S3;
	}
	Store_OnClientRebuilt();
	OnClientRebuilt_StoreDownload();

	if (!Store_IsEnabled())
	{
		return;
	}

	char endpoint[256];
	char bucket[128];
	char region[64];
	char accessKey[128];
	char secretKey[128];
	char publicUrl[256];
	gCV_gokz_replay_store_endpoint.GetString(endpoint, sizeof(endpoint));
	gCV_gokz_replay_store_bucket.GetString(bucket, sizeof(bucket));
	gCV_gokz_replay_store_region.GetString(region, sizeof(region));
	gCV_gokz_replay_store_access_key.GetString(accessKey, sizeof(accessKey));
	gCV_gokz_replay_store_secret_key.GetString(secretKey, sizeof(secretKey));
	gCV_gokz_replay_store_public_url.GetString(publicUrl, sizeof(publicUrl));

	if (endpoint[0] == '\0' || bucket[0] == '\0')
	{
		LogError("Replay store is enabled but gokz_replay_store_endpoint or gokz_replay_store_bucket is empty.");
		return;
	}

	gH_S3 = new S3Client(endpoint, bucket, region, accessKey, secretKey);
	gH_S3.PathStyle = gCV_gokz_replay_store_path_style.BoolValue;
	gH_S3.Timeout = gCV_gokz_replay_store_timeout.IntValue;
	gH_S3.MaxRetries = gCV_gokz_replay_store_max_retries.IntValue;
	if (publicUrl[0] != '\0')
	{
		gH_S3.SetPublicUrl(publicUrl);
	}

	Store_OnClientReady();
}

bool Store_IsEnabled()
{
	return gCV_gokz_replay_store_enabled.BoolValue;
}

bool Store_IsReady()
{
	return Store_IsEnabled() && gH_S3 != null;
}

bool Store_HasPublicUrl()
{
	char publicUrl[256];
	gCV_gokz_replay_store_public_url.GetString(publicUrl, sizeof(publicUrl));
	return publicUrl[0] != '\0';
}

void Store_BuildPublicUrl(const char[] key, char[] buffer, int maxlength)
{
	char publicUrl[256];
	gCV_gokz_replay_store_public_url.GetString(publicUrl, sizeof(publicUrl));
	int length = strlen(publicUrl);
	while (length > 0 && publicUrl[length - 1] == '/')
	{
		length--;
		publicUrl[length] = '\0';
	}
	FormatEx(buffer, maxlength, "%s/%s", publicUrl, key);
}

int Store_GetUploadMaxAttempts()
{
	return gCV_gokz_replay_upload_max_attempts.IntValue;
}

int Store_GetCacheMaxAgeDays()
{
	return gCV_gokz_replay_cache_max_age_days.IntValue;
}

bool Store_GetCachePurgeOnBoot()
{
	return gCV_gokz_replay_cache_purge_on_boot.BoolValue;
}



// =====[ EVENTS ]=====

public void OnConVarChanged_Store(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (rebuildTimer != INVALID_HANDLE)
	{
		return;
	}
	rebuildTimer = CreateTimer(0.5, Timer_RebuildClient);
}

public Action Timer_RebuildClient(Handle timer)
{
	rebuildTimer = INVALID_HANDLE;
	Store_RebuildClient();
	return Plugin_Stop;
}
