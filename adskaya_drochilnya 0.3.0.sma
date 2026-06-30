/*=====================================================
    ADSKAYA DROCHILNYA
    Version: 0.3.0 Foundation Update

    Second foundation iteration.
    Gameplay rules from v0.2.0/v0.3.0 are preserved, while systems are
    separated so future affixes, weapons, characters, bosses, and events
    can move into .inc files with minimal friction.
=====================================================*/

#include <amxmodx>
#include <amxmisc>
#include <reapi>

#define AD_PLUGIN_NAME                  "ADSKAYA DROCHILNYA"
#define AD_PLUGIN_VERSION               "0.3.0 Foundation Update"
#define AD_PLUGIN_AUTHOR                "Open Source"

#define AD_MAX_PLAYERS                  32

#define AD_MAX_SYSTEMS                  16
#define AD_SYSTEM_NAME_LENGTH           32
#define AD_SYSTEM_CALLBACK_LENGTH       48
#define AD_SYSTEM_UPDATE_INTERVAL       1.0

#define AD_HUD_CALLBACK_LENGTH          48

#define AD_MAX_AFFIXES                  64
#define AD_INVALID_AFFIX                -1
#define AD_AFFIX_NAME_LENGTH            32

enum _:AD_TierRule
{
    AD_TIER_XP_STEP = 100,
    AD_BUILD_POINTS_PER_TIER = 1
}

enum _:AD_HudType
{
    AD_HUD_MAIN,
    AD_HUD_DEBUG,
    AD_HUD_AFFIX,
    AD_HUD_DAMAGE,
    AD_HUD_COUNT
}

enum _:AD_HudChannel
{
    AD_HUD_CHANNEL_MAIN = -1,
    AD_HUD_CHANNEL_DEBUG = -1,
    AD_HUD_CHANNEL_AFFIX = -1,
    AD_HUD_CHANNEL_DAMAGE = -1
}

enum _:AD_Stat
{
    AD_STAT_DAMAGE,
    AD_STAT_RELOAD,
    AD_STAT_MAGAZINE,
    AD_STAT_MOVESPEED,
    AD_STAT_ACCURACY,
    AD_STAT_HEALTH,
    AD_STAT_COUNT
}

enum AD_PlayerData
{
    bool:AD_Player_Connected,
    bool:AD_Player_Alive,
    AD_Player_Kills,
    AD_Player_Deaths,
    AD_Player_Killstreak,
    AD_Player_XP,
    AD_Player_Tier,
    AD_Player_BuildPoints,
    bool:AD_Player_HudEnabled
}

new g_PlayerData[AD_MAX_PLAYERS + 1][AD_PlayerData];
new Float:g_PlayerStats[AD_MAX_PLAYERS + 1][AD_STAT_COUNT];

new g_SystemCount;
new bool:g_SystemRegistered[AD_MAX_SYSTEMS];
new g_SystemName[AD_MAX_SYSTEMS][AD_SYSTEM_NAME_LENGTH];
new g_SystemInitCallback[AD_MAX_SYSTEMS][AD_SYSTEM_CALLBACK_LENGTH];
new g_SystemShutdownCallback[AD_MAX_SYSTEMS][AD_SYSTEM_CALLBACK_LENGTH];
new g_SystemUpdateCallback[AD_MAX_SYSTEMS][AD_SYSTEM_CALLBACK_LENGTH];

new g_HudSync[AD_HUD_COUNT];
new bool:g_HudRegistered[AD_HUD_COUNT];
new g_HudDrawCallback[AD_HUD_COUNT][AD_HUD_CALLBACK_LENGTH];

new bool:g_AffixRegistered[AD_MAX_AFFIXES];
new g_AffixName[AD_MAX_AFFIXES][AD_AFFIX_NAME_LENGTH];
new g_AffixCount;

new g_CvarXPPerKill;
new g_CvarHudEnabled;
new bool:g_DebugEnabled;

