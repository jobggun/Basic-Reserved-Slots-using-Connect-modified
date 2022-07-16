stock void LogBRSCDebugMessage(const char[] message, any ...)
{
    #if defined _DEBUG

    int size = strlen(message) + 255;
    char[] fMessage = new char[size];
    VFormat(fMessage, size, message, 2);
    
    char fileName[PLATFORM_MAX_PATH];
    char timeStamp[64];
    FormatTime(timeStamp, sizeof(timeStamp), "%Y%m%d", GetTime());
    BuildPath(Path_SM, fileName, sizeof(fileName), "logs/BRSC_DEBUG_%s.log", timeStamp);
    
    LogToFile(fileName, fMessage);

    #endif
}

stock void LogBRSCMessage(const char[] message, any ...)
{
    int size = strlen(message) + 255;
    char[] fMessage = new char[size];
    VFormat(fMessage, size, message, 2);
    
    char fileName[PLATFORM_MAX_PATH];
    char timeStamp[64];
    FormatTime(timeStamp, sizeof(timeStamp), "%Y%m%d", GetTime());
    BuildPath(Path_SM, fileName, sizeof(fileName), "logs/BRSC_%s.log", timeStamp);
    
    LogToFile(fileName, fMessage);
}