#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <sdktools_sound>
#include <clientprefs>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.0.2"

#define SOUND_FLAG_DOWNLOAD		(1 << 0)

#define SOUND_VOLUME_MAX 100
#define SOUND_VOLUME_MIN 0

enum {
    SND_TYPE_DAMAGE = 0,
    SND_TYPE_DEATH = 1
}

ConVar g_cDamageVoiceEnabled;
ConVar g_cDamageVoiceInterval;

Handle g_hSoundToggleCookie;
Handle g_hSoundVolumeCookie;

// Plugin cvar related.
bool g_bPluginEnabled;
float g_fSoundInterval;

// Plugin logic related.
float g_fLastDamageSound[MAXPLAYERS+1];

// Internal
Handle g_hModelPath;
Handle g_hDamageSoundPaths;
Handle g_hDeathSoundPaths;
Handle g_hFlags;
Handle g_hIsDamageSoundsPreCachedArray;
Handle g_hIsDeathSoundsPreCachedArray;

// Client prefs (Player setting) related.
bool g_bPlayerSoundDisabled[MAXPLAYERS+1];
float g_fPlayerSoundVolume[MAXPLAYERS+1];


public Plugin myinfo = 
{
    name = "Damage voice",
    author = "faketuna",
    description = "Plays sound when player take damage.\nSpecial thanks for testing plugin >> kur4yam1, valni_nyas, omoi",
    version = PLUGIN_VERSION,
    url = "https://short.f2a.dev/s/github"
};

public void OnPluginStart()
{
    g_cDamageVoiceEnabled            = CreateConVar("sm_dv_enable", "1", "Toggles damage voice globaly", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cDamageVoiceInterval        = CreateConVar("sm_dv_interval", "4.0", "Time between each sound to trigger per player. 0.0 to disable", FCVAR_NONE, true, 0.0, true, 30.0);

    g_cDamageVoiceEnabled.AddChangeHook(OnCvarsChanged);
    g_cDamageVoiceInterval.AddChangeHook(OnCvarsChanged);

    g_hSoundVolumeCookie            = RegClientCookie("cookie_dv_volume", "Damage voice volume", CookieAccess_Protected);
    g_hSoundToggleCookie            = RegClientCookie("cookie_dv_toggle", "Damage voice toggle", CookieAccess_Protected);

    RegConsoleCmd("dv_volume", CommandDVVolume, "Set damage voice volume per player.");
    RegConsoleCmd("dv_toggle", CommandDVToggle, "Toggle damage voice per player.");
    RegConsoleCmd("dv_menu", CommandDVMenu, "Open settings menu");
    RegConsoleCmd("dvmenu", CommandDVMenu, "Open settings menu");
    RegConsoleCmd("dvm", CommandDVMenu, "Open settings menu");

    HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);

    ParseConfig();

    LoadTranslations("common.phrases");
    LoadTranslations("damagevoice.phrases");

    SetCookieMenuItem(SoundSettingsMenu, 0 ,"Damage voice");
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientConnected(i)) {
            if(AreClientCookiesCached(i)) {
                OnClientCookiesCached(i);
            }
        }
    }
}

public void OnClientCookiesCached(int client) {
    if (IsFakeClient(client)) {
        return;
    }

    char cookieValue[128];
    GetClientCookie(client, g_hSoundVolumeCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_fPlayerSoundVolume[client] = StringToFloat(cookieValue);
    } else {
        g_fPlayerSoundVolume[client] = 1.0;
        SetClientCookie(client, g_hSoundVolumeCookie, "1.0");
    }

    GetClientCookie(client, g_hSoundToggleCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_bPlayerSoundDisabled[client] = view_as<bool>(StringToInt(cookieValue));
    } else {
        g_bPlayerSoundDisabled[client] = false;
        SetClientCookie(client, g_hSoundToggleCookie, "0");
    }
}


