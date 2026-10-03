/*
	SQL query templates.
*/



// =====[ MAPS ]=====

char sqlite_maps_alter1[] = "\
ALTER TABLE Maps \
    ADD InRankedPool INTEGER NOT NULL DEFAULT '0'";

char sqlite_maps_insertranked[] = "\
INSERT OR IGNORE INTO Maps \
    (InRankedPool, Name) \
    VALUES (%d, '%s')";

char sqlite_maps_updateranked[] = "\
UPDATE OR IGNORE Maps \
    SET InRankedPool=%d \
    WHERE Name = '%s'";

char mysql_maps_upsertranked[] = "\
INSERT INTO Maps (InRankedPool, Name) \
    VALUES (%d, '%s') \
    ON DUPLICATE KEY UPDATE \
    InRankedPool=VALUES(InRankedPool)";

char sql_maps_reset_mappool[] = "\
UPDATE Maps \
    SET InRankedPool=0";

char sql_maps_getname[] = "\
SELECT Name \
    FROM Maps \
    WHERE MapID=%d";

char sql_maps_searchbyname[] = "\
SELECT MapID, Name \
    FROM Maps \
    WHERE Name LIKE '%%%s%%' \
    ORDER BY (Name='%s') DESC, LENGTH(Name) \
    LIMIT 1";



// =====[ PLAYERS ]=====

char sql_players_getalias[] = "\
SELECT Alias \
    FROM Players \
    WHERE SteamID32=%d";

char sql_players_searchbyalias[] = "\
SELECT SteamID32, Alias \
    FROM Players \
    WHERE Players.Cheater=0 AND LOWER(Alias) LIKE '%%%s%%' \
    ORDER BY (LOWER(Alias)='%s') DESC, LastPlayed DESC \
    LIMIT 1";



// =====[ MAPCOURSES ]=====

char sql_mapcourses_findid[] = "\
SELECT MapCourseID \
    FROM MapCourses \
    WHERE MapID=%d AND Course=%d";



// =====[ GENERAL ]=====

char sql_getpb[] = "\
SELECT ValidTimes.RunTime, ValidTimes.Teleports \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    WHERE ValidTimes.SteamID32=%d AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d \
    ORDER BY ValidTimes.RunTime \
    LIMIT %d";

char sql_getpbpro[] = "\
SELECT ValidTimes.RunTime \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    WHERE ValidTimes.SteamID32=%d AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0 \
    ORDER BY ValidTimes.RunTime \
    LIMIT %d";

char sql_getmaptop[] = "\
SELECT t.TimeID, t.SteamID32, p.Alias, t.RunTime AS PBTime, t.Teleports \
    FROM ValidTimes t \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    LEFT OUTER JOIN ValidTimes t2 ON t2.SteamID32=t.SteamID32 \
    AND t2.MapCourseID=t.MapCourseID AND t2.Mode=t.Mode AND (t2.RunTime<t.RunTime OR (t2.RunTime=t.RunTime AND (t2.Created<t.Created OR (t2.Created=t.Created AND t2.TimeID<t.TimeID)))) \
    WHERE t2.TimeID IS NULL AND p.Cheater=0 AND mc.MapID=%d AND mc.Course=%d AND t.Mode=%d \
    ORDER BY PBTime \
    LIMIT %d";

char sql_getmaptoppro[] = "\
SELECT t.TimeID, t.SteamID32, p.Alias, t.RunTime AS PBTime, t.Teleports \
    FROM ValidTimes t \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    LEFT OUTER JOIN ValidTimes t2 ON t2.SteamID32=t.SteamID32 AND t2.MapCourseID=t.MapCourseID \
    AND t2.Mode=t.Mode AND (t2.RunTime<t.RunTime OR (t2.RunTime=t.RunTime AND (t2.Created<t.Created OR (t2.Created=t.Created AND t2.TimeID<t.TimeID)))) AND t.Teleports=0 AND t2.Teleports=0 \
    WHERE t2.TimeID IS NULL AND p.Cheater=0 AND mc.MapID=%d \
    AND mc.Course=%d AND t.Mode=%d AND t.Teleports=0 \
    ORDER BY PBTime \
    LIMIT %d";

