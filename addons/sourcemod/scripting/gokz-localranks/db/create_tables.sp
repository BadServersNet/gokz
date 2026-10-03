/*
	Table creation and alteration.
*/



void DB_CreateTables()
{
	if (g_DBType != DatabaseType_SQLite)
	{
		return;
	}

	Transaction txn = SQL_CreateTransaction();

	// Create/alter database tables
	switch (g_DBType)
	{
		case DatabaseType_SQLite:
		{
			txn.AddQuery(sqlite_maps_alter1);
		}

	}

	// No error logs for this transaction as it will always throw an error
	// if the column already exists, which is more annoying than helpful.
	SQL_ExecuteTransaction(gH_DB, txn, _, _, _, DBPrio_High);
} 