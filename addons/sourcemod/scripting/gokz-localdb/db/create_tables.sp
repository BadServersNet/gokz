/*
	Table creation and alteration.
*/



void DB_CreateTables()
{
	Transaction txn = SQL_CreateTransaction();
	
	switch (g_DBType)
	{
		case DatabaseType_SQLite:
		{
			txn.AddQuery(sqlite_players_create);
			txn.AddQuery(sqlite_maps_create);
			txn.AddQuery(sqlite_mapcourses_create);
			txn.AddQuery(sqlite_times_create);
			txn.AddQuery(sqlite_jumpstats_create);
			txn.AddQuery(sqlite_vbpos_create);
			txn.AddQuery(sqlite_startpos_create);
			txn.AddQuery("CREATE TABLE IF NOT EXISTS InvalidTimes (TimeID INTEGER PRIMARY KEY, Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (TimeID) REFERENCES Times(TimeID))");
			txn.AddQuery("CREATE TABLE IF NOT EXISTS InvalidJumps (JumpID INTEGER PRIMARY KEY, Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (JumpID) REFERENCES Jumpstats(JumpID))");
			txn.AddQuery("CREATE VIEW IF NOT EXISTS ValidTimes AS SELECT t.* FROM Times t LEFT JOIN InvalidTimes i ON i.TimeID=t.TimeID WHERE i.TimeID IS NULL");
			txn.AddQuery("CREATE VIEW IF NOT EXISTS ValidJumpstats AS SELECT j.* FROM Jumpstats j LEFT JOIN InvalidJumps i ON i.JumpID=j.JumpID WHERE i.JumpID IS NULL");
			txn.AddQuery("CREATE INDEX IF NOT EXISTS IX_Times_PlayerCreated ON Times (SteamID32, Created, TimeID)");
			txn.AddQuery("CREATE INDEX IF NOT EXISTS IX_Times_Created ON Times (Created, TimeID)");
			txn.AddQuery("CREATE INDEX IF NOT EXISTS IX_Times_PlayerBoard ON Times (SteamID32, MapCourseID, Mode, Style, RunTime, Created, TimeID)");
			txn.AddQuery("CREATE INDEX IF NOT EXISTS IX_Jumpstats_PlayerBest ON Jumpstats (SteamID32, Mode, JumpType, IsBlockJump, Block, Distance, Created, JumpID)");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS Times_KeepHistory BEFORE DELETE ON Times BEGIN SELECT RAISE(ABORT, 'Runs are permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS Times_KeepMeasurements BEFORE UPDATE ON Times BEGIN SELECT RAISE(ABORT, 'Run measurements are immutable'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS Jumpstats_KeepHistory BEFORE DELETE ON Jumpstats BEGIN SELECT RAISE(ABORT, 'Jumps are permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS Jumpstats_KeepMeasurements BEFORE UPDATE ON Jumpstats BEGIN SELECT RAISE(ABORT, 'Jump measurements are immutable'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS InvalidTimes_KeepUpdate BEFORE UPDATE ON InvalidTimes BEGIN SELECT RAISE(ABORT, 'Record exclusions are permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS InvalidTimes_KeepDelete BEFORE DELETE ON InvalidTimes BEGIN SELECT RAISE(ABORT, 'Record exclusions are permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS InvalidJumps_KeepUpdate BEFORE UPDATE ON InvalidJumps BEGIN SELECT RAISE(ABORT, 'Record exclusions are permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS InvalidJumps_KeepDelete BEFORE DELETE ON InvalidJumps BEGIN SELECT RAISE(ABORT, 'Record exclusions are permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS Players_KeepHistory BEFORE DELETE ON Players WHEN EXISTS (SELECT 1 FROM Times WHERE SteamID32=OLD.SteamID32) OR EXISTS (SELECT 1 FROM Jumpstats WHERE SteamID32=OLD.SteamID32) BEGIN SELECT RAISE(ABORT, 'Player history is permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS MapCourses_KeepHistory BEFORE DELETE ON MapCourses WHEN EXISTS (SELECT 1 FROM Times WHERE MapCourseID=OLD.MapCourseID) BEGIN SELECT RAISE(ABORT, 'Course history is permanent'); END");
			txn.AddQuery("CREATE TRIGGER IF NOT EXISTS Maps_KeepHistory BEFORE DELETE ON Maps WHEN EXISTS (SELECT 1 FROM Times t JOIN MapCourses c ON c.MapCourseID=t.MapCourseID WHERE c.MapID=OLD.MapID) BEGIN SELECT RAISE(ABORT, 'Map history is permanent'); END");
		}
		case DatabaseType_MySQL:
		{
			txn.AddQuery(mysql_players_create);
			txn.AddQuery(mysql_maps_create);
			txn.AddQuery(mysql_mapcourses_create);
			txn.AddQuery(mysql_times_create);
			txn.AddQuery(mysql_jumpstats_create);
			txn.AddQuery(mysql_vbpos_create);
			txn.AddQuery(mysql_startpos_create);
		}
	}
	
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_CreateTables, DB_TxnFailure_CreateTables, _, DBPrio_High);
}

public void DB_TxnSuccess_CreateTables(Handle db, int data, int numQueries, Handle[] results, any[] queryData)
{
	Call_OnDatabaseConnect();
}

public void DB_TxnFailure_CreateTables(Handle db, int data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	SetFailState("Database schema setup failed: %s", error);
}
