/*
	Table creation.
*/



void DB_CreateTables()
{
	Transaction txn = SQL_CreateTransaction();

	switch (g_DBType)
	{
		case DatabaseType_SQLite:
		{
			txn.AddQuery(sqlite_replays_create);
			txn.AddQuery(sqlite_replays_index_timeid);
			txn.AddQuery(sqlite_replays_index_jumpid);
			txn.AddQuery(sqlite_replays_index_steamid);
		}
		case DatabaseType_MySQL:
		{
			txn.AddQuery(mysql_replays_create);
		}
	}

	SQL_ExecuteTransaction(gH_DB, txn, _, DB_TxnFailure_Generic, _, DBPrio_High);
}