/*=====================================================
    Core

    Core owns AMXX/ReAPI integration only. Gameplay modules are
    registered through System API and communicate through project events.
=====================================================*/

public plugin_init()
{
    register_plugin(AD_PLUGIN_NAME, AD_PLUGIN_VERSION, AD_PLUGIN_AUTHOR);

    AD_Core_RegisterHooks();
    AD_System_Init();
}

public plugin_end()
{
    AD_System_Shutdown();
}

stock AD_Core_RegisterHooks()
{
    RegisterHookChain(RG_CBasePlayer_Spawn, "HC_PlayerSpawn", true);
    RegisterHookChain(RG_CBasePlayer_Killed, "HC_PlayerKilled", true);
}

stock bool:AD_Core_IsValidPlayer(id)
{
    return (id >= 1 && id <= AD_MAX_PLAYERS);
}

stock bool:AD_Core_IsConnectedPlayer(id)
{
    return AD_Core_IsValidPlayer(id) && AD_Player_IsConnected(id);
}

/*=====================================================
    System API

    Systems register lifecycle callbacks in one place. This keeps the
    current single-file plugin easy to split into separate .inc modules.
=====================================================*/

stock AD_System_Init()
{
    g_SystemCount = 0;

    AD_System_Register("XP", "AD_XP_Init", "AD_XP_Shutdown", "AD_XP_Update");
    AD_System_Register("Tier", "AD_Tier_Init", "AD_Tier_Shutdown", "AD_Tier_Update");
    AD_System_Register("HUD", "AD_Hud_Init", "AD_Hud_Shutdown", "AD_Hud_Update");
    AD_System_Register("Developer", "AD_Developer_Init", "AD_Developer_Shutdown", "AD_Developer_Update");
    AD_System_Register("Affix", "AD_Affix_Init", "AD_Affix_Shutdown", "AD_Affix_Update");
    AD_System_Register("Weapon", "AD_Weapon_Init", "AD_Weapon_Shutdown", "AD_Weapon_Update");

    for (new systemId = 0; systemId < g_SystemCount; systemId++)
    {
        AD_System_Call(g_SystemInitCallback[systemId]);
    }

    set_task(AD_SYSTEM_UPDATE_INTERVAL, "AD_System_TaskUpdate", _, _, _, "b");
}

stock AD_System_Shutdown()
{
    for (new systemId = g_SystemCount - 1; systemId >= 0; systemId--)
    {
        AD_System_Call(g_SystemShutdownCallback[systemId]);
    }
}

stock AD_System_Update()
{
    for (new systemId = 0; systemId < g_SystemCount; systemId++)
    {
        AD_System_Call(g_SystemUpdateCallback[systemId]);
    }
}

public AD_System_TaskUpdate()
{
    AD_System_Update();
}

stock AD_System_Register(const name[], const initCallback[], const shutdownCallback[], const updateCallback[])
{
    if (g_SystemCount >= AD_MAX_SYSTEMS)
    {
        return -1;
    }

    new systemId = g_SystemCount++;

    g_SystemRegistered[systemId] = true;
    copy(g_SystemName[systemId], AD_SYSTEM_NAME_LENGTH - 1, name);
    copy(g_SystemInitCallback[systemId], AD_SYSTEM_CALLBACK_LENGTH - 1, initCallback);
    copy(g_SystemShutdownCallback[systemId], AD_SYSTEM_CALLBACK_LENGTH - 1, shutdownCallback);
    copy(g_SystemUpdateCallback[systemId], AD_SYSTEM_CALLBACK_LENGTH - 1, updateCallback);

    return systemId;
}

stock AD_System_Find(const name[])
{
    for (new systemId = 0; systemId < g_SystemCount; systemId++)
    {
        if (g_SystemRegistered[systemId] && equali(g_SystemName[systemId], name))
        {
            return systemId;
        }
    }

    return -1;
}

