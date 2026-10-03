# Permanent GOKZ history and website projections

MariaDB owns the game database schema. Nest uses a dedicated SELECT-only connection and a mapped Prisma schema; its PostgreSQL migration command must never run against GOKZ. These migrations use MariaDB SQL, including `CREATE OR REPLACE` triggers and `ADD INDEX IF NOT EXISTS`; they do not target Oracle MySQL. Validation used MariaDB 12.3.2.

## Retained data

`Times` and `Jumpstats` keep their existing IDs and original measurements. Deletes and updates are rejected by triggers, and restrictive foreign keys prevent player/course deletion from cascading into history. Every valid jump meeting the existing distance/offset rules is inserted, including non-PBs; the old 100-improvement ceiling and row reuse are removed. A block jump still has a normal-distance entry and a separate block-category entry. Runs are already inserted on completion. Jump replay recording remains tied to PBs; run replay recording remains tied to every completion. Existing replay references are retained when a new PB arrives.

The legacy `delete*` moderation commands insert into `InvalidTimes` or `InvalidJumps`. Those exclusions are permanent and `ValidTimes`/`ValidJumpstats` omit them from competitive reads. Flagged cheaters remain stored. Nest can show a flagged player's own eligible history while excluding that player from public boards. Raw archived records and replay objects are never pruned by this change. Previously overwritten or deleted records cannot be reconstructed.

## Read projections

- `PersonalBests`: one best per player/course/mode/style/category, with category 0 for overall and 1 for pro. Ordering is runtime, original completion timestamp, then numeric TimeID. Equal runtimes still share their leaderboard rank.
- `JumpPersonalBests`: one best per player/mode/jump type/block category, ordered by block size, distance, original timestamp, then JumpID.
- `DailyRunActivity`: exact counts, fastest runtime, and last completion for each UTC day/player/course/mode/style/category.
- `GokzStatsState`: a monotonic eligibility revision advanced transactionally when a cheater flag changes or a record is excluded. Nest reads one row to isolate cached data from older eligibility rules.

Insert triggers lock the owning player row before inserting raw records or exclusions, then update projections in that same transaction. This serializes concurrent projection updates for one player without serializing unrelated players. Exclusions recompute the affected bests and UTC daily totals. The game locks the player before its PB lookup or moderation selection. External importers/moderation writers should acquire that player lock before reading candidates, and retry the entire transaction on a deadlock or MariaDB `Record has changed since last read` error. A stale repeatable-read transaction aborts rather than committing inconsistent projections. These tables are derived and may be rebuilt from retained history; they are never an independent source of measurements. Cheater flags are applied at read time so changing a flag does not require rebuilding history.

Nest uses numeric SteamID32 predicates for indexed history and identity pagination, ranks lifetime PB rows, and aggregates whole past UTC days from the daily projection. Partial current days and rolling-window boundary days use raw records, preserving exact periods and distinct-player counts. Period PBs come from that period's eligible history. A future-dated imported best falls back to eligible historical records until its timestamp is reached.

## Applying migrations

1. Back up the database and replay bucket. Check the backup can be restored. Record raw row counts and IDs before the upgrade.
2. Stop every game server and importer writing to this shared database and put GOKZ website reads into maintenance. Keep writers stopped throughout the migration/backfill. Old jump writers attempt updates that the new retention triggers reject.
3. Use Python 3 and a MariaDB command-line client with an administrator's private option file. Run from the GOKZ checkout:

   ```sh
   python3 database/migrate.py gokz --defaults-extra-file /secure/path/gokz-admin.cnf
   ```

   The client file supplies host, port, user, and password. Keep it outside repositories and restrict its permissions. The database must already exist and existing history tables must use InnoDB. Review all SQL before running it. `001_baseline` adopts existing standard GOKZ tables with `CREATE TABLE IF NOT EXISTS`; `002_permanent_history` protects history and adds indexes/views; `003_read_projections` creates triggers and backfills the website projections. No raw records are removed or modified.

4. Verify raw counts/IDs are unchanged, stored bests match eligible-history ordering, daily category counts match history, and the migration table contains all three checksums. A second runner invocation makes no changes. DDL commits independently; on failure keep maintenance in place, inspect the reported SQL error, and repair/retry. Do not reset the database or edit an already recorded migration.
5. Grant the website account SELECT on `Players`, `Maps`, `MapCourses`, `Times`, `Jumpstats`, `InvalidTimes`, `InvalidJumps`, `ValidTimes`, `ValidJumpstats`, `PersonalBests`, `JumpPersonalBests`, `DailyRunActivity`, and `GokzStatsState`; add SELECT on `Replays` for downloads. Views use invoker security, so underlying grants are required. Nest rejects writable reader accounts.
6. Install the updated GOKZ plugins, then deploy the updated Nest backend and regenerate its GOKZ Prisma client with `pnpm db:generate:kz`. Warm both scheduled analytics categories, validate reads using the dedicated reader account, and restart writers. The new localdb plugin requires migration 003 before it loads.

Use a separate migration administrator. Game accounts need normal record INSERTs, mutable player/map/position/replay operations, and exclusion INSERTs; deny DELETE/UPDATE on raw history and deny DROP/ALTER/TRUNCATE privileges where practical. The migrations also initialize the ranked-pool column, and MariaDB plugin startup no longer requires schema-creation privileges. Triggers are not protection against a database administrator dropping a table or disabling constraints. Retain backups and budget for indefinite table/index and replay-object growth.

SQLite servers receive retention tables, views, indexes, and protection triggers automatically on startup. Website projections target the shared MariaDB deployment.

The updater uploads release artifacts only; it does not apply these external database migrations. Complete the shared-database maintenance before releasing/updating plugins. Do not run the legacy filtered `sm-gokz-migrate` workflow against an existing history database: it now requires an empty output and its untouched input database must remain archived.

## Local validation

Nest passed `pnpm check-all` and `pnpm build`. The three affected GOKZ plugins and the guarded legacy importer compiled with SourceMod 1.12. Existing vendored include warnings remain. No repository tests were added. CI applies the migration sequence twice against a fresh MariaDB service.

An isolated MariaDB upgrade retained all 120,000 synthetic runs and 150 jumps, preserving ID/runtime/distance checksums. Validation covered fresh installation, legacy-table adoption, repeat migration, raw mutation/cascade rejection, exclusions selecting the next best, category counts, UTC totals from non-UTC writers, simultaneous writes/exclusions, flagged-player reads, future-dated imports, numeric pagination, and SQLite startup/retention. Optimized results matched direct eligible-history queries across both categories, all rolling periods, monthly periods, and dimension filters.

One local full analytics comparison on that synthetic history measured:

| Category | Direct history | Projections |
| --- | ---: | ---: |
| Overall | 3,212 ms | 618 ms |
| Pro | 1,913 ms | 283 ms |

These are isolated sample timings, not a production latency guarantee. Query plans use the player's composite index for history, PB rows for lifetime boards, and the category/created index before touching future-best fallback history.

### Complexity report

Oxlint measured the functions that initially exceeded the repository limit while implementing the query builders:

| Function | Before helper extraction | After |
| --- | ---: | ---: |
| gokzRunSource | 11 | 6 |
| gokzActivitySource | 13 | 9 |
| runs | 11 | 7 |

Max depth for these functions: 1 -> 1. Extracted: runConditions, runTable, activityWindow, activityBoundaries, runSelection. Behavior verified through the history/projection comparisons and repository checks above.