public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!g_bPluginEnabled) {
        return Plugin_Continue;
    }
    if(IsFakeClient(client)) {
        return Plugin_Continue;
    }
    if(client != 0 && attacker != 0) {
        if(GetClientTeam(client) == GetClientTeam(attacker)) {
            return Plugin_Continue;
        }
    }

    float ft = GetGameTime() - g_fLastDamageSound[client];
    if (ft <= g_fSoundInterval && g_fSoundInterval != 0.0) {
        return Plugin_Continue;
    }

    char buff[PLATFORM_MAX_PATH];
    GetClientModel(client, buff, sizeof(buff));
    int i = GetSoundIndex(buff);
    if(i == -1) {
        return Plugin_Continue;
    }
    PlaySound(i, client, SND_TYPE_DAMAGE);
    return Plugin_Continue;
}

public void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast) {
    if (!g_bPluginEnabled) {
        return;
    }

    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if(IsFakeClient(client)) {
        return;
    }

    char buff[PLATFORM_MAX_PATH];
    GetClientModel(client, buff, sizeof(buff));
    int i = GetSoundIndex(buff);
    if(i == -1) {
        return;
    }
    PlaySound(i, client, SND_TYPE_DEATH);
    return;
}

public void OnConfigsExecuted() {
    SyncConVarValues();
}

public void OnMapStart() {
    Handle check;
    for(int i = GetArraySize(g_hIsDamageSoundsPreCachedArray)-1; i >= 0; i--) {
        check = GetArrayCell(g_hIsDamageSoundsPreCachedArray, i);
        for(int j = GetArraySize(check)-1; j >= 0; j--) {
            SetArrayCell(check, j, false);
        }
    }
    for(int i = GetArraySize(g_hIsDeathSoundsPreCachedArray)-1; i >= 0; i--) {
        check = GetArrayCell(g_hIsDeathSoundsPreCachedArray, i);
        for(int j = GetArraySize(check)-1; j >= 0; j--) {
            SetArrayCell(check, j, false);
        }
    }
    for(int i = 1; i <= MaxClients; i++) {
        g_fLastDamageSound[i] = 0.0;
    }
    AddDownloadAll();
}

public void SyncConVarValues() {
    g_bPluginEnabled        = GetConVarBool(g_cDamageVoiceEnabled);
    g_fSoundInterval        = GetConVarFloat(g_cDamageVoiceInterval);
}

public void OnCvarsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    SyncConVarValues();
}

int GetSoundIndex(const char[] modelName) {
    char mdPath[PLATFORM_MAX_PATH];
    for(int i = GetArraySize(g_hModelPath)-1; i >= 0; i--) {
        GetArrayString(g_hModelPath, i, mdPath, sizeof(mdPath));
        if(StrEqual(mdPath, modelName, false)) {
            return i;
        }
    }
    return -1;
}

bool TryPrecache(Handle soundPaths, int modelIndex, int index, int soundType) {
    Handle checkPrecached;
    char soundFile[PLATFORM_MAX_PATH];
    GetArrayString(soundPaths, index, soundFile, sizeof(soundFile));

    if(soundType == SND_TYPE_DAMAGE) {
        checkPrecached = GetArrayCell(g_hIsDamageSoundsPreCachedArray, modelIndex);
        if(GetArrayCell(checkPrecached, index)) {
            return true;
        }

        AddToStringTable(FindStringTable("soundprecache"), soundFile);
        SetArrayCell(checkPrecached, index, true);
        return GetArrayCell(checkPrecached, index);
    }
    if(soundType == SND_TYPE_DEATH) {
        checkPrecached = GetArrayCell(g_hIsDeathSoundsPreCachedArray, modelIndex);
        if(GetArrayCell(checkPrecached, index)) {
            return true;
        }

        AddToStringTable(FindStringTable("soundprecache"), soundFile);
        SetArrayCell(checkPrecached, index, true);
        return GetArrayCell(checkPrecached, index);
    }
    return false;
}

