/*
	Object keys, local cache/outbox/staging paths and cache pruning.
*/



static bool g_PurgedOnBoot;



// =====[ PUBLIC ]=====

void FormatRunKey(char[] buffer, int maxlength, const char[] map, int timeID)
{
	FormatEx(buffer, maxlength, "%s/%s/%d.%s", RP_KEY_PREFIX_RUNS, map, timeID, RP_FILE_EXTENSION);
}

void FormatJumpKey(char[] buffer, int maxlength, int steamID, int jumpID, int timestamp)
{
	FormatEx(buffer, maxlength, "%s/%d/%d_%d.%s", RP_KEY_PREFIX_JUMPS, steamID, jumpID, timestamp, RP_FILE_EXTENSION);
}

void FormatCheaterKey(char[] buffer, int maxlength, int steamID, int timestamp, const char[] map, int mode, int style)
{
	FormatEx(buffer, maxlength, "%s/%d/%d_%s_%s_%s.%s", RP_KEY_PREFIX_CHEATERS, steamID, timestamp, map, gC_ModeNamesShort[mode], gC_StyleNamesShort[style], RP_FILE_EXTENSION);
}

void KeyToCachePath(const char[] key, char[] buffer, int maxlength)
{
	BuildPath(Path_SM, buffer, maxlength, "%s/%s", RP_DIRECTORY_CACHE, key);
}

void KeyToMarkerPath(const char[] key, char[] buffer, int maxlength)
{
	char encoded[RP_MAX_KEY_LENGTH];
	strcopy(encoded, sizeof(encoded), key);
	ReplaceString(encoded, sizeof(encoded), "/", "~");
	BuildPath(Path_SM, buffer, maxlength, "%s/%s.%s", RP_DIRECTORY_OUTBOX, encoded, RP_OUTBOX_MARKER_EXTENSION);
}

bool MarkerNameToKey(const char[] fileName, char[] key, int maxlength)
{
	char suffix[16];
	FormatEx(suffix, sizeof(suffix), ".%s", RP_OUTBOX_MARKER_EXTENSION);
	int nameLength = strlen(fileName);
	int suffixLength = strlen(suffix);
	int keyLength = nameLength - suffixLength;
	if (keyLength <= 0 || keyLength >= maxlength)
	{
		return false;
	}
	if (!StrEqual(fileName[keyLength], suffix))
	{
		return false;
	}

	strcopy(key, maxlength, fileName);
	key[keyLength] = '\0';
	ReplaceString(key, maxlength, "~", "/");
	return true;
}

void FormatStagingPath(char[] buffer, int maxlength, int client)
{
	int userid = GetClientUserId(client);
	float engineTime = GetEngineTime();
	BuildPath(Path_SM, buffer, maxlength, "%s/%d_%.3f.%s", RP_DIRECTORY_STAGING, userid, engineTime, RP_FILE_EXTENSION);
}

int ParseKeyRecordID(const char[] key)
{
	int lastSlash = FindCharInString(key, '/', true);
	if (lastSlash == -1)
	{
		return -1;
	}
	return StringToInt(key[lastSlash + 1]);
}

void ParseRunKeyMap(const char[] key, char[] map, int maxlength)
{
	char parts[3][RP_MAX_KEY_LENGTH];
	int count = ExplodeString(key, "/", parts, sizeof(parts), sizeof(parts[]));
	bool isRunKey = count == 3 && StrEqual(parts[0], RP_KEY_PREFIX_RUNS);
	if (!isRunKey)
	{
		return;
	}
	strcopy(map, maxlength, parts[1]);
}

void EnsureDirectoryForPath(const char[] filePath)
{
	char path[PLATFORM_MAX_PATH];
	strcopy(path, sizeof(path), filePath);
	int length = strlen(path);
	for (int i = 1; i < length; i++)
	{
		if (path[i] != '/')
		{
			continue;
		}
		path[i] = '\0';
		if (!DirExists(path))
		{
			CreateDirectory(path, 511);
		}
		path[i] = '/';
	}
}

void EnsureStoreDirectories()
{
	EnsureStoreDirectory(RP_DIRECTORY_CACHE);
	EnsureStoreDirectory(RP_DIRECTORY_OUTBOX);
	EnsureStoreDirectory(RP_DIRECTORY_STAGING);
}

