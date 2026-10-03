CREATE TABLE IF NOT EXISTS PersonalBests (
    SteamID32 INT UNSIGNED NOT NULL,
    MapCourseID INT UNSIGNED NOT NULL,
    Mode TINYINT UNSIGNED NOT NULL,
    Style TINYINT UNSIGNED NOT NULL,
    Category TINYINT UNSIGNED NOT NULL,
    TimeID INT UNSIGNED NOT NULL,
    RunTime INT UNSIGNED NOT NULL,
    Created TIMESTAMP NOT NULL,
    PRIMARY KEY (SteamID32, MapCourseID, Mode, Style, Category),
    INDEX IX_PersonalBests_Board (Category, MapCourseID, Mode, Style, RunTime, SteamID32),
    INDEX IX_PersonalBests_Created (Category, Created, SteamID32, MapCourseID, Mode, Style),
    INDEX IX_PersonalBests_TimeID (TimeID),
    CONSTRAINT FK_PersonalBests_TimeID FOREIGN KEY (TimeID) REFERENCES Times (TimeID)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS JumpPersonalBests (
    SteamID32 INT UNSIGNED NOT NULL,
    Mode TINYINT UNSIGNED NOT NULL,
    JumpType TINYINT UNSIGNED NOT NULL,
    IsBlockJump TINYINT UNSIGNED NOT NULL,
    JumpID INT UNSIGNED NOT NULL,
    Block SMALLINT UNSIGNED NOT NULL,
    Distance INT UNSIGNED NOT NULL,
    Created TIMESTAMP NOT NULL,
    PRIMARY KEY (SteamID32, Mode, JumpType, IsBlockJump),
    INDEX IX_JumpPersonalBests_Board (IsBlockJump, Mode, JumpType, Block, Distance, Created, JumpID),
    INDEX IX_JumpPersonalBests_JumpID (JumpID),
    CONSTRAINT FK_JumpPersonalBests_JumpID FOREIGN KEY (JumpID) REFERENCES Jumpstats (JumpID)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS DailyRunActivity (
    Day DATE NOT NULL,
    SteamID32 INT UNSIGNED NOT NULL,
    MapCourseID INT UNSIGNED NOT NULL,
    Mode TINYINT UNSIGNED NOT NULL,
    Style TINYINT UNSIGNED NOT NULL,
    Category TINYINT UNSIGNED NOT NULL,
    RunCount BIGINT UNSIGNED NOT NULL,
    BestRunTime INT UNSIGNED NOT NULL,
    LastCreated TIMESTAMP NOT NULL,
    PRIMARY KEY (Day, SteamID32, MapCourseID, Mode, Style, Category),
    INDEX IX_DailyRunActivity_Player (SteamID32, Category, Day),
    INDEX IX_DailyRunActivity_Board (Category, MapCourseID, Mode, Style, Day)
) ENGINE=InnoDB;

DELIMITER //
CREATE OR REPLACE PROCEDURE Gokz_AddRunProjection(
    IN accountID INT UNSIGNED, IN courseID INT UNSIGNED, IN runMode TINYINT UNSIGNED,
    IN runStyle TINYINT UNSIGNED, IN runCategory TINYINT UNSIGNED, IN recordID INT UNSIGNED,
    IN milliseconds INT UNSIGNED, IN achieved TIMESTAMP)
BEGIN
    INSERT INTO PersonalBests (SteamID32, MapCourseID, Mode, Style, Category, TimeID, RunTime, Created)
    VALUES (accountID, courseID, runMode, runStyle, runCategory, recordID, milliseconds, achieved)
    ON DUPLICATE KEY UPDATE
        TimeID = IF((VALUES(RunTime), VALUES(Created), VALUES(TimeID)) < (RunTime, Created, TimeID), VALUES(TimeID), TimeID),
        Created = IF((VALUES(RunTime), VALUES(Created)) < (RunTime, Created), VALUES(Created), Created),
        RunTime = LEAST(RunTime, VALUES(RunTime));
    INSERT INTO DailyRunActivity (Day, SteamID32, MapCourseID, Mode, Style, Category, RunCount, BestRunTime, LastCreated)
    VALUES (DATE(TIMESTAMPADD(SECOND, UNIX_TIMESTAMP(achieved), '1970-01-01 00:00:00')), accountID, courseID, runMode, runStyle, runCategory, 1, milliseconds, achieved)
    ON DUPLICATE KEY UPDATE
        RunCount = RunCount + 1,
        BestRunTime = LEAST(BestRunTime, VALUES(BestRunTime)),
        LastCreated = GREATEST(LastCreated, VALUES(LastCreated));
END//

CREATE OR REPLACE TRIGGER Times_LockProjection BEFORE INSERT ON Times FOR EACH ROW
BEGIN
    DECLARE lockedAccount INT UNSIGNED;
    SELECT SteamID32 INTO lockedAccount FROM Players WHERE SteamID32 = NEW.SteamID32 FOR UPDATE;
END//

CREATE OR REPLACE TRIGGER InvalidTimes_LockProjection BEFORE INSERT ON InvalidTimes FOR EACH ROW
BEGIN
    DECLARE accountID INT UNSIGNED;
    DECLARE lockedAccount INT UNSIGNED;
    SELECT SteamID32 INTO accountID FROM Times WHERE TimeID = NEW.TimeID;
    SELECT SteamID32 INTO lockedAccount FROM Players WHERE SteamID32 = accountID FOR UPDATE;
END//

CREATE OR REPLACE TRIGGER Jumpstats_LockProjection BEFORE INSERT ON Jumpstats FOR EACH ROW
BEGIN
    DECLARE lockedAccount INT UNSIGNED;
    SELECT SteamID32 INTO lockedAccount FROM Players WHERE SteamID32 = NEW.SteamID32 FOR UPDATE;
END//

CREATE OR REPLACE TRIGGER InvalidJumps_LockProjection BEFORE INSERT ON InvalidJumps FOR EACH ROW
BEGIN
    DECLARE accountID INT UNSIGNED;
    DECLARE lockedAccount INT UNSIGNED;
    SELECT SteamID32 INTO accountID FROM Jumpstats WHERE JumpID = NEW.JumpID;
    SELECT SteamID32 INTO lockedAccount FROM Players WHERE SteamID32 = accountID FOR UPDATE;
END//

CREATE OR REPLACE TRIGGER Times_Project AFTER INSERT ON Times FOR EACH ROW
BEGIN
    IF NEW.RunTime > 0 THEN
        CALL Gokz_AddRunProjection(NEW.SteamID32, NEW.MapCourseID, NEW.Mode, NEW.Style, 0, NEW.TimeID, NEW.RunTime, NEW.Created);
        IF NEW.Teleports = 0 THEN
            CALL Gokz_AddRunProjection(NEW.SteamID32, NEW.MapCourseID, NEW.Mode, NEW.Style, 1, NEW.TimeID, NEW.RunTime, NEW.Created);
        END IF;
    END IF;
END//

CREATE OR REPLACE TRIGGER Jumpstats_Project AFTER INSERT ON Jumpstats FOR EACH ROW
BEGIN
    INSERT INTO JumpPersonalBests (SteamID32, Mode, JumpType, IsBlockJump, JumpID, Block, Distance, Created)
    VALUES (NEW.SteamID32, NEW.Mode, NEW.JumpType, NEW.IsBlockJump, NEW.JumpID, NEW.Block, NEW.Distance, NEW.Created)
    ON DUPLICATE KEY UPDATE
        JumpID = IF((VALUES(Block), VALUES(Distance)) > (Block, Distance)
            OR ((VALUES(Block), VALUES(Distance)) = (Block, Distance) AND (VALUES(Created), VALUES(JumpID)) < (Created, JumpID)), VALUES(JumpID), JumpID),
        Created = IF((VALUES(Block), VALUES(Distance)) > (Block, Distance)
            OR ((VALUES(Block), VALUES(Distance)) = (Block, Distance) AND VALUES(Created) < Created), VALUES(Created), Created),
        Distance = IF(VALUES(Block) > Block, VALUES(Distance), IF(VALUES(Block) = Block, GREATEST(Distance, VALUES(Distance)), Distance)),
        Block = GREATEST(Block, VALUES(Block));
END//

CREATE OR REPLACE TRIGGER InvalidTimes_Project AFTER INSERT ON InvalidTimes FOR EACH ROW
BEGIN
    DELETE FROM PersonalBests WHERE TimeID = NEW.TimeID;
    INSERT INTO PersonalBests (SteamID32, MapCourseID, Mode, Style, Category, TimeID, RunTime, Created)
    SELECT SteamID32, MapCourseID, Mode, Style, Category, TimeID, RunTime, Created
    FROM (
        SELECT t.*, categories.Category,
            ROW_NUMBER() OVER (PARTITION BY t.SteamID32, t.MapCourseID, t.Mode, t.Style, categories.Category ORDER BY t.RunTime, t.Created, t.TimeID) AS Position
        FROM ValidTimes t JOIN Times invalid ON invalid.TimeID = NEW.TimeID
            AND t.SteamID32 = invalid.SteamID32 AND t.MapCourseID = invalid.MapCourseID
            AND t.Mode = invalid.Mode AND t.Style = invalid.Style
        JOIN (SELECT 0 AS Category UNION ALL SELECT 1) categories ON categories.Category = 0 OR t.Teleports = 0
        WHERE t.RunTime > 0
    ) candidates WHERE Position = 1
    ON DUPLICATE KEY UPDATE TimeID = VALUES(TimeID), RunTime = VALUES(RunTime), Created = VALUES(Created);
    DELETE a FROM DailyRunActivity a JOIN Times t ON t.TimeID = NEW.TimeID
        AND a.Day = DATE(TIMESTAMPADD(SECOND, UNIX_TIMESTAMP(t.Created), '1970-01-01 00:00:00')) AND a.SteamID32 = t.SteamID32 AND a.MapCourseID = t.MapCourseID AND a.Mode = t.Mode AND a.Style = t.Style;
    INSERT INTO DailyRunActivity (Day, SteamID32, MapCourseID, Mode, Style, Category, RunCount, BestRunTime, LastCreated)
    SELECT DATE(TIMESTAMPADD(SECOND, UNIX_TIMESTAMP(t.Created), '1970-01-01 00:00:00')), t.SteamID32, t.MapCourseID, t.Mode, t.Style, categories.Category, COUNT(*), MIN(t.RunTime), MAX(t.Created)
    FROM ValidTimes t JOIN Times invalid ON invalid.TimeID = NEW.TimeID
        AND t.SteamID32 = invalid.SteamID32 AND t.MapCourseID = invalid.MapCourseID AND t.Mode = invalid.Mode AND t.Style = invalid.Style
        AND t.Created >= FROM_UNIXTIME(FLOOR(UNIX_TIMESTAMP(invalid.Created) / 86400) * 86400) AND t.Created < FROM_UNIXTIME((FLOOR(UNIX_TIMESTAMP(invalid.Created) / 86400) + 1) * 86400)
    JOIN (SELECT 0 AS Category UNION ALL SELECT 1) categories ON categories.Category = 0 OR t.Teleports = 0
    WHERE t.RunTime > 0 GROUP BY DATE(TIMESTAMPADD(SECOND, UNIX_TIMESTAMP(t.Created), '1970-01-01 00:00:00')), t.SteamID32, t.MapCourseID, t.Mode, t.Style, categories.Category;
END//

CREATE OR REPLACE TRIGGER InvalidJumps_Project AFTER INSERT ON InvalidJumps FOR EACH ROW
BEGIN
    DELETE FROM JumpPersonalBests WHERE JumpID = NEW.JumpID;
    INSERT INTO JumpPersonalBests (SteamID32, Mode, JumpType, IsBlockJump, JumpID, Block, Distance, Created)
    SELECT SteamID32, Mode, JumpType, IsBlockJump, JumpID, Block, Distance, Created
    FROM (
        SELECT j.*, ROW_NUMBER() OVER (PARTITION BY j.SteamID32, j.Mode, j.JumpType, j.IsBlockJump ORDER BY j.Block DESC, j.Distance DESC, j.Created, j.JumpID) AS Position
        FROM ValidJumpstats j JOIN Jumpstats invalid ON invalid.JumpID = NEW.JumpID
            AND j.SteamID32 = invalid.SteamID32 AND j.Mode = invalid.Mode AND j.JumpType = invalid.JumpType AND j.IsBlockJump = invalid.IsBlockJump
    ) candidates WHERE Position = 1
    ON DUPLICATE KEY UPDATE JumpID = VALUES(JumpID), Block = VALUES(Block), Distance = VALUES(Distance), Created = VALUES(Created);
END//
DELIMITER ;

INSERT INTO PersonalBests (SteamID32, MapCourseID, Mode, Style, Category, TimeID, RunTime, Created)
SELECT SteamID32, MapCourseID, Mode, Style, Category, TimeID, RunTime, Created
FROM (
    SELECT t.*, categories.Category,
        ROW_NUMBER() OVER (PARTITION BY t.SteamID32, t.MapCourseID, t.Mode, t.Style, categories.Category ORDER BY t.RunTime, t.Created, t.TimeID) AS Position
    FROM ValidTimes t JOIN (SELECT 0 AS Category UNION ALL SELECT 1) categories ON categories.Category = 0 OR t.Teleports = 0
    WHERE t.RunTime > 0
) candidates WHERE Position = 1
ON DUPLICATE KEY UPDATE TimeID = VALUES(TimeID), RunTime = VALUES(RunTime), Created = VALUES(Created);

INSERT INTO JumpPersonalBests (SteamID32, Mode, JumpType, IsBlockJump, JumpID, Block, Distance, Created)
SELECT SteamID32, Mode, JumpType, IsBlockJump, JumpID, Block, Distance, Created
FROM (
    SELECT j.*, ROW_NUMBER() OVER (PARTITION BY j.SteamID32, j.Mode, j.JumpType, j.IsBlockJump ORDER BY j.Block DESC, j.Distance DESC, j.Created, j.JumpID) AS Position
    FROM ValidJumpstats j
) candidates WHERE Position = 1
ON DUPLICATE KEY UPDATE JumpID = VALUES(JumpID), Block = VALUES(Block), Distance = VALUES(Distance), Created = VALUES(Created);

INSERT INTO DailyRunActivity (Day, SteamID32, MapCourseID, Mode, Style, Category, RunCount, BestRunTime, LastCreated)
SELECT DATE(TIMESTAMPADD(SECOND, UNIX_TIMESTAMP(t.Created), '1970-01-01 00:00:00')), t.SteamID32, t.MapCourseID, t.Mode, t.Style, categories.Category, COUNT(*), MIN(t.RunTime), MAX(t.Created)
FROM ValidTimes t JOIN (SELECT 0 AS Category UNION ALL SELECT 1) categories ON categories.Category = 0 OR t.Teleports = 0
WHERE t.RunTime > 0 GROUP BY DATE(TIMESTAMPADD(SECOND, UNIX_TIMESTAMP(t.Created), '1970-01-01 00:00:00')), t.SteamID32, t.MapCourseID, t.Mode, t.Style, categories.Category
ON DUPLICATE KEY UPDATE RunCount = VALUES(RunCount), BestRunTime = VALUES(BestRunTime), LastCreated = VALUES(LastCreated);
