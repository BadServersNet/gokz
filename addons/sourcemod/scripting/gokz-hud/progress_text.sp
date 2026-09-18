/*
	Shows how far along the server record route the player, or the player they
	are spectating, is. The progress itself is tracked by gokz-replays.
*/



// =====[ PUBLIC ]=====

char[] FormatProgressTextForMenu(KZPlayer player, HUDInfo info)
{
	char progressText[64];
	float progress;
	int rank;
	int total;
	if (!GetProgress(info, progress, rank, total))
	{
		return progressText;
	}

	float percent = progress * 100.0;
	if (player.GetHUDOption(HUDOption_ProgressRank) == ProgressRank_Enabled)
	{
		FormatEx(progressText, sizeof(progressText), "%T", "TP Menu - Progress Rank", player.ID, percent, rank, total);
		return progressText;
	}
	FormatEx(progressText, sizeof(progressText), "%T", "TP Menu - Progress", player.ID, percent);
	return progressText;
}

char[] FormatProgressTextForInfoPanel(KZPlayer player, HUDInfo info)
{
	char progressText[128];
	float progress;
	int rank;
	int total;
	if (!GetProgress(info, progress, rank, total))
	{
		return progressText;
	}

	float percent = progress * 100.0;
	if (player.GetHUDOption(HUDOption_ProgressRank) == ProgressRank_Enabled)
	{
		FormatEx(progressText, sizeof(progressText), "%T\n", "Info Panel Text - Progress Rank", player.ID, percent, rank, total);
		return progressText;
	}
	FormatEx(progressText, sizeof(progressText), "%T\n", "Info Panel Text - Progress", player.ID, percent);
	return progressText;
}



// =====[ PRIVATE ]=====

static bool GetProgress(HUDInfo info, float &progress, int &rank, int &total)
{
	if (!gB_GOKZReplays)
	{
		return false;
	}
	return GOKZ_RP_GetProgress(info.ID, progress, rank, total);
}
