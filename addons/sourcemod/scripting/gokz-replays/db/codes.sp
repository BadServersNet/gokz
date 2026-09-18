/*
	Short unique replay codes.
*/



static const char codeAlphabet[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";



// =====[ PUBLIC ]=====

void GenerateReplayCode(char[] buffer, int maxlength)
{
	int alphabetLength = sizeof(codeAlphabet) - 1;
	int length = RP_CODE_LENGTH;
	if (length >= maxlength)
	{
		length = maxlength - 1;
	}
	for (int i = 0; i < length; i++)
	{
		int pick = GetURandomInt() % alphabetLength;
		buffer[i] = codeAlphabet[pick];
	}
	buffer[length] = '\0';
}

bool NormalizeReplayCode(const char[] input, char[] buffer, int maxlength)
{
	int length = strlen(input);
	if (length != RP_CODE_LENGTH || length >= maxlength)
	{
		return false;
	}
	strcopy(buffer, maxlength, input);
	for (int i = 0; i < length; i++)
	{
		buffer[i] = CharToUpper(buffer[i]);
		if (FindCharInString(codeAlphabet, buffer[i]) == -1)
		{
			return false;
		}
	}
	return true;
}
