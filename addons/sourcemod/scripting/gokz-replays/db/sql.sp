/*
	SQL queries for the Replays table.
*/



// =====[ REPLAYS ]=====

char sqlite_replays_create[] = "\
CREATE TABLE IF NOT EXISTS Replays ( \
    ReplayID INTEGER NOT NULL, \
    ReplayType INTEGER NOT NULL, \
    TimeID INTEGER NULL, \
    JumpID INTEGER NULL, \
    SteamID32 INTEGER NOT NULL, \
    ObjectKey TEXT NOT NULL, \
    FileSize INTEGER NOT NULL, \
    InStore INTEGER NOT NULL DEFAULT 0, \
    MapName TEXT NOT NULL DEFAULT '', \
    Code TEXT NOT NULL, \
    Created INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Replays PRIMARY KEY (ReplayID), \
    CONSTRAINT UQ_Replays_ObjectKey UNIQUE (ObjectKey), \
    CONSTRAINT UQ_Replays_Code UNIQUE (Code), \
    CONSTRAINT FK_Replays_TimeID FOREIGN KEY (TimeID) REFERENCES Times(TimeID) \
    ON UPDATE CASCADE ON DELETE CASCADE, \
    CONSTRAINT FK_Replays_JumpID FOREIGN KEY (JumpID) REFERENCES Jumpstats(JumpID) \
    ON UPDATE CASCADE ON DELETE CASCADE)";

char sqlite_replays_index_timeid[] = "\
CREATE INDEX IF NOT EXISTS IX_Replays_TimeID ON Replays (TimeID)";

char sqlite_replays_index_jumpid[] = "\
CREATE INDEX IF NOT EXISTS IX_Replays_JumpID ON Replays (JumpID)";

char sqlite_replays_index_steamid[] = "\
CREATE INDEX IF NOT EXISTS IX_Replays_SteamID32 ON Replays (SteamID32)";

char mysql_replays_create[] = "\
CREATE TABLE IF NOT EXISTS Replays ( \
    ReplayID INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, \
    ReplayType TINYINT UNSIGNED NOT NULL, \
    TimeID INTEGER UNSIGNED NULL, \
    JumpID INTEGER UNSIGNED NULL, \
    SteamID32 INTEGER UNSIGNED NOT NULL, \
    ObjectKey VARCHAR(191) NOT NULL, \
    FileSize INTEGER UNSIGNED NOT NULL, \
    InStore TINYINT UNSIGNED NOT NULL DEFAULT 0, \
    MapName VARCHAR(64) NOT NULL DEFAULT '', \
    Code VARCHAR(8) NOT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Replays PRIMARY KEY (ReplayID), \
    CONSTRAINT UQ_Replays_ObjectKey UNIQUE (ObjectKey), \
    CONSTRAINT UQ_Replays_Code UNIQUE (Code), \
    INDEX IX_Replays_TimeID (TimeID), \
    INDEX IX_Replays_JumpID (JumpID), \
    INDEX IX_Replays_SteamID32 (SteamID32), \
    CONSTRAINT FK_Replays_TimeID FOREIGN KEY (TimeID) REFERENCES Times(TimeID) \
    ON UPDATE CASCADE ON DELETE CASCADE, \
    CONSTRAINT FK_Replays_JumpID FOREIGN KEY (JumpID) REFERENCES Jumpstats(JumpID) \
    ON UPDATE CASCADE ON DELETE CASCADE)";

char sqlite_replays_upsert[] = "\
INSERT INTO Replays (ReplayType, TimeID, JumpID, SteamID32, ObjectKey, FileSize, InStore, MapName, Code, Created) \
    VALUES (%d, %s, %s, %d, '%s', %d, %d, '%s', '%s', %s) \
    ON CONFLICT(ObjectKey) DO UPDATE SET FileSize=excluded.FileSize, InStore=excluded.InStore, MapName=excluded.MapName, Created=excluded.Created";

char mysql_replays_upsert[] = "\
INSERT INTO Replays (ReplayType, TimeID, JumpID, SteamID32, ObjectKey, FileSize, InStore, MapName, Code, Created) \
    VALUES (%d, %s, %s, %d, '%s', %d, %d, '%s', '%s', %s) \
    ON DUPLICATE KEY UPDATE FileSize=VALUES(FileSize), InStore=VALUES(InStore), MapName=VALUES(MapName), Created=VALUES(Created)";

char sql_replays_created_from_time[] = "COALESCE((SELECT Created FROM Times WHERE TimeID=%d), CURRENT_TIMESTAMP)";
char sql_replays_created_from_jump[] = "COALESCE((SELECT Created FROM Jumpstats WHERE JumpID=%d), CURRENT_TIMESTAMP)";

char sql_replays_getbycode[] = "\
SELECT ObjectKey, FileSize, InStore \
    FROM Replays \
    WHERE Code='%s' \
    LIMIT 1";

char sql_replays_getcode[] = "\
SELECT Code \
    FROM Replays \
    WHERE ObjectKey='%s' \
    LIMIT 1";

#define SQL_REPLAY_RUN_COLUMNS "r.ReplayID, r.ReplayType, r.ObjectKey, r.FileSize, r.InStore, r.MapName, p.Alias, r.Created, r.Code, t.Mode, t.RunTime, t.Teleports, mc.Course, 0 AS JumpType, 0 AS Distance, 0 AS Block, 0 AS Strafes, 0 AS Sync, 0 AS Pre, 0 AS Max, (SELECT COUNT(DISTINCT t3.SteamID32) FROM Times t3 INNER JOIN Players p3 ON p3.SteamID32=t3.SteamID32 WHERE p3.Cheater=0 AND t3.MapCourseID=t.MapCourseID AND t3.Mode=t.Mode AND t3.RunTime<t.RunTime AND (t.Teleports>0 OR t3.Teleports=0)) + 1 AS Rank"
#define SQL_REPLAY_JUMP_COLUMNS "r.ReplayID, r.ReplayType, r.ObjectKey, r.FileSize, r.InStore, r.MapName, p.Alias, r.Created, r.Code, j.Mode, 0, 0, 0, j.JumpType, j.Distance, j.Block, j.Strafes, j.Sync, j.Pre, j.Max, 0 AS Rank"