stock bool:AD_System_IsRegistered(systemId)
{
    return (systemId >= 0 && systemId < g_SystemCount) && g_SystemRegistered[systemId];
}

stock AD_System_GetCount()
{
    return g_SystemCount;
}

stock AD_System_Call(const callback[])
{
    if (!callback[0])
    {
        return;
    }

    if (callfunc_begin(callback) == 1)
    {
        callfunc_end();
    }
}

/*=====================================================
    AMXX/ReAPI Bridge
=====================================================*/

public client_putinserver(id)
{
    AD_Event_PlayerConnect(id);
}

public client_disconnected(id)
{
    AD_Event_PlayerDisconnect(id);
}

public HC_PlayerSpawn(id)
{
    AD_Event_PlayerSpawn(id);
    return HC_CONTINUE;
}

public HC_PlayerKilled(victim, attacker, gib)
{
    AD_Event_PlayerKilled(victim, attacker, gib);
    return HC_CONTINUE;
}

/*=====================================================
    Event Dispatcher

    Dispatcher describes what happened. It does not decide how XP,
    tiers, HUD, weapons, or affixes react to that event.
=====================================================*/

stock AD_Event_PlayerConnect(id)
{
    if (!AD_Core_IsValidPlayer(id))
    {
        return;
    }

    AD_Player_Reset(id);
    AD_Player_SetConnected(id, true);
    AD_Player_SetHudEnabled(id, true);

    AD_Affix_OnConnect(id);
    AD_Debug_LogPlayer(id, "connected");
}

stock AD_Event_PlayerDisconnect(id)
{
    if (!AD_Core_IsValidPlayer(id))
    {
        return;
    }

    AD_Affix_OnDisconnect(id);
    AD_Player_Reset(id);
}

stock AD_Event_PlayerSpawn(id)
{
    if (!AD_Core_IsConnectedPlayer(id))
    {
        return;
    }

    AD_Player_SetAlive(id, true);

    AD_Affix_OnSpawn(id);
    AD_Weapon_OnSpawn(id);
}

stock AD_Event_PlayerKilled(victim, attacker, gib)
{
    if (AD_Core_IsValidPlayer(victim))
    {
        AD_Player_AddDeath(victim);
        AD_Player_ResetKillstreak(victim);
    }

    if (AD_Event_IsValidKillReward(victim, attacker))
    {
        AD_Player_AddKill(attacker);

        AD_XP_OnPlayerKill(attacker, victim);
        AD_Affix_OnKill(attacker, victim);
        AD_Weapon_OnKill(attacker, victim, gib);
    }
}

stock bool:AD_Event_IsValidKillReward(victim, attacker)
{
    return AD_Core_IsValidPlayer(attacker) && attacker != victim;
}

/*=====================================================
    Player API

    Player storage stays private. Systems read and mutate player state
    only through this API.
=====================================================*/

stock AD_Player_Reset(id)
{
    if (!AD_Core_IsValidPlayer(id))
    {
        return;
    }

    arrayset(g_PlayerData[id], 0, AD_PlayerData);
    AD_Player_ResetStats(id);
}

stock AD_Player_SetConnected(id, bool:value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_Connected] = value;
    }
}

stock bool:AD_Player_IsConnected(id)
{
    return AD_Core_IsValidPlayer(id) && g_PlayerData[id][AD_Player_Connected];
}

stock AD_Player_SetAlive(id, bool:value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_Alive] = value;
    }
}

stock bool:AD_Player_IsAlive(id)
{
    return AD_Core_IsValidPlayer(id) && g_PlayerData[id][AD_Player_Alive];
}

stock AD_Player_AddKill(id)
{
    if (!AD_Core_IsValidPlayer(id))
    {
        return;
    }

    AD_Player_SetKills(id, AD_Player_GetKills(id) + 1);
    AD_Player_SetKillstreak(id, AD_Player_GetKillstreak(id) + 1);
}

stock AD_Player_SetKills(id, value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_Kills] = max(0, value);
    }
}

