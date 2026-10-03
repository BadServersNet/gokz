#define SESSION_COLOUR_VALUE "#ffffff"
#define SESSION_COLOUR_AHEAD "#40ff40"
#define SESSION_COLOUR_BEHIND "#ea4141"
#define SESSION_COLOUR_WAITING "#ead18a"
#define SESSION_EVEN_THRESHOLD 0.005



// =====[ PUBLIC ]=====

bool GetSessionInfo(KZPlayer player, ReplaySessionInfo session)
{
	if (!gB_GOKZReplays)
	{
		return false;
	}
	int target = player.Alive ? player.ID : player.ObserverTarget;
	if (target == -1)
	{
		return false;
	}
	return GOKZ_RP_GetSessionInfo(target, session);
}

bool IsSessionTextShownIn(KZPlayer player, int position)
{
	ReplaySessionInfo session;
	if (!GetSessionInfo(player, session))
	{
		return false;
	}
	return GetSessionTextPosition(player) == position;
}

char[] FormatSessionTextForInfoPanel(KZPlayer player)
{
	char sessionText[256];
	ReplaySessionInfo session;
	if (GetSessionInfo(player, session))
	{
		FormatSessionText(player, session, true, sessionText, sizeof(sessionText));
	}
	return sessionText;
}

char[] FormatSessionTextForMenu(KZPlayer player)
{
	char sessionText[128];
	ReplaySessionInfo session;
	if (GetSessionInfo(player, session))
	{
		FormatSessionText(player, session, false, sessionText, sizeof(sessionText));
	}
	return sessionText;
}



// =====[ PRIVATE ]=====

static int GetSessionTextPosition(KZPlayer player)
{
	if (player.GetHUDOption(HUDOption_ProgressText) == ProgressText_TPMenu)
	{
		return ProgressText_TPMenu;
	}
	return ProgressText_InfoPanel;
}

static void FormatSessionText(KZPlayer player, ReplaySessionInfo session, bool html, char[] buffer, int maxlength)
{
	char label[32];
	FormatEx(label, sizeof(label), "%T", session.type == ReplaySession_Lead ? "Session Text - Lead" : "Session Text - Race", player.ID);
	char status[128];
	FormatSessionStatus(player, session, html, status, sizeof(status));
	FormatEx(buffer, maxlength, "%s: %s", label, status);

	if (!ShowsProgress(session))
	{
		return;
	}
	char progress[64];
	FormatEx(progress, sizeof(progress), "%T", "Session Text - Progress", player.ID, RoundToFloor(session.playerProgress * 100.0), RoundToFloor(session.botProgress * 100.0));
	Format(buffer, maxlength, "%s (%s)", buffer, progress);
}

static bool ShowsProgress(ReplaySessionInfo session)
{
	if (session.state == ReplaySessionState_Running || session.state == ReplaySessionState_Waiting)
	{
		return true;
	}
	return session.state == ReplaySessionState_Finished && session.type == ReplaySession_Lead;
}

static void FormatSessionStatus(KZPlayer player, ReplaySessionInfo session, bool html, char[] buffer, int maxlength)
{
	switch (session.state)
	{
		case ReplaySessionState_Loading:
		{
			FormatPhrase(player, "Session Text - Loading", SESSION_COLOUR_VALUE, html, buffer, maxlength);
		}
		case ReplaySessionState_Countdown:
		{
			char countdown[32];
			FormatEx(countdown, sizeof(countdown), "%T", "Session Text - Countdown", player.ID, IntMax(RoundToCeil(session.countdown), 1));
			Colourise(countdown, SESSION_COLOUR_VALUE, html, buffer, maxlength);
		}
		case ReplaySessionState_Ready:
		{
			FormatPhrase(player, "Session Text - Ready", SESSION_COLOUR_VALUE, html, buffer, maxlength);
		}
		case ReplaySessionState_Waiting:
		{
			FormatPhrase(player, "Session Text - Waiting", SESSION_COLOUR_WAITING, html, buffer, maxlength);
		}
		case ReplaySessionState_Running:
		{
			FormatRunningStatus(player, session, html, buffer, maxlength);
		}
		case ReplaySessionState_Finished:
		{
			FormatFinishedStatus(player, session, html, buffer, maxlength);
		}
	}
}

static void FormatRunningStatus(KZPlayer player, ReplaySessionInfo session, bool html, char[] buffer, int maxlength)
{
	if (session.type == ReplaySession_Lead)
	{
		FormatPhrase(player, "Session Text - Following", SESSION_COLOUR_VALUE, html, buffer, maxlength);
		return;
	}
	if (!session.hasTimeDiff)
	{
		FormatPhrase(player, "Session Text - Racing", SESSION_COLOUR_VALUE, html, buffer, maxlength);
		return;
	}
	FormatTimeDiff(session.timeDiff, html, buffer, maxlength);
}

static void FormatFinishedStatus(KZPlayer player, ReplaySessionInfo session, bool html, char[] buffer, int maxlength)
{
	if (session.type == ReplaySession_Lead)
	{
		FormatPhrase(player, "Session Text - Done", SESSION_COLOUR_VALUE, html, buffer, maxlength);
		return;
	}
	if (session.resultDiff < SESSION_EVEN_THRESHOLD)
	{
		FormatPhrase(player, "Session Text - Tied", SESSION_COLOUR_VALUE, html, buffer, maxlength);
		return;
	}
	char result[32];
	FormatEx(result, sizeof(result), "%T", session.won ? "Session Text - Won" : "Session Text - Lost", player.ID, session.resultDiff);
	Colourise(result, session.won ? SESSION_COLOUR_AHEAD : SESSION_COLOUR_BEHIND, html, buffer, maxlength);
}

static void FormatTimeDiff(float timeDiff, bool html, char[] buffer, int maxlength)
{
	char diff[16];
	if (timeDiff <= -SESSION_EVEN_THRESHOLD)
	{
		FormatEx(diff, sizeof(diff), "-%.2f", FloatAbs(timeDiff));
		Colourise(diff, SESSION_COLOUR_AHEAD, html, buffer, maxlength);
		return;
	}
	if (timeDiff >= SESSION_EVEN_THRESHOLD)
	{
		FormatEx(diff, sizeof(diff), "+%.2f", timeDiff);
		Colourise(diff, SESSION_COLOUR_BEHIND, html, buffer, maxlength);
		return;
	}
	Colourise("0.00", SESSION_COLOUR_VALUE, html, buffer, maxlength);
}

static void FormatPhrase(KZPlayer player, const char[] phrase, const char[] colour, bool html, char[] buffer, int maxlength)
{
	char text[64];
	FormatEx(text, sizeof(text), "%T", phrase, player.ID);
	Colourise(text, colour, html, buffer, maxlength);
}

static void Colourise(const char[] text, const char[] colour, bool html, char[] buffer, int maxlength)
{
	if (!html)
	{
		strcopy(buffer, maxlength, text);
		return;
	}
	FormatEx(buffer, maxlength, "<font color='%s'>%s</font>", colour, text);
}