char sql_getwrs[] = "\
SELECT MIN(ValidTimes.RunTime), MapCourses.Course, ValidTimes.Mode \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d \
    GROUP BY MapCourses.Course, ValidTimes.Mode";

char sql_getwrspro[] = "\
SELECT MIN(ValidTimes.RunTime), MapCourses.Course, ValidTimes.Mode \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d AND ValidTimes.Teleports=0 \
    GROUP BY MapCourses.Course, ValidTimes.Mode";

char sql_getpbs[] = "\
SELECT MIN(ValidTimes.RunTime), MapCourses.Course, ValidTimes.Mode \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    WHERE ValidTimes.SteamID32=%d AND MapCourses.MapID=%d \
    GROUP BY MapCourses.Course, ValidTimes.Mode";

char sql_getpbspro[] = "\
SELECT MIN(ValidTimes.RunTime), MapCourses.Course, ValidTimes.Mode \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    WHERE ValidTimes.SteamID32=%d AND MapCourses.MapID=%d AND ValidTimes.Teleports=0 \
    GROUP BY MapCourses.Course, ValidTimes.Mode";

char sql_getmaprank[] = "\
SELECT COUNT(DISTINCT ValidTimes.SteamID32) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d AND MapCourses.Course=%d \
    AND ValidTimes.Mode=%d AND ValidTimes.RunTime < \
    (SELECT MIN(ValidTimes.RunTime) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND ValidTimes.SteamID32=%d AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d) \
    + 1";

char sql_getmaprankpro[] = "\
SELECT COUNT(DISTINCT ValidTimes.SteamID32) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d AND MapCourses.Course=%d \
    AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0 \
    AND ValidTimes.RunTime < \
    (SELECT MIN(ValidTimes.RunTime) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND ValidTimes.SteamID32=%d AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0) \
    + 1";

char sql_getlowestmaprank[] = "\
SELECT COUNT(DISTINCT ValidTimes.SteamID32) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d";

char sql_getlowestmaprankpro[] = "\
SELECT COUNT(DISTINCT ValidTimes.SteamID32) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0";

char sql_getcount_maincourses[] = "\
SELECT COUNT(*) \
    FROM MapCourses \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    WHERE Maps.InRankedPool=1 AND MapCourses.Course=0";

char sql_getcount_maincoursescompleted[] = "\
SELECT COUNT(DISTINCT ValidTimes.MapCourseID) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    WHERE Maps.InRankedPool=1 AND MapCourses.Course=0 \
    AND ValidTimes.SteamID32=%d AND ValidTimes.Mode=%d";

char sql_getcount_maincoursescompletedpro[] = "\
SELECT COUNT(DISTINCT ValidTimes.MapCourseID) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    WHERE Maps.InRankedPool=1 AND MapCourses.Course=0 \
    AND ValidTimes.SteamID32=%d AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0";

char sql_getcount_bonuses[] = "\
SELECT COUNT(*) \
    FROM MapCourses \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    WHERE Maps.InRankedPool=1 AND MapCourses.Course>0";

char sql_getcount_bonusescompleted[] = "\
SELECT COUNT(DISTINCT ValidTimes.MapCourseID) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    WHERE Maps.InRankedPool=1 AND MapCourses.Course>0 \
    AND ValidTimes.SteamID32=%d AND ValidTimes.Mode=%d";

char sql_getcount_bonusescompletedpro[] = "\
SELECT COUNT(DISTINCT ValidTimes.MapCourseID) \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    WHERE Maps.InRankedPool=1 AND MapCourses.Course>0 \
    AND ValidTimes.SteamID32=%d AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0";

char sql_gettopplayers[] = "\
SELECT Players.SteamID32, Players.Alias, COUNT(DISTINCT ValidTimes.MapCourseID) AS RecordCount \
    FROM ValidTimes \
    INNER JOIN \
    (SELECT ValidTimes.MapCourseID, ValidTimes.Mode, MIN(ValidTimes.RunTime) AS RecordTime \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND Maps.InRankedPool=1 AND MapCourses.Course=0 \
    AND ValidTimes.Mode=%d \
    GROUP BY ValidTimes.MapCourseID) Records \
    ON ValidTimes.MapCourseID=Records.MapCourseID AND ValidTimes.Mode=Records.Mode AND ValidTimes.RunTime=Records.RecordTime \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 \
    GROUP BY Players.SteamID32, Players.Alias \
    ORDER BY RecordCount DESC \
    LIMIT %d"; // Doesn't include bonuses