stock AD_Player_GetKills(id)
{
    return AD_Core_IsValidPlayer(id) ? g_PlayerData[id][AD_Player_Kills] : 0;
}

stock AD_Player_AddDeath(id)
{
    if (!AD_Core_IsValidPlayer(id))
    {
        return;
    }

    AD_Player_SetDeaths(id, AD_Player_GetDeaths(id) + 1);
    AD_Player_SetAlive(id, false);
}

stock AD_Player_SetDeaths(id, value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_Deaths] = max(0, value);
    }
}

stock AD_Player_GetDeaths(id)
{
    return AD_Core_IsValidPlayer(id) ? g_PlayerData[id][AD_Player_Deaths] : 0;
}

stock AD_Player_ResetKillstreak(id)
{
    AD_Player_SetKillstreak(id, 0);
}

stock AD_Player_SetKillstreak(id, value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_Killstreak] = max(0, value);
    }
}

stock AD_Player_GetKillstreak(id)
{
    return AD_Core_IsValidPlayer(id) ? g_PlayerData[id][AD_Player_Killstreak] : 0;
}

stock AD_Player_AddXP(id, amount)
{
    AD_Player_SetXP(id, AD_Player_GetXP(id) + amount);
}

stock AD_Player_SetXP(id, value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_XP] = max(0, value);
    }
}

stock AD_Player_GetXP(id)
{
    return AD_Core_IsValidPlayer(id) ? g_PlayerData[id][AD_Player_XP] : 0;
}

stock AD_Player_SetTier(id, value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_Tier] = max(0, value);
    }
}

stock AD_Player_GetTier(id)
{
    return AD_Core_IsValidPlayer(id) ? g_PlayerData[id][AD_Player_Tier] : 0;
}

stock AD_Player_AddBuildPoint(id, amount = AD_BUILD_POINTS_PER_TIER)
{
    AD_Player_SetBuildPoints(id, AD_Player_GetBuildPoints(id) + amount);
}

stock AD_Player_SetBuildPoints(id, value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_BuildPoints] = max(0, value);
    }
}

stock AD_Player_GetBuildPoints(id)
{
    return AD_Core_IsValidPlayer(id) ? g_PlayerData[id][AD_Player_BuildPoints] : 0;
}

stock AD_Player_SetHudEnabled(id, bool:value)
{
    if (AD_Core_IsValidPlayer(id))
    {
        g_PlayerData[id][AD_Player_HudEnabled] = value;
    }
}

stock bool:AD_Player_IsHudEnabled(id)
{
    return AD_Core_IsValidPlayer(id) && g_PlayerData[id][AD_Player_HudEnabled];
}

stock AD_Player_ResetStats(id)
{
    if (!AD_Core_IsValidPlayer(id))
    {
        return;
    }

    for (new stat = 0; stat < AD_STAT_COUNT; stat++)
    {
        g_PlayerStats[id][stat] = 0.0;
    }
}

stock Float:AD_Player_GetStat(id, stat)
{
    if (!AD_Core_IsValidPlayer(id) || !AD_Player_IsValidStat(stat))
    {
        return 0.0;
    }

    return g_PlayerStats[id][stat];
}

stock AD_Player_SetStat(id, stat, Float:value)
{
    if (AD_Core_IsValidPlayer(id) && AD_Player_IsValidStat(stat))
    {
        g_PlayerStats[id][stat] = value;
    }
}

stock AD_Player_AddStat(id, stat, Float:amount)
{
    AD_Player_SetStat(id, stat, AD_Player_GetStat(id, stat) + amount);
}

stock bool:AD_Player_IsValidStat(stat)
{
    return (stat >= 0 && stat < AD_STAT_COUNT);
}

/*=====================================================
    XP System
=====================================================*/

public AD_XP_Init()
{
    g_CvarXPPerKill = register_cvar("ad_xp_per_kill", "10");
}

public AD_XP_Shutdown()
{
}

public AD_XP_Update()
{
}

