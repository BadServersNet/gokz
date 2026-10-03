CREATE TABLE IF NOT EXISTS InvalidTimes (
    TimeID INT UNSIGNED PRIMARY KEY,
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_InvalidTimes_TimeID FOREIGN KEY (TimeID) REFERENCES Times (TimeID)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS InvalidJumps (
    JumpID INT UNSIGNED PRIMARY KEY,
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_InvalidJumps_JumpID FOREIGN KEY (JumpID) REFERENCES Jumpstats (JumpID)
) ENGINE=InnoDB;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW ValidTimes AS
SELECT t.* FROM Times t LEFT JOIN InvalidTimes i ON i.TimeID = t.TimeID WHERE i.TimeID IS NULL;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW ValidJumpstats AS
SELECT j.* FROM Jumpstats j LEFT JOIN InvalidJumps i ON i.JumpID = j.JumpID WHERE i.JumpID IS NULL;

ALTER TABLE Times
    DROP FOREIGN KEY IF EXISTS FK_Times_SteamID32,
    DROP FOREIGN KEY IF EXISTS FK_Times_MapCourseID,
    ADD CONSTRAINT FK_Times_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players (SteamID32),
    ADD CONSTRAINT FK_Times_MapCourseID FOREIGN KEY (MapCourseID) REFERENCES MapCourses (MapCourseID),
    ADD INDEX IF NOT EXISTS IX_Times_PlayerCreated (SteamID32, Created, TimeID),
    ADD INDEX IF NOT EXISTS IX_Times_Created (Created, TimeID),
    ADD INDEX IF NOT EXISTS IX_Times_PlayerBoard (SteamID32, MapCourseID, Mode, Style, RunTime, Created, TimeID),
    ADD INDEX IF NOT EXISTS IX_Times_BoardTime (MapCourseID, Mode, Style, RunTime, SteamID32);

ALTER TABLE Jumpstats
    DROP FOREIGN KEY IF EXISTS FK_Jumpstats_SteamID32,
    ADD CONSTRAINT FK_Jumpstats_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players (SteamID32),
    ADD INDEX IF NOT EXISTS IX_Jumpstats_PlayerBest (SteamID32, Mode, JumpType, IsBlockJump, Block, Distance, Created, JumpID),
    ADD INDEX IF NOT EXISTS IX_Jumpstats_BoardBest (IsBlockJump, Mode, JumpType, Block, Distance, Created, JumpID),
    ADD INDEX IF NOT EXISTS IX_Jumpstats_Created (Created, JumpID);

ALTER TABLE Replays
    DROP FOREIGN KEY IF EXISTS FK_Replays_TimeID,
    DROP FOREIGN KEY IF EXISTS FK_Replays_JumpID,
    ADD CONSTRAINT FK_Replays_TimeID FOREIGN KEY (TimeID) REFERENCES Times (TimeID),
    ADD CONSTRAINT FK_Replays_JumpID FOREIGN KEY (JumpID) REFERENCES Jumpstats (JumpID),
    ADD INDEX IF NOT EXISTS IX_Replays_TimeStore (TimeID, ReplayType, InStore, ReplayID),
    ADD INDEX IF NOT EXISTS IX_Replays_JumpStore (JumpID, ReplayType, InStore, ReplayID),
    DROP INDEX IF EXISTS IX_Replays_TimeID,
    DROP INDEX IF EXISTS IX_Replays_JumpID;

ALTER TABLE Maps ADD COLUMN IF NOT EXISTS InRankedPool TINYINT NOT NULL DEFAULT 0;

ALTER TABLE Players ADD INDEX IF NOT EXISTS IX_Players_Cheater (Cheater, SteamID32);

CREATE TABLE IF NOT EXISTS GokzStatsState (
    ID TINYINT UNSIGNED PRIMARY KEY,
    EligibilityRevision BIGINT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB;

INSERT IGNORE INTO GokzStatsState (ID) VALUES (1);

DELIMITER //
CREATE OR REPLACE TRIGGER Times_KeepHistory BEFORE DELETE ON Times FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Runs are permanent; insert an InvalidTimes record';
END//
CREATE OR REPLACE TRIGGER Times_KeepMeasurements BEFORE UPDATE ON Times FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Run measurements are immutable';
END//
CREATE OR REPLACE TRIGGER Jumpstats_KeepHistory BEFORE DELETE ON Jumpstats FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Jumps are permanent; insert an InvalidJumps record';
END//
CREATE OR REPLACE TRIGGER Jumpstats_KeepMeasurements BEFORE UPDATE ON Jumpstats FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Jump measurements are immutable';
END//
CREATE OR REPLACE TRIGGER InvalidTimes_KeepUpdate BEFORE UPDATE ON InvalidTimes FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Record exclusions are permanent';
END//
CREATE OR REPLACE TRIGGER InvalidTimes_KeepDelete BEFORE DELETE ON InvalidTimes FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Record exclusions are permanent';
END//
CREATE OR REPLACE TRIGGER InvalidJumps_KeepUpdate BEFORE UPDATE ON InvalidJumps FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Record exclusions are permanent';
END//
CREATE OR REPLACE TRIGGER InvalidJumps_KeepDelete BEFORE DELETE ON InvalidJumps FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Record exclusions are permanent';
END//
CREATE OR REPLACE TRIGGER Players_Eligibility AFTER UPDATE ON Players FOR EACH ROW
BEGIN
    IF OLD.Cheater <> NEW.Cheater THEN
        UPDATE GokzStatsState SET EligibilityRevision = EligibilityRevision + 1 WHERE ID = 1;
    END IF;
END//
CREATE OR REPLACE TRIGGER InvalidTimes_Eligibility AFTER INSERT ON InvalidTimes FOR EACH ROW
BEGIN
    UPDATE GokzStatsState SET EligibilityRevision = EligibilityRevision + 1 WHERE ID = 1;
END//
CREATE OR REPLACE TRIGGER InvalidJumps_Eligibility AFTER INSERT ON InvalidJumps FOR EACH ROW
BEGIN
    UPDATE GokzStatsState SET EligibilityRevision = EligibilityRevision + 1 WHERE ID = 1;
END//
DELIMITER ;
