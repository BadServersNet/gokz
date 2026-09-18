/*
	Shows how far along the server record route the player, or the player they
	are spectating, is. The progress itself is tracked by gokz-replays.
*/



// =====[ PUBLIC ]=====

bool IsProgressAvailable(KZPlayer player)
{
	int target = player.Alive ? player.ID : player.ObserverTarget;
	if (target == -1)
	{
		return false;
	}
	float progress;
	int rank;
	int total;
	return GetProgress(target, progress, rank, total);
}

char[] FormatProgressTextForMenu(KZPlayer player, HUDInfo info)
{
	return FormatProgressText(player, info, "TP Menu - Progress", "TP Menu - Progress Rank");
}

char[] FormatProgressTextForInfoPanel(KZPlayer player, HUDInfo info)
{
	return FormatProgressText(player, info, "Info Panel Text - Progress", "Info Panel Text - Progress Rank");
}



// =====[ PRIVATE ]=====

static char[] FormatProgressText(KZPlayer player, HUDInfo info, const char[] phrase, const char[] rankPhrase)
{
	char progressText[128];
	float progress;
	int rank;
	int total;
	if (!GetProgress(info.ID, progress, rank, total))
	{
		return progressText;
	}

	float percent = progress * 100.0;
	if (player.GetHUDOption(HUDOption_ProgressRank) == ProgressRank_Enabled)
	{
		FormatEx(progressText, sizeof(progressText), "%T", rankPhrase, player.ID, percent, rank, total);
		return progressText;
	}
	FormatEx(progressText, sizeof(progressText), "%T", phrase, player.ID, percent);
	return progressText;
}

static bool GetProgress(int target, float &progress, int &rank, int &total)
{
	if (!gB_GOKZReplays)
	{
		return false;
	}
	return GOKZ_RP_GetProgress(target, progress, rank, total);
}