stock AD_XP_OnPlayerKill(attacker, victim)
{
    if (!AD_Core_IsValidPlayer(attacker))
    {
        return;
    }

    AD_XP_Give(attacker, AD_XP_GetKillReward(attacker, victim));
}

stock AD_XP_Give(id, amount)
{
    if (!AD_Core_IsValidPlayer(id) || amount <= 0)
    {
        return;
    }

    AD_Player_AddXP(id, amount);
    AD_Tier_OnPlayerXPChanged(id);
}

stock AD_XP_GetKillReward(attacker, victim)
{
    return get_pcvar_num(g_CvarXPPerKill) + (attacker * 0) + (victim * 0);
}

/*=====================================================
    Tier System
=====================================================*/

public AD_Tier_Init()
{
}

public AD_Tier_Shutdown()
{
}

public AD_Tier_Update()
{
}

stock AD_Tier_OnPlayerXPChanged(id)
{
    if (!AD_Core_IsValidPlayer(id))
    {
        return;
    }

    while (AD_Player_GetXP(id) >= AD_Tier_GetNextTierXP(id))
    {
        AD_Player_SetTier(id, AD_Player_GetTier(id) + 1);
        AD_Player_AddBuildPoint(id);
    }
}

stock AD_Tier_SetPlayerTier(id, tier)
{
    AD_Player_SetTier(id, tier);
}

stock AD_Tier_GetNextTierXP(id)
{
    return (AD_Player_GetTier(id) + 1) * AD_TIER_XP_STEP;
}

/*=====================================================
    HUD System

    HUD owns rendering cadence and registered HUD surfaces. Individual
    HUDs can later move into independent modules.
=====================================================*/

public AD_Hud_Init()
{
    g_CvarHudEnabled = register_cvar("ad_hud", "1");

    AD_Hud_Register(AD_HUD_MAIN, "AD_Hud_DrawMain");
    AD_Hud_Register(AD_HUD_DEBUG, "AD_Hud_DrawDebug");
    AD_Hud_Register(AD_HUD_AFFIX, "AD_Hud_DrawAffix");
    AD_Hud_Register(AD_HUD_DAMAGE, "AD_Hud_DrawDamage");
}

public AD_Hud_Shutdown()
{
}

public AD_Hud_Update()
{
    if (!AD_Hud_IsGloballyEnabled())
    {
        return;
    }

    for (new id = 1; id <= AD_MAX_PLAYERS; id++)
    {
        if (!AD_Hud_CanShowToPlayer(id))
        {
            continue;
        }

        AD_Hud_DrawPlayer(id);
    }
}

stock AD_Hud_Register(hudType, const drawCallback[])
{
    if (!AD_Hud_IsValidType(hudType))
    {
        return false;
    }

    g_HudRegistered[hudType] = true;
    g_HudSync[hudType] = CreateHudSyncObj();
    copy(g_HudDrawCallback[hudType], AD_HUD_CALLBACK_LENGTH - 1, drawCallback);

    return true;
}

stock AD_Hud_DrawPlayer(id)
{
    for (new hudType = 0; hudType < AD_HUD_COUNT; hudType++)
    {
        if (g_HudRegistered[hudType])
        {
            AD_Hud_DrawSurface(id, hudType);
        }
    }
}

stock AD_Hud_DrawSurface(id, hudType)
{
    if (!AD_Hud_IsValidType(hudType) || !g_HudDrawCallback[hudType][0])
    {
        return;
    }

    if (callfunc_begin(g_HudDrawCallback[hudType]) == 1)
    {
        callfunc_push_int(id);
        callfunc_end();
    }
}

public AD_Hud_DrawMain(id)
{
    set_hudmessage(220, 50, 50, 0.02, 0.18, 0, 0.0, 1.1, 0.0, 0.0, AD_HUD_CHANNEL_MAIN);

    ShowSyncHudMsg(
        id,
        g_HudSync[AD_HUD_MAIN],
        "Tier: %d^nXP: %d^nKillstreak: %d^nBuild: %d",
        AD_Player_GetTier(id),
        AD_Player_GetXP(id),
        AD_Player_GetKillstreak(id),
        AD_Player_GetBuildPoints(id)
    );
}

public AD_Hud_DrawDebug(id)
{
    if (!g_DebugEnabled)
    {
        return;
    }

    set_hudmessage(120, 180, 255, 0.02, 0.34, 0, 0.0, 1.1, 0.0, 0.0, AD_HUD_CHANNEL_DEBUG);

    ShowSyncHudMsg(
        id,
        g_HudSync[AD_HUD_DEBUG],
        "Kills: %d^nDeaths: %d^nAffixes: %d",
        AD_Player_GetKills(id),
        AD_Player_GetDeaths(id),
        AD_GetAffixCount()
    );
}

public AD_Hud_DrawAffix(id)
{
    return id;
}

public AD_Hud_DrawDamage(id)
{
    return id;
}

stock bool:AD_Hud_IsGloballyEnabled()
{
    return bool:get_pcvar_num(g_CvarHudEnabled);
}

stock bool:AD_Hud_CanShowToPlayer(id)
{
    return AD_Core_IsConnectedPlayer(id) && AD_Player_IsHudEnabled(id);
}

stock bool:AD_Hud_IsValidType(hudType)
{
    return (hudType >= 0 && hudType < AD_HUD_COUNT);
}

/*=====================================================
    Developer API
=====================================================*/

public AD_Developer_Init()
{
    register_concmd("ad_givexp", "AD_Command_GiveXP", ADMIN_RCON, "<name/#userid> <amount>");
    register_concmd("ad_settier", "AD_Command_SetTier", ADMIN_RCON, "<name/#userid> <tier>");
    register_concmd("ad_reset", "AD_Command_Reset", ADMIN_RCON, "<name/#userid>");
    register_concmd("ad_debug", "AD_Command_Debug", ADMIN_RCON, "<0|1>");
}

public AD_Developer_Shutdown()
{
}

public AD_Developer_Update()
{
}

public AD_Command_GiveXP(id, level, cid)
{
    if (!cmd_access(id, level, cid, 3))
    {
        return PLUGIN_HANDLED;
    }

    new target = AD_Developer_ReadTargetArg(id, 1);
    if (!target)
    {
        return PLUGIN_HANDLED;
    }

    new amountArg[16];
    read_argv(2, amountArg, charsmax(amountArg));

    AD_XP_Give(target, str_to_num(amountArg));

    return PLUGIN_HANDLED;
}

public AD_Command_SetTier(id, level, cid)
{
    if (!cmd_access(id, level, cid, 3))
    {
        return PLUGIN_HANDLED;
    }

    new target = AD_Developer_ReadTargetArg(id, 1);
    if (!target)
    {
        return PLUGIN_HANDLED;
    }

    new tierArg[16];
    read_argv(2, tierArg, charsmax(tierArg));
    AD_Tier_SetPlayerTier(target, str_to_num(tierArg));

    return PLUGIN_HANDLED;
}

public AD_Command_Reset(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
    {
        return PLUGIN_HANDLED;
    }

    new target = AD_Developer_ReadTargetArg(id, 1);
    if (!target)
    {
        return PLUGIN_HANDLED;
    }

    AD_Player_Reset(target);
    AD_Player_SetConnected(target, true);
    AD_Player_SetHudEnabled(target, true);

    return PLUGIN_HANDLED;
}

public AD_Command_Debug(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
    {
        return PLUGIN_HANDLED;
    }

    new valueArg[8];
    read_argv(1, valueArg, charsmax(valueArg));
    g_DebugEnabled = bool:clamp(str_to_num(valueArg), 0, 1);

    return PLUGIN_HANDLED;
}

stock AD_Developer_ReadTargetArg(adminId, argIndex)
{
    new targetArg[32];
    read_argv(argIndex, targetArg, charsmax(targetArg));

    new target = cmd_target(adminId, targetArg, CMDTARGET_ALLOW_SELF);
    if (!target)
    {
        console_print(adminId, "[AD] Player not found.");
    }

    return target;
}

stock AD_Debug_LogPlayer(id, const action[])
{
    if (g_DebugEnabled)
    {
        server_print("[AD DEBUG] Player %d %s", id, action);
    }
}

/*=====================================================
    Weapon API

    Weapon hooks are intentionally effect-free in this release. The API
    exists so next releases can attach weapon modifiers without touching
    Core or Event Dispatcher.
=====================================================*/

public AD_Weapon_Init()
{
}

public AD_Weapon_Shutdown()
{
}

public AD_Weapon_Update()
{
}

stock AD_Weapon_OnSpawn(id)
{
    return id;
}

stock AD_Weapon_OnKill(attacker, victim, gib)
{
    return attacker + victim + gib;
}

stock AD_Weapon_OnDeploy(id, weaponEntity)
{
    return id + weaponEntity;
}

stock AD_Weapon_OnFire(id, weaponEntity)
{
    return id + weaponEntity;
}

stock AD_Weapon_OnReload(id, weaponEntity)
{
    return id + weaponEntity;
}

stock AD_Weapon_OnDamage(victim, attacker, weaponEntity, Float:damage)
{
    return victim + attacker + weaponEntity + floatround(damage);
}

/*=====================================================
    Affix Engine

    Affixes can be registered, found, counted, and named. Gameplay
    effects remain empty until affix implementations are introduced.
=====================================================*/

public AD_Affix_Init()
{
}

public AD_Affix_Shutdown()
{
}

public AD_Affix_Update()
{
}

stock AD_RegisterAffix(const name[])
{
    new existingAffix = AD_FindAffix(name);
    if (existingAffix != AD_INVALID_AFFIX)
    {
        return existingAffix;
    }

    if (g_AffixCount >= AD_MAX_AFFIXES)
    {
        return AD_INVALID_AFFIX;
    }

    new affixId = g_AffixCount++;
    g_AffixRegistered[affixId] = true;
    copy(g_AffixName[affixId], AD_AFFIX_NAME_LENGTH - 1, name);

    return affixId;
}

stock AD_FindAffix(const name[])
{
    for (new affixId = 0; affixId < g_AffixCount; affixId++)
    {
        if (g_AffixRegistered[affixId] && equali(g_AffixName[affixId], name))
        {
            return affixId;
        }
    }

    return AD_INVALID_AFFIX;
}

stock AD_GetAffixName(affixId, output[], outputLength)
{
    if (!AD_IsAffixRegistered(affixId))
    {
        output[0] = 0;
        return false;
    }

    copy(output, outputLength - 1, g_AffixName[affixId]);
    return true;
}

stock AD_GetAffixCount()
{
    return g_AffixCount;
}

stock bool:AD_IsAffixRegistered(affixId)
{
    return (affixId >= 0 && affixId < g_AffixCount) && g_AffixRegistered[affixId];
}

stock AD_ApplyAffix(id, affixId)
{
    if (!AD_Core_IsValidPlayer(id) || !AD_IsAffixRegistered(affixId))
    {
        return false;
    }

    return true;
}

stock AD_RemoveAffix(id, affixId)
{
    if (!AD_Core_IsValidPlayer(id) || !AD_IsAffixRegistered(affixId))
    {
        return false;
    }

    return true;
}

stock AD_Affix_OnConnect(id)
{
    return id;
}

stock AD_Affix_OnDisconnect(id)
{
    return id;
}

stock AD_Affix_OnKill(attacker, victim)
{
    return attacker + victim;
}

stock AD_Affix_OnSpawn(id)
{
    return id;
}

stock AD_Affix_OnDamage(victim, attacker, Float:damage)
{
    return victim + attacker + floatround(damage);
}