char sql_gettopplayerspro[] = "\
SELECT Players.SteamID32, Players.Alias, COUNT(DISTINCT ValidTimes.MapCourseID) AS RecordCount \
    FROM ValidTimes \
    INNER JOIN \
    (SELECT ValidTimes.MapCourseID, ValidTimes.Mode, MIN(ValidTimes.RunTime) AS RecordTime \
    FROM ValidTimes \
    INNER JOIN MapCourses ON MapCourses.MapCourseID=ValidTimes.MapCourseID \
    INNER JOIN Maps ON Maps.MapID=MapCourses.MapID \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 AND Maps.InRankedPool=1 AND MapCourses.Course=0 \
    AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0 \
    GROUP BY ValidTimes.MapCourseID) Records \
    ON ValidTimes.MapCourseID=Records.MapCourseID AND ValidTimes.Mode=Records.Mode AND ValidTimes.RunTime=Records.RecordTime AND ValidTimes.Teleports=0 \
    INNER JOIN Players ON Players.SteamID32=ValidTimes.SteamID32 \
    WHERE Players.Cheater=0 \
    GROUP BY Players.SteamID32, Players.Alias \
    ORDER BY RecordCount DESC \
    LIMIT %d"; // Doesn't include bonuses

char sql_getaverage[] = "\
SELECT AVG(PBTime), COUNT(*) \
    FROM \
    (SELECT MIN(ValidTimes.RunTime) AS PBTime \
    FROM ValidTimes \
    INNER JOIN MapCourses ON ValidTimes.MapCourseID=MapCourses.MapCourseID \
    INNER JOIN Players ON ValidTimes.SteamID32=Players.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d \
    GROUP BY ValidTimes.SteamID32) AS PBTimes";

char sql_getaverage_pro[] = "\
SELECT AVG(PBTime), COUNT(*) \
    FROM \
    (SELECT MIN(ValidTimes.RunTime) AS PBTime \
    FROM ValidTimes \
    INNER JOIN MapCourses ON ValidTimes.MapCourseID=MapCourses.MapCourseID \
    INNER JOIN Players ON ValidTimes.SteamID32=Players.SteamID32 \
    WHERE Players.Cheater=0 AND MapCourses.MapID=%d \
    AND MapCourses.Course=%d AND ValidTimes.Mode=%d AND ValidTimes.Teleports=0 \
    GROUP BY ValidTimes.SteamID32) AS PBTimes";

char sql_getrecentrecords[] = "\
SELECT Maps.Name, MapCourses.Course, MapCourses.MapCourseID, Players.Alias, a.RunTime \
    FROM ValidTimes AS a \
    INNER JOIN MapCourses ON a.MapCourseID=MapCourses.MapCourseID \
    INNER JOIN Maps ON MapCourses.MapID=Maps.MapID \
    INNER JOIN Players ON a.SteamID32=Players.SteamID32 \
    WHERE Players.Cheater=0 AND Maps.InRankedPool AND a.Mode=%d \
    AND NOT EXISTS \
    (SELECT * \
    FROM ValidTimes AS b \
    WHERE a.MapCourseID=b.MapCourseID AND a.Mode=b.Mode \
    AND a.Created>b.Created AND a.RunTime>b.RunTime) \
    ORDER BY a.TimeID DESC \
    LIMIT %d";

char sql_getrecentrecords_pro[] = "\
SELECT Maps.Name, MapCourses.Course, MapCourses.MapCourseID, Players.Alias, a.RunTime \
    FROM ValidTimes AS a \
    INNER JOIN MapCourses ON a.MapCourseID=MapCourses.MapCourseID \
    INNER JOIN Maps ON MapCourses.MapID=Maps.MapID \
    INNER JOIN Players ON a.SteamID32=Players.SteamID32 \
    WHERE Players.Cheater=0 AND Maps.InRankedPool AND a.Mode=%d AND a.Teleports=0 \
    AND NOT EXISTS \
    (SELECT * \
    FROM ValidTimes AS b \
    WHERE b.Teleports=0 AND a.MapCourseID=b.MapCourseID AND a.Mode=b.Mode \
    AND a.Created>b.Created AND a.RunTime>b.RunTime) \
    ORDER BY a.TimeID DESC \
    LIMIT %d";



