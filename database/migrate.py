import argparse
import hashlib
from pathlib import Path
import subprocess


def run_client(arguments, sql):
    result = subprocess.run(arguments, input=sql, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def migrate(arguments):
    run_client(arguments, "CREATE TABLE IF NOT EXISTS GokzSchemaMigrations (Version VARCHAR(64) PRIMARY KEY, Checksum CHAR(64) NOT NULL, Applied TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;")
    applied = run_client(arguments, "SELECT Version, Checksum FROM GokzSchemaMigrations ORDER BY Version;")
    versions = dict(line.split("\t") for line in applied.splitlines())
    directory = Path(__file__).resolve().parent / "migrations"
    for path in sorted(directory.glob("*.sql")):
        sql = path.read_text()
        checksum = hashlib.sha256(sql.encode()).hexdigest()
        version = path.stem
        if version in versions:
            if versions[version] != checksum:
                raise ValueError(f"Applied migration changed: {version}")
            continue
        guard = f"""SET time_zone = '+00:00';
DELIMITER //
BEGIN NOT ATOMIC
    IF GET_LOCK(CONCAT('gokz:', LEFT(SHA2(DATABASE(), 256), 32)), 30) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'GOKZ migration lock unavailable';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE()
        AND table_name IN ('Players', 'Maps', 'MapCourses', 'Times', 'Jumpstats', 'Replays') AND engine <> 'InnoDB') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'GOKZ history tables must use InnoDB';
    END IF;
    IF EXISTS (SELECT 1 FROM GokzSchemaMigrations WHERE Version = '{version}') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Concurrent GOKZ migration completed; rerun';
    END IF;
END//
DELIMITER ;
"""
        finish = f"\nINSERT INTO GokzSchemaMigrations (Version, Checksum) VALUES ('{version}', '{checksum}');\nDO RELEASE_LOCK(CONCAT('gokz:', LEFT(SHA2(DATABASE(), 256), 32)));\n"
        run_client(arguments, guard + sql + finish)
        print(f"Applied {version}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("database")
    parser.add_argument("--defaults-extra-file", type=Path)
    parser.add_argument("--client", default="mariadb")
    options = parser.parse_args()
    arguments = [options.client]
    if options.defaults_extra_file:
        arguments.append(f"--defaults-extra-file={options.defaults_extra_file.resolve()}")
    arguments.extend(["--batch", "--skip-column-names", "--database", options.database])
    migrate(arguments)


if __name__ == "__main__":
    main()
