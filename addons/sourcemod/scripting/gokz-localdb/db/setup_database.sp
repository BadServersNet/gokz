/*
	Set up the connection to the local database.
*/



void DB_SetupDatabase()
{
	char error[255];
	gH_DB = SQL_Connect("gokz", true, error, sizeof(error));
	if (gH_DB == null)
	{
		SetFailState("Database connection failed. Error: \"%s\".", error);
	}

	char databaseType[8];
	SQL_ReadDriver(gH_DB, databaseType, sizeof(databaseType));
	if (strcmp(databaseType, "sqlite", false) == 0)
	{
		g_DBType = DatabaseType_SQLite;
	}
	else if (strcmp(databaseType, "mysql", false) == 0)
	{
		g_DBType = DatabaseType_MySQL;
	}
	else
	{
		SetFailState("Incompatible database driver. Use SQLite or MySQL.");
	}

	if (g_DBType == DatabaseType_MySQL)
	{
		if (!SQL_FastQuery(gH_DB, "SET time_zone='+00:00'"))
		{
			SetFailState("Unable to set GOKZ database timezone to UTC");
		}
		DBResultSet schema = SQL_Query(gH_DB, "SELECT COUNT(*) FROM GokzSchemaMigrations WHERE Version='003_read_projections'");
		if (schema == null)
		{
			SetFailState("Apply GOKZ database/migrate.py before loading this plugin");
		}
		SQL_FetchRow(schema);
		int migrations = SQL_FetchInt(schema, 0);
		delete schema;
		if (migrations != 1)
		{
			SetFailState("GOKZ database migration 003_read_projections is required");
		}
		Call_OnDatabaseConnect();
		return;
	}
	DB_CreateTables();
} 