char sql_replays_getrecent[] = "\
SELECT " ... SQL_REPLAY_RUN_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    WHERE r.ReplayType=0 AND p.Cheater=0%s \
UNION ALL \
SELECT " ... SQL_REPLAY_JUMP_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Jumpstats j ON j.JumpID=r.JumpID \
    INNER JOIN Players p ON p.SteamID32=j.SteamID32 \
    WHERE r.ReplayType=2 AND p.Cheater=0%s \
ORDER BY ReplayID DESC \
LIMIT %d";

char sql_replays_delete_by_jump[] = "\
DELETE FROM Replays \
    WHERE JumpID=%d";

char sql_replays_findmap[] = "\
SELECT MapName \
    FROM Replays \
    WHERE MapName LIKE '%%%s%%' \
    ORDER BY (MapName='%s') DESC, LENGTH(MapName) \
    LIMIT 1";

char sql_replays_getmaps[] = "\
SELECT r.MapName, COUNT(*) \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    WHERE r.ReplayType=0 AND p.Cheater=0 AND r.MapName<>''%s \
    GROUP BY r.MapName \
    ORDER BY MAX(r.ReplayID) DESC \
    LIMIT %d";

char sql_replays_getcourses[] = "\
SELECT DISTINCT mc.Course \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    WHERE r.ReplayType=0 AND p.Cheater=0 AND r.MapName='%s' AND t.Mode=%d \
    ORDER BY mc.Course";

char sql_replays_gettop[] = "\
SELECT " ... SQL_REPLAY_RUN_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    LEFT OUTER JOIN Times t2 ON t2.SteamID32=t.SteamID32 AND t2.MapCourseID=t.MapCourseID \
    AND t2.Mode=t.Mode AND t2.RunTime<t.RunTime \
    AND EXISTS (SELECT 1 FROM Replays r2 WHERE r2.TimeID=t2.TimeID) \
    WHERE r.ReplayType=0 AND t2.TimeID IS NULL AND p.Cheater=0 \
    AND r.MapName='%s' AND mc.Course=%d AND t.Mode=%d \
    ORDER BY t.RunTime \
    LIMIT %d";

char sql_replays_gettoppro[] = "\
SELECT " ... SQL_REPLAY_RUN_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    LEFT OUTER JOIN Times t2 ON t2.SteamID32=t.SteamID32 AND t2.MapCourseID=t.MapCourseID \
    AND t2.Mode=t.Mode AND t2.RunTime<t.RunTime AND t2.Teleports=0 \
    AND EXISTS (SELECT 1 FROM Replays r2 WHERE r2.TimeID=t2.TimeID) \
    WHERE r.ReplayType=0 AND t2.TimeID IS NULL AND p.Cheater=0 \
    AND r.MapName='%s' AND mc.Course=%d AND t.Mode=%d AND t.Teleports=0 \
    ORDER BY t.RunTime \
    LIMIT %d";

char sql_replays_getmine[] = "\
SELECT " ... SQL_REPLAY_RUN_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    WHERE r.ReplayType=0 AND t.SteamID32=%d AND r.MapName='%s' AND mc.Course=%d AND t.Mode=%d \
    ORDER BY t.RunTime \
    LIMIT %d";

char sql_replays_getjumps[] = "\
SELECT " ... SQL_REPLAY_JUMP_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Jumpstats j ON j.JumpID=r.JumpID \
    INNER JOIN Players p ON p.SteamID32=j.SteamID32 \
    WHERE r.ReplayType=2 AND p.Cheater=0 AND j.JumpType=%d AND j.Mode=%d%s \
    ORDER BY j.Distance DESC \
    LIMIT %d";

char sql_replays_getroute[] = "\
SELECT " ... SQL_REPLAY_RUN_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    WHERE r.ReplayType=0 AND p.Cheater=0 AND r.MapName='%s' AND mc.Course=0 \
    ORDER BY t.RunTime \
    LIMIT %d";

char sql_replays_getpb[] = "\
SELECT " ... SQL_REPLAY_RUN_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    WHERE r.ReplayType=0 AND t.SteamID32=%d AND r.MapName='%s' AND mc.Course=0 AND t.Mode=%d \
    ORDER BY t.RunTime \
    LIMIT %d";

char sql_replays_getruncode[] = "\
SELECT " ... SQL_REPLAY_RUN_COLUMNS ... " \
    FROM Replays r \
    INNER JOIN Times t ON t.TimeID=r.TimeID \
    INNER JOIN MapCourses mc ON mc.MapCourseID=t.MapCourseID \
    INNER JOIN Players p ON p.SteamID32=t.SteamID32 \
    WHERE r.ReplayType=0 AND r.Code='%s' \
    LIMIT 1";

char sql_replays_getbytime[] = "\
SELECT ObjectKey, FileSize, InStore \
    FROM Replays \
    WHERE TimeID=%d \
    ORDER BY ReplayID DESC \
    LIMIT 1";

char sql_replays_getbyjump[] = "\
SELECT ObjectKey, FileSize, InStore \
    FROM Replays \
    WHERE JumpID=%d \
    ORDER BY ReplayID DESC \
    LIMIT 1";
