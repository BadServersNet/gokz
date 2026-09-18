/*
	Reads the general header of a replay file without loading the tick data,
	and copies replay files into the cache.
*/



// =====[ PUBLIC ]=====

bool ReadReplayFileInfo(const char[] path, int &replayType, int &steamID, char[] mapName, int mapNameLength)
{
	File file = OpenFile(path, "rb");
	if (file == null)
	{
		return false;
	}

	int magicNumber;
	file.ReadInt32(magicNumber);
	int formatVersion;
	file.ReadInt8(formatVersion);
	if (magicNumber != RP_MAGIC_NUMBER)
	{
		delete file;
		return false;
	}

	if (formatVersion == 1)
	{
		ReadFormatVersion1Info(file, replayType, steamID, mapName, mapNameLength);
		delete file;
		return true;
	}
	if (formatVersion != RP_FORMAT_VERSION)
	{
		delete file;
		return false;
	}

	file.ReadInt8(replayType);
	SkipLengthPrefixedString(file);
	ReadLengthPrefixedString(file, mapName, mapNameLength);
	file.Seek(12, SEEK_CUR);
	SkipLengthPrefixedString(file);
	file.ReadInt32(steamID);
	delete file;
	return true;
}

static int g_CopyBuffer[RP_COPY_CHUNK_CELLS];

static bool CopyCells(File source, File destination, int cells)
{
	int remaining = cells;
	while (remaining > 0)
	{
		int chunk = remaining < sizeof(g_CopyBuffer) ? remaining : sizeof(g_CopyBuffer);
		int read = source.Read(g_CopyBuffer, chunk, 4);
		if (read != chunk)
		{
			LogError("Replay copy read %d of %d cells (%d cells left).", read, chunk, remaining);
			return false;
		}
		if (!destination.Write(g_CopyBuffer, read, 4))
		{
			LogError("Replay copy failed to write %d cells.", read);
			return false;
		}
		remaining -= read;
	}
	return true;
}

static bool CopyTailBytes(File source, File destination, int bytes)
{
	for (int i = 0; i < bytes; i++)
	{
		int value;
		if (!source.ReadInt8(value))
		{
			LogError("Replay copy failed to read tail byte %d of %d.", i + 1, bytes);
			return false;
		}
		if (!destination.WriteInt8(value))
		{
			LogError("Replay copy failed to write tail byte %d of %d.", i + 1, bytes);
			return false;
		}
	}
	return true;
}

bool CopyReplayFile(const char[] sourcePath, const char[] destinationPath)
{
	int expected = FileSize(sourcePath);
	if (expected < 0)
	{
		LogError("Replay \"%s\" does not exist or is not a regular file.", sourcePath);
		return false;
	}

	File source = OpenFile(sourcePath, "rb");
	if (source == null)
	{
		LogError("Failed to open replay \"%s\" for copying.", sourcePath);
		return false;
	}
	File destination = OpenFile(destinationPath, "wb");
	if (destination == null)
	{
		LogError("Failed to create replay copy \"%s\".", destinationPath);
		delete source;
		return false;
	}

	bool copied = CopyCells(source, destination, expected / 4) && CopyTailBytes(source, destination, expected % 4);
	delete destination;
	delete source;
	if (!copied)
	{
		LogError("Replay copy \"%s\" from \"%s\" stopped early.", destinationPath, sourcePath);
		DeleteFile(destinationPath);
		return false;
	}

	int written = FileSize(destinationPath);
	if (written != expected)
	{
		LogError("Replay copy \"%s\" is %d bytes but the source is %d bytes.", destinationPath, written, expected);
		DeleteFile(destinationPath);
		return false;
	}
	return true;
}



// =====[ PRIVATE ]=====

static void ReadFormatVersion1Info(File file, int &replayType, int &steamID, char[] mapName, int mapNameLength)
{
	replayType = ReplayType_Run;
	SkipLengthPrefixedString(file);
	ReadLengthPrefixedString(file, mapName, mapNameLength);
	file.Seek(20, SEEK_CUR);
	file.ReadInt32(steamID);
}

void SkipLengthPrefixedString(File file)
{
	int length;
	file.ReadInt8(length);
	length &= 0xFF;
	file.Seek(length, SEEK_CUR);
}

static void ReadLengthPrefixedString(File file, char[] buffer, int maxlength)
{
	int length;
	file.ReadInt8(length);
	length &= 0xFF;
	if (length >= maxlength)
	{
		file.Seek(length, SEEK_CUR);
		buffer[0] = '\0';
		return;
	}
	file.ReadString(buffer, maxlength, length);
	buffer[length] = '\0';
}
