static GlobalForward H_OnReplaySaved;
static GlobalForward H_OnReplayDiscarded;
static GlobalForward H_OnTimerEnd_Post;
static GlobalForward H_OnPlaybackFailed;

// =====[ NATIVES ]=====

void CreateNatives()
{
	CreateNative("GOKZ_RP_GetPlaybackInfo", Native_RP_GetPlaybackInfo);
	CreateNative("GOKZ_RP_LoadJumpReplay", Native_RP_LoadJumpReplay);
	CreateNative("GOKZ_RP_LoadRunReplay", Native_RP_LoadRunReplay);
	CreateNative("GOKZ_RP_GetProgress", Native_RP_GetProgress);
	CreateNative("GOKZ_RP_UpdateReplayControlMenu", Native_RP_UpdateReplayControlMenu);
	CreateNative("GOKZ_RP_ImportReplay", Native_RP_ImportReplay);
	CreateNative("GOKZ_RP_GetPendingUploadCount", Native_RP_GetPendingUploadCount);
	CreateNative("GOKZ_RP_ClearUploadQueue", Native_RP_ClearUploadQueue);
}

public int Native_RP_GetPlaybackInfo(Handle plugin, int numParams)
{
	HUDInfo info;
	GetPlaybackState(GetNativeCell(1), info);
	SetNativeArray(2, info, sizeof(HUDInfo));
	return 1;
}

public int Native_RP_LoadJumpReplay(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int jumpID = GetNativeCell(2);
	return view_as<int>(RequestJumpPlayback(client, jumpID));
}

public int Native_RP_LoadRunReplay(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int timeID = GetNativeCell(2);
	return view_as<int>(RequestRunPlayback(client, timeID));
}

public int Native_RP_GetProgress(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	float progress;
	int rank;
	int total;
	bool tracked = Progress_GetClientProgress(client, progress, rank, total);
	SetNativeCellRef(2, progress);
	SetNativeCellRef(3, rank);
	SetNativeCellRef(4, total);
	return view_as<int>(tracked);
}

public int Native_RP_UpdateReplayControlMenu(Handle plugin, int numParams)
{
	return view_as<int>(UpdateReplayControlMenu(GetNativeCell(1)));
}

public int Native_RP_ImportReplay(Handle plugin, int numParams)
{
	char sourcePath[PLATFORM_MAX_PATH];
	GetNativeString(1, sourcePath, sizeof(sourcePath));
	int replayType = GetNativeCell(2);
	int recordID = GetNativeCell(3);
	int steamID = GetNativeCell(4);
	char map[64];
	GetNativeString(5, map, sizeof(map));
	int timestamp = GetNativeCell(6);
	int mode = GetNativeCell(7);
	int style = GetNativeCell(8);
	int maxlength = GetNativeCell(10);

	char key[RP_MAX_KEY_LENGTH];
	bool imported = Store_ImportReplay(sourcePath, replayType, recordID, steamID, map, timestamp, mode, style, key, sizeof(key));
	SetNativeString(9, key, maxlength);
	return view_as<int>(imported);
}

public int Native_RP_GetPendingUploadCount(Handle plugin, int numParams)
{
	return Store_GetPendingUploadCount();
}

public int Native_RP_ClearUploadQueue(Handle plugin, int numParams)
{
	return Store_ClearUploadQueue();
}

// =====[ FORWARDS ]=====

void CreateGlobalForwards()
{
	H_OnReplaySaved = new GlobalForward("GOKZ_RP_OnReplaySaved", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Float, Param_String);
	H_OnReplayDiscarded = new GlobalForward("GOKZ_RP_OnReplayDiscarded", ET_Ignore, Param_Cell);
	H_OnTimerEnd_Post = new GlobalForward("GOKZ_RP_OnTimerEnd_Post", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_Float, Param_Cell);
	H_OnPlaybackFailed = new GlobalForward("GOKZ_RP_OnPlaybackFailed", ET_Ignore, Param_Cell);
}

void Call_OnPlaybackFailed(int client)
{
	Call_StartForward(H_OnPlaybackFailed);
	Call_PushCell(client);
	Call_Finish();
}

void Call_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath)
{
	Call_StartForward(H_OnReplaySaved);
	Call_PushCell(client);
	Call_PushCell(replayType);
	Call_PushString(map);
	Call_PushCell(course);
	Call_PushCell(timeType);
	Call_PushFloat(time);
	Call_PushString(filePath);
	Call_Finish();
}

void Call_OnReplayDiscarded(int client)
{
	Call_StartForward(H_OnReplayDiscarded);
	Call_PushCell(client);
	Call_Finish();
}

void Call_OnTimerEnd_Post(int client, const char[] filePath, int course, float time, int teleportsUsed)
{
	Call_StartForward(H_OnTimerEnd_Post);
	Call_PushCell(client);
	Call_PushString(filePath);
	Call_PushCell(course);
	Call_PushFloat(time);
	Call_PushCell(teleportsUsed);
	Call_Finish();
}