void Store_PurgeUploadedCacheOnBoot()
{
	if (g_PurgedOnBoot)
	{
		return;
	}
	g_PurgedOnBoot = true;
	if (!Store_GetCachePurgeOnBoot())
	{
		return;
	}
	if (!Store_IsEnabled())
	{
		LogMessage("Skipping the replay cache purge at boot because the replay store is disabled.");
		return;
	}
	int deleted;
	int kept;
	DeleteUploadedCacheFiles(0, deleted, kept);
	EnsureStoreDirectories();
	LogMessage("Purged %d uploaded replays from the cache at boot; %d replays waiting for upload were kept.", deleted, kept);
}



// =====[ EVENTS ]=====

void OnMapStart_StoreCache()
{
	PurgeStaging();
	PruneCache();
}



// =====[ PRIVATE ]=====

static void EnsureStoreDirectory(const char[] directory)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/", directory);
	EnsureDirectoryForPath(path);
}

static void PurgeStaging()
{
	char stagingPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, stagingPath, sizeof(stagingPath), RP_DIRECTORY_STAGING);
	DirectoryListing dir = OpenDirectory(stagingPath);
	if (dir == null)
	{
		return;
	}

	int cutoff = GetTime() - RP_STAGING_MAX_AGE;
	char fileName[PLATFORM_MAX_PATH];
	FileType type;
	while (dir.GetNext(fileName, sizeof(fileName), type))
	{
		if (type != FileType_File)
		{
			continue;
		}
		char filePath[PLATFORM_MAX_PATH];
		FormatEx(filePath, sizeof(filePath), "%s/%s", stagingPath, fileName);
		DeleteFileIfOlder(filePath, cutoff);
	}
	delete dir;
}

static void PruneCache()
{
	int maxAgeDays = Store_GetCacheMaxAgeDays();
	if (maxAgeDays <= 0)
	{
		return;
	}
	int cutoff = GetTime() - maxAgeDays * 86400;
	int deleted;
	int kept;
	DeleteUploadedCacheFiles(cutoff, deleted, kept);
	if (deleted > 0)
	{
		LogMessage("Pruned %d cached replays older than %d days.", deleted, maxAgeDays);
	}
}

static void DeleteUploadedCacheFiles(int cutoff, int &deleted, int &kept)
{
	char cachePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, cachePath, sizeof(cachePath), RP_DIRECTORY_CACHE);
	DeleteUploadedCacheDirectory(cachePath, "", cutoff, deleted, kept);
}

static void DeleteUploadedCacheDirectory(const char[] dirPath, const char[] keyPrefix, int cutoff, int &deleted, int &kept)
{
	DirectoryListing dir = OpenDirectory(dirPath);
	if (dir == null)
	{
		return;
	}

	char name[PLATFORM_MAX_PATH];
	FileType type;
	while (dir.GetNext(name, sizeof(name), type))
	{
		if (StrEqual(name, ".") || StrEqual(name, ".."))
		{
			continue;
		}
		char entryPath[PLATFORM_MAX_PATH];
		FormatEx(entryPath, sizeof(entryPath), "%s/%s", dirPath, name);
		char entryKey[RP_MAX_KEY_LENGTH];
		FormatEx(entryKey, sizeof(entryKey), "%s%s", keyPrefix, name);
		if (type == FileType_Directory)
		{
			char nestedPrefix[RP_MAX_KEY_LENGTH];
			FormatEx(nestedPrefix, sizeof(nestedPrefix), "%s/", entryKey);
			DeleteUploadedCacheDirectory(entryPath, nestedPrefix, cutoff, deleted, kept);
			RemoveDir(entryPath);
			continue;
		}
		DeleteUploadedCacheFile(entryPath, entryKey, cutoff, deleted, kept);
	}
	delete dir;
}

static void DeleteUploadedCacheFile(const char[] filePath, const char[] key, int cutoff, int &deleted, int &kept)
{
	if (IsPartialDownload(filePath))
	{
		kept++;
		return;
	}
	char markerPath[PLATFORM_MAX_PATH];
	KeyToMarkerPath(key, markerPath, sizeof(markerPath));
	if (FileExists(markerPath))
	{
		kept++;
		return;
	}
	int modified = GetFileTime(filePath, FileTime_LastChange);
	if (cutoff > 0 && modified >= cutoff)
	{
		return;
	}
	DeleteFile(filePath);
	deleted++;
}

static bool IsPartialDownload(const char[] filePath)
{
	int length = strlen(filePath);
	int suffixLength = 5;
	if (length < suffixLength)
	{
		return false;
	}
	return StrEqual(filePath[length - suffixLength], ".part");
}

static void DeleteFileIfOlder(const char[] filePath, int cutoff)
{
	int modified = GetFileTime(filePath, FileTime_LastChange);
	if (modified >= cutoff)
	{
		return;
	}
	DeleteFile(filePath);
}