// =====[ JUMPSTATS ]=====

char sql_jumpstats_gettop[] = "\
SELECT j.JumpID, p.SteamID32, p.Alias, j.Block, j.Distance, j.Strafes, j.Sync, j.Pre, j.Max, j.Airtime \
    FROM ValidJumpstats j JOIN Players p ON p.SteamID32=j.SteamID32 \
    WHERE p.Cheater=0 AND j.JumpType=%d AND j.Mode=%d AND j.IsBlockJump=%d \
    AND NOT EXISTS (SELECT 1 FROM ValidJumpstats b WHERE b.SteamID32=j.SteamID32 \
        AND b.JumpType=%d AND b.Mode=%d AND b.IsBlockJump=%d \
        AND (b.Block>j.Block OR (b.Block=j.Block AND (b.Distance>j.Distance OR (b.Distance=j.Distance \
            AND (b.Created<j.Created OR (b.Created=j.Created AND b.JumpID<j.JumpID))))))) \
    ORDER BY j.Block DESC, j.Distance DESC, j.Created, j.JumpID LIMIT %d";

char mysql_jumpstats_gettop[] = "\
SELECT j.JumpID, p.SteamID32, p.Alias, j.Block, j.Distance, j.Strafes, j.Sync, j.Pre, j.Max, j.Airtime \
    FROM JumpPersonalBests b JOIN ValidJumpstats j ON j.JumpID=b.JumpID \
    JOIN Players p ON p.SteamID32=j.SteamID32 \
    WHERE p.Cheater=0 AND j.JumpType=%d AND j.Mode=%d AND j.IsBlockJump=%d \
    ORDER BY j.Block DESC, j.Distance DESC, j.Created, j.JumpID LIMIT %d";

char sql_jumpstats_getrecord[] = "\
SELECT JumpID, Distance, Block \
    FROM \
        ValidJumpstats rec \
    WHERE \
        SteamID32 = %d AND \
        JumpType = %d AND \
        Mode = %d AND \
        IsBlockJump = %d \
    ORDER BY Block DESC, Distance DESC";

char sql_jumpstats_getpbs[] = "\
SELECT b.JumpID, b.JumpType, b.Distance, b.Strafes, b.Sync, b.Pre, b.Max, b.Airtime \
    FROM ValidJumpstats b WHERE b.SteamID32=%d AND b.Mode=%d AND NOT b.IsBlockJump \
    AND NOT EXISTS (SELECT 1 FROM ValidJumpstats tie WHERE tie.SteamID32=b.SteamID32 AND tie.Mode=b.Mode \
        AND tie.JumpType=b.JumpType AND NOT tie.IsBlockJump AND (tie.Distance>b.Distance OR (tie.Distance=b.Distance \
            AND (tie.Created<b.Created OR (tie.Created=b.Created AND tie.JumpID<b.JumpID))))) \
    ORDER BY b.JumpType";

char sql_jumpstats_getblockpbs[] = "\
SELECT b.JumpID, b.JumpType, b.Block, b.Distance, b.Strafes, b.Sync, b.Pre, b.Max, b.Airtime \
    FROM ValidJumpstats b WHERE b.SteamID32=%d AND b.Mode=%d AND b.IsBlockJump \
    AND NOT EXISTS (SELECT 1 FROM ValidJumpstats tie WHERE tie.SteamID32=b.SteamID32 AND tie.Mode=b.Mode \
        AND tie.JumpType=b.JumpType AND tie.IsBlockJump AND (tie.Block>b.Block OR (tie.Block=b.Block \
            AND (tie.Distance>b.Distance OR (tie.Distance=b.Distance AND (tie.Created<b.Created \
                OR (tie.Created=b.Created AND tie.JumpID<b.JumpID))))))) \
    ORDER BY b.JumpType";