void PlaySound(int soundIndex, int client, int soundType) {
    char soundFile[PLATFORM_MAX_PATH];
    Handle soundPath;

    
    if(soundType == SND_TYPE_DAMAGE) {
        g_fLastDamageSound[client] = GetGameTime();
        soundPath = GetArrayCell(g_hDamageSoundPaths ,soundIndex);
    }
    if(soundType == SND_TYPE_DEATH) {
        soundPath = GetArrayCell(g_hDeathSoundPaths ,soundIndex);
    }
    int size = GetArraySize(soundPath);
    if(size == 1) {
        if(!TryPrecache(soundPath, soundIndex, 0, soundType)) {
            return;
        }
        GetArrayString(soundPath, 0, soundFile, sizeof(soundFile));
        for(int i = 1; i <= MaxClients; i++) {
            if(!IsClientInGame(i) || IsFakeClient(i) && g_bPlayerSoundDisabled[i]) {
                continue;
            }
            EmitSoundToClient(
                i,
                soundFile,
                client,
                SNDCHAN_STATIC,
                SNDLEVEL_NORMAL,
                SND_NOFLAGS,
                g_fPlayerSoundVolume[i],
                SNDPITCH_NORMAL,
                0,
                NULL_VECTOR,
                NULL_VECTOR,
                true,
                0.0
            );
        }
    } else {
        int idx = GetRandomInt(0, size-1);
        if(!TryPrecache(soundPath, soundIndex, idx, soundType)) {
            return;
        }
        GetArrayString(soundPath, idx, soundFile, sizeof(soundFile));
        for(int i = 1; i <= MaxClients; i++) {
            if(!IsClientInGame(i) || IsFakeClient(i) || g_bPlayerSoundDisabled[i]) {
                continue;
            }
            EmitSoundToClient(
                i,
                soundFile,
                client,
                SNDCHAN_STATIC,
                SNDLEVEL_NORMAL,
                SND_NOFLAGS,
                g_fPlayerSoundVolume[i],
                SNDPITCH_NORMAL,
                0,
                NULL_VECTOR,
                NULL_VECTOR,
                true,
                0.0
            );
        }
    }
}

void ParseConfig() {
    g_hModelPath = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    g_hDamageSoundPaths = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    g_hDeathSoundPaths = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    g_hFlags      = CreateArray();
    g_hIsDamageSoundsPreCachedArray = CreateArray(ByteCountToCells(8));
    g_hIsDeathSoundsPreCachedArray = CreateArray(ByteCountToCells(8));

    char soundListFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM,soundListFile,sizeof(soundListFile),"configs/damagevoice.cfg");
    if(!FileExists(soundListFile)) {
        PrintToServer("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nFILE NOT FOUND");
        SetFailState("damagevoice.cfg failed to parse! Reason: File doesn't exist!");
    }
    Handle listFile = CreateKeyValues("infolist");
    FileToKeyValues(listFile, soundListFile);
    KvRewind(listFile);

    if(KvGotoFirstSubKey(listFile)) {
        char fileLocation[PLATFORM_MAX_PATH], item[8];
        Handle damageSoundPath;
        Handle deathSoundPath;
        Handle damagePrecached;
        Handle deathPrecached;
        do {
            KvGetString(listFile, "model", fileLocation, sizeof(fileLocation), "");
            if(fileLocation[0] != '\0') {
                PushArrayString(g_hModelPath, fileLocation);

                damageSoundPath = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
                deathSoundPath = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
                damagePrecached = CreateArray();
                deathPrecached = CreateArray();
                int flags = 0;

                if(KvGetNum(listFile, "download", 0)) {
                    flags |= SOUND_FLAG_DOWNLOAD;
                }

                PushArrayCell(g_hDamageSoundPaths, damageSoundPath);
                PushArrayCell(g_hDeathSoundPaths, deathSoundPath);
                PushArrayCell(g_hIsDamageSoundsPreCachedArray, damagePrecached);
                PushArrayCell(g_hIsDeathSoundsPreCachedArray, deathPrecached);
                PushArrayCell(g_hFlags, flags);

                KvGetString(listFile, "damage", fileLocation, sizeof(fileLocation), "");
                Format(fileLocation, sizeof(fileLocation), "*%s", fileLocation);
                PushArrayString(damageSoundPath, fileLocation);
                PushArrayCell(damagePrecached, false);

                for (int i = 2;; i++) {
                    FormatEx(item, sizeof(item), "damage%d", i);
                    KvGetString(listFile, item, fileLocation, sizeof(fileLocation), "");
                    if (fileLocation[0] == '\0') {
                        break;
                    }
                    Format(fileLocation, sizeof(fileLocation), "*%s", fileLocation);
                    PushArrayString(damageSoundPath, fileLocation);
                    PushArrayCell(damagePrecached, false);
                }

                KvGetString(listFile, "death", fileLocation, sizeof(fileLocation), "");
                Format(fileLocation, sizeof(fileLocation), "*%s", fileLocation);
                PushArrayString(deathSoundPath, fileLocation);
                PushArrayCell(deathPrecached, false);

                for (int i = 2;; i++) {
                    FormatEx(item, sizeof(item), "death%d", i);
                    KvGetString(listFile, item, fileLocation, sizeof(fileLocation), "");
                    if (fileLocation[0] == '\0') {
                        break;
                    }
                    Format(fileLocation, sizeof(fileLocation), "*%s", fileLocation);
                    PushArrayString(deathSoundPath, fileLocation);
                    PushArrayCell(deathPrecached, false);
                }
            }
        } while(KvGotoNextKey(listFile));
    } else {
        PrintToServer("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nSUBKEY NOT FOUND");
        SetFailState("damagevoice.cfg failed to parse! Reason: No subkeys found!");
    }
    CloseHandle(listFile);
}

void AddDownloadAll() {
    char soundFile[PLATFORM_MAX_PATH];
    char buff[PLATFORM_MAX_PATH];
    Handle damageSoundPath;
    Handle deathSoundPath;
    int flags;

    for(int i = GetArraySize(g_hDamageSoundPaths)-1; i >= 0; i--) {
        damageSoundPath = GetArrayCell(g_hDamageSoundPaths, i);
        deathSoundPath = GetArrayCell(g_hDeathSoundPaths, i);
        flags = GetArrayCell(g_hFlags, i);

        for(int j = GetArraySize(damageSoundPath)-1; j >= 0; j--) {
            GetArrayString(damageSoundPath, j, soundFile, sizeof(soundFile));
            if(flags & SOUND_FLAG_DOWNLOAD) {
                ReplaceString(soundFile, sizeof(soundFile), "*", "", false);
                Format(buff, sizeof(buff), "sound/%s", soundFile);
                AddFileToDownloadsTable(buff);
            }
        }

        for(int j = GetArraySize(deathSoundPath)-1; j >= 0; j--) {
            GetArrayString(deathSoundPath, j, soundFile, sizeof(soundFile));
            if(flags & SOUND_FLAG_DOWNLOAD) {
                ReplaceString(soundFile, sizeof(soundFile), "*", "", false);
                Format(buff, sizeof(buff), "sound/%s", soundFile);
                AddFileToDownloadsTable(buff);
            }
        }
    }
}

public Action CommandDVMenu(int client, int args) {
    DisplaySettingsMenu(client);
    return Plugin_Handled;
}

public Action CommandDVToggle(int client, int args) {
    g_bPlayerSoundDisabled[client] = !g_bPlayerSoundDisabled[client];
    CPrintToChat(client, "%t%t", "dv prefix", !g_bPlayerSoundDisabled[client] ? "dv cmd toggle enable" : "dv cmd toggle disable");
    SetClientCookie(client, g_hSoundToggleCookie, g_bPlayerSoundDisabled[client] ? "1" : "0");
    return Plugin_Handled;
}

public Action CommandDVVolume(int client, int args) {
    if(args >= 1) {
        char arg1[4];
        GetCmdArg(1, arg1, sizeof(arg1));
        if(!IsOnlyDicimal(arg1)) {
            CPrintToChat(client, "%t%t", "dv prefix", "dv cmd invalid arguments");
            return Plugin_Handled;
        }
        int arg = StringToInt(arg1);
        if(arg > SOUND_VOLUME_MAX || SOUND_VOLUME_MIN > arg) {
            CPrintToChat(client, "%t%t", "dv prefix", "dv cmd value out of range", arg, SOUND_VOLUME_MIN, SOUND_VOLUME_MAX);
            return Plugin_Handled;
        }

        g_fPlayerSoundVolume[client] = float(StringToInt(arg1)) / 100;
        char buff[6];
        FloatToString(g_fPlayerSoundVolume[client], buff, sizeof(buff));
        SetClientCookie(client, g_hSoundVolumeCookie, buff);
        CPrintToChat(client, "%t%t", "dv prefix", "dv cmd set volume", arg1);
        return Plugin_Handled;
    }

    DisplaySettingsMenu(client);
    return Plugin_Handled;
}

