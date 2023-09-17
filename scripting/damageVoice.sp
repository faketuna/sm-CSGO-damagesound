#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <sdktools_sound>
#include <clientprefs>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.0.1"

#define SOUND_FLAG_DOWNLOAD		(1 << 0)

#define SOUND_VOLUME_MAX 100
#define SOUND_VOLUME_MIN 0

#define CHARA_NAME_MAX_SIZE 64

enum {
    SND_TYPE_DAMAGE = 0,
    SND_TYPE_DEATH = 1
}

ConVar g_cDamageVoiceEnabled;
ConVar g_cDamageVoiceInterval;
ConVar g_cDamageVoiceVolume;

// Plugin cvar related.
bool g_bPluginEnabled;
float g_fSoundInterval;
float g_fSoundVolume;

// Plugin logic related.
float g_fLastDamageSound[MAXPLAYERS+1];

// Internal
Handle g_hModelPath;
Handle g_hDamageSoundPaths;
Handle g_hDeathSoundPaths;
Handle g_hFlags;
Handle g_hIsDamageSoundsPreCachedArray;
Handle g_hIsDeathSoundsPreCachedArray;


public Plugin myinfo = 
{
    name = "Damage voice",
    author = "faketuna",
    description = "Plays sound when player take damage",
    version = PLUGIN_VERSION,
    url = "https://short.f2a.dev/s/github"
};

public void OnPluginStart()
{
    g_cDamageVoiceEnabled            = CreateConVar("sm_dv_enable", "1", "Toggles damage voice globaly", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cDamageVoiceInterval        = CreateConVar("sm_dv_interval", "2.0", "Time between each sound to trigger per player. 0.0 to disable", FCVAR_NONE, true, 0.0, true, 30.0);
    g_cDamageVoiceVolume        = CreateConVar("sm_dv_volume", "1.0", "Global damage sound volume. If set to 1.0 you should be normalize sound file volume amplitude to -8.0db", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cDamageVoiceEnabled.AddChangeHook(OnCvarsChanged);
    g_cDamageVoiceInterval.AddChangeHook(OnCvarsChanged);
    g_cDamageVoiceVolume.AddChangeHook(OnCvarsChanged);

    HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);

    ParseConfig();
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
    //PrecacheSounds(); //TODO() Remove and replace to dynamic precache
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
}

public void SyncConVarValues() {
    g_bPluginEnabled        = GetConVarBool(g_cDamageVoiceEnabled);
    g_fSoundInterval        = GetConVarFloat(g_cDamageVoiceInterval);
    g_fSoundVolume          = GetConVarFloat(g_cDamageVoiceVolume);
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
        float pos[3];
        GetClientAbsOrigin(client, pos);
        EmitAmbientSound(
            soundFile,
            pos,
            client,
            SNDLEVEL_NORMAL,
            SND_NOFLAGS,
            g_fSoundVolume,
            SNDPITCH_NORMAL,
            0.0
        );
    } else {
        int idx = GetRandomInt(0, size-1);
        if(!TryPrecache(soundPath, soundIndex, idx, soundType)) {
            return;
        }
        GetArrayString(soundPath, idx, soundFile, sizeof(soundFile));
        float pos[3];
        GetClientAbsOrigin(client, pos);
        EmitAmbientSound(
            soundFile,
            pos,
            client,
            SNDLEVEL_NORMAL,
            SND_NOFLAGS,
            g_fSoundVolume,
            SNDPITCH_NORMAL,
            0.0
        );
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

void PrecacheSounds() {
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
                Format(buff, sizeof(buff), "sound/%s", soundFile);
                AddFileToDownloadsTable(buff);
            }
            Format(soundFile, sizeof(soundFile), "%s", soundFile);
            AddToStringTable(FindStringTable("soundprecache"), soundFile);
        }

        for(int j = GetArraySize(deathSoundPath)-1; j >= 0; j--) {
            GetArrayString(deathSoundPath, j, soundFile, sizeof(soundFile));

            if(flags & SOUND_FLAG_DOWNLOAD) {
                Format(buff, sizeof(buff), "sound/%s", soundFile);
                AddFileToDownloadsTable(buff);
            }
            Format(soundFile, sizeof(soundFile), "%s", soundFile);
            AddToStringTable(FindStringTable("soundprecache"), soundFile);
        }
    }
}