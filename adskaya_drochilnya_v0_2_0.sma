/*=====================================================
    ADSKAYA DROCHILNYA
    Version: 0.2.0 CORE
=====================================================*/
#include <amxmodx>
#include <reapi>

#define PLUGIN "ADSKAYA DROCHILNYA"
#define VERSION "0.2.0"
#define AUTHOR "Open Source"
#define MAX_PLAYERS 32

enum PlayerData
{
    bool:Connected,
    bool:Alive,
    Kills,
    Deaths,
    Killstreak,
    XP,
    Tier,
    BuildPoints,
    bool:HudEnabled
}
new g_Player[MAX_PLAYERS+1][PlayerData];
new g_HudSync;
new g_CvarXPPerKill,g_CvarHud;

public plugin_init()
{
    register_plugin(PLUGIN,VERSION,AUTHOR);
    g_HudSync=CreateHudSyncObj();
    g_CvarXPPerKill=register_cvar("ad_xp_per_kill","10");
    g_CvarHud=register_cvar("ad_hud","1");
    RegisterHookChain(RG_CBasePlayer_Spawn,"HC_PlayerSpawn",true);
    RegisterHookChain(RG_CBasePlayer_Killed,"HC_PlayerKilled",true);
    set_task(1.0,"Task_HUD",_,_,_,"b");
}
public client_putinserver(id){AD_ResetPlayer(id);g_Player[id][Connected]=true;g_Player[id][HudEnabled]=true;}
public client_disconnected(id){AD_ResetPlayer(id);}
public HC_PlayerSpawn(id){if(!is_user_connected(id))return HC_CONTINUE;g_Player[id][Alive]=true;return HC_CONTINUE;}
public HC_PlayerKilled(victim,attacker,gib){AD_OnPlayerKilled(victim,attacker);return HC_CONTINUE;}

stock AD_OnPlayerKilled(victim,attacker)
{
    AD_AddDeath(victim);
    AD_ResetKillstreak(victim);
    if(attacker>0&&attacker<=MAX_PLAYERS&&attacker!=victim){
        AD_AddKill(attacker);
        AD_AddXP(attacker,get_pcvar_num(g_CvarXPPerKill));
        AD_CheckTier(attacker);
    }
}
stock AD_ResetPlayer(id){arrayset(g_Player[id],0,PlayerData);}
stock AD_AddKill(id){g_Player[id][Kills]++;g_Player[id][Killstreak]++;}
stock AD_AddDeath(id){g_Player[id][Deaths]++;g_Player[id][Alive]=false;}
stock AD_ResetKillstreak(id){g_Player[id][Killstreak]=0;}
stock AD_AddXP(id,amount){g_Player[id][XP]+=amount;}
stock AD_CheckTier(id){
    while(g_Player[id][XP]>=(g_Player[id][Tier]+1)*100){
        g_Player[id][Tier]++;
        g_Player[id][BuildPoints]++;
    }
}
stock AD_GetTier(id){return g_Player[id][Tier];}
stock AD_GetXP(id){return g_Player[id][XP];}
stock AD_GetBuildPoints(id){return g_Player[id][BuildPoints];}

public Task_HUD()
{
    if(!get_pcvar_num(g_CvarHud)) return;
    set_hudmessage(220,50,50,0.02,0.18,0,0.0,1.1,0.0,0.0,-1);
    for(new id=1;id<=MAX_PLAYERS;id++){
        if(!is_user_connected(id)||!g_Player[id][HudEnabled]) continue;
        ShowSyncHudMsg(id,g_HudSync,
        "Tier: %d^nXP: %d^nKillstreak: %d^nBuild: %d",
        AD_GetTier(id),AD_GetXP(id),g_Player[id][Killstreak],AD_GetBuildPoints(id));
    }
}