bool IsOnlyDicimal(char[] string) {
    for(int i = 0; i < strlen(string); i++) {
        if (!IsCharNumeric(string[i])) {
            return false;
        }
    }
    return true;
}

void DisplaySettingsMenu(int client)
{
    SetGlobalTransTarget(client);
    Menu prefmenu = CreateMenu(SoundSettingHandler, MENU_ACTIONS_DEFAULT);

    char menuTitle[64];
    Format(menuTitle, sizeof(menuTitle), "%t", "dv menu title");
    prefmenu.SetTitle(menuTitle);

    char soundDisabled[64], soundVolume[64];

    Format(soundDisabled, sizeof(soundDisabled), "%t%t","dv menu disable damage voice", g_bPlayerSoundDisabled[client] ? "Yes" : "No");
    prefmenu.AddItem("dv_pref_disable", soundDisabled);

    Format(soundVolume, sizeof(soundVolume), "%t%.0f%","dv menu volume", g_fPlayerSoundVolume[client] * 100);
    switch (RoundToZero((g_fPlayerSoundVolume[client]*100)))
    {
        case 10: { prefmenu.AddItem("dv_pref_volume_100", soundVolume);}
        case 20: { prefmenu.AddItem("dv_pref_volume_10", soundVolume);}
        case 30: { prefmenu.AddItem("dv_pref_volume_20", soundVolume);}
        case 40: { prefmenu.AddItem("dv_pref_volume_30", soundVolume);}
        case 50: { prefmenu.AddItem("dv_pref_volume_40", soundVolume);}
        case 60: { prefmenu.AddItem("dv_pref_volume_50", soundVolume);}
        case 70: { prefmenu.AddItem("dv_pref_volume_60", soundVolume);}
        case 80: { prefmenu.AddItem("dv_pref_volume_70", soundVolume);}
        case 90: { prefmenu.AddItem("dv_pref_volume_80", soundVolume);}
        case 100: { prefmenu.AddItem("dv_pref_volume_90", soundVolume);}
        default: { prefmenu.AddItem("dv_pref_volume_100", soundVolume);}
    }
    prefmenu.ExitBackButton = true;
    prefmenu.Display(client, MENU_TIME_FOREVER);
}

public int SoundSettingHandler(Menu prefmenu, MenuAction actions, int client, int item)
{
    SetGlobalTransTarget(client);
    if (actions == MenuAction_Select)
    {
        char preference[32];
        GetMenuItem(prefmenu, item, preference, sizeof(preference));
        if(StrEqual(preference, "dv_pref_disable"))
        {
            g_bPlayerSoundDisabled[client] = !g_bPlayerSoundDisabled[client];
            SetClientCookie(client, g_hSoundToggleCookie, g_bPlayerSoundDisabled[client] ? "1" : "0");
        }
        if(StrContains(preference, "dv_pref_volume_") >= 0)
        {
            ReplaceString(preference, sizeof(preference), "dv_pref_volume_", "");
            int val = StringToInt(preference);
            g_fPlayerSoundVolume[client] = float(val) / 100;
            char buff[6];
            FloatToString(g_fPlayerSoundVolume[client], buff, sizeof(buff));
            SetClientCookie(client, g_hSoundVolumeCookie, buff);
        }
        DisplaySettingsMenu(client);
    }
    else if (actions == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            ShowCookieMenu(client);
        }
    }
    else if (actions == MenuAction_End)
    {
        CloseHandle(prefmenu);
    }
    return 0;
}

public void SoundSettingsMenu(int client, CookieMenuAction actions, any info, char[] buffer, int maxlen)
{
    if (actions == CookieMenuAction_DisplayOption)
    {
        Format(buffer, maxlen, "Damage voice");
    }
    
    if (actions == CookieMenuAction_SelectOption)
    {
        DisplaySettingsMenu(client);
    }
}
