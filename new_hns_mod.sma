// ======================================================================
// CS 1.6 Hide and Seek (捉迷藏) Plugin - Complete Rewrite
// Compatible with AMX Mod X 1.82+
// ======================================================================

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <nvault>

#define PLUGIN  "Hide and Seek Mod"
#define VERSION "2.1"
#define AUTHOR  "HNS Community"

// ======================================================================
// Constants
// ======================================================================
#define MAX_PLAYERS           32
#define TEAM_T                0
#define TEAM_CT               1

#define DEFAULT_MONEY         10000
#define DEFAULT_FREEZE_TIME   5
#define DEFAULT_LICENSE_LIMIT 50
#define PLAYTIME_PER_LICENSE  1800   // 30 min

#define TASK_PLAYTIME         100
#define TASK_SURVIVAL         200
#define TASK_FREEZE           300
#define TASK_KUNGFU           400
#define TASK_FALLSHOP         500
#define TASK_CLAIRVOYANCE     600
#define TASK_HUD              700
#define TASK_LICDISPLAY       800
#define TASK_AUTOCV           900

// License page IDs
#define LICPAGE_MAIN          0
#define LICPAGE_SPEED         1
#define LICPAGE_MAXHP         2
#define LICPAGE_ITEMS         3
#define LICPAGE_FALL          4
#define LICPAGE_ENEMYAA       5
#define LICPAGE_SUPER         6
#define LICPAGE_KUNGFU        7
#define LICPAGE_RESERVED      8

#define clampx(%1,%2,%3) (((%1)>(%3))?(%3):(((%1)<(%2))?(%2):(%1)))
#define minx(%1,%2) (((%1)<(%2))?(%1):(%2))
#define maxx(%1,%2) (((%1)>(%2))?(%1):(%2))

// ======================================================================
// Global Variables
// ======================================================================

// --- Player Data ---
new g_iRoundMoney[MAX_PLAYERS+1]
new g_iStoredMoney[MAX_PLAYERS+1]
new g_iLicenses[MAX_PLAYERS+1]
new g_iPlayTimeSec[MAX_PLAYERS+1]
new g_iRoundKills[MAX_PLAYERS+1]
new g_bFrozen[MAX_PLAYERS+1]              // FIX: removed bool: tag
new g_iSuperhumanLv[MAX_PLAYERS+1]

// Shop states (per round, per player)
new g_bClairvoyanceRound[MAX_PLAYERS+1]   // FIX: removed bool: tag
new Float:g_flMedkitCD[MAX_PLAYERS+1]
new g_iFlashBought[MAX_PLAYERS+1]
new g_iSmokeBought[MAX_PLAYERS+1]
new Float:g_flFlashCD[MAX_PLAYERS+1]
new g_bFallShopActive[MAX_PLAYERS+1]      // FIX: removed bool: tag
new g_bKungFuActive[MAX_PLAYERS+1]       // FIX: removed bool: tag

// Auto clairvoyance
new g_bAutoCV[MAX_PLAYERS+1]             // FIX: removed bool: tag

// Mute
new g_bMuted[MAX_PLAYERS+1][MAX_PLAYERS+1] // FIX: removed bool: tag

// License menu tracking
new g_iLicPage[MAX_PLAYERS+1]
new g_bInLicMenu[MAX_PLAYERS+1]          // FIX: removed bool: tag

// --- Team Data [TEAM_T=0, TEAM_CT=1] ---
new g_iTeamSpeedLv[2]
new g_iTeamMaxHPLv[2]
new g_iTeamFlashLv[2]       // T only
new g_iTeamLightKnifeLv[2]  // CT only
new g_iTeamFallLv[2]
new g_iTeamEnemyAALv[2]
new g_iTeamGravityLv[2]
new g_iTeamLicUsed[2]

// --- Round Data ---
new g_bRoundActive                       // FIX: removed bool: tag
new g_bFreezePeriod                      // FIX: removed bool: tag
new Float:g_flRoundStartTime
new g_iConsecutiveCTLoss
new g_bCTAllSurvived                     // FIX: removed bool: tag
new g_bTAllSurvived                      // FIX: removed bool: tag

// --- Config ---
new g_iFreezeTime
new g_iLicenseLimit        // 0=no limit allowed, >0=limit, -1=unlimited
new g_iSpawnProtect        // 1=protected, 2=heal on unfreeze, 3=no protect
new g_iCollisionMode       // 1=teammate no collision, 2=all collision

// --- Misc ---
new g_iMaxPlayers
new g_vault
new g_sBeamSprite
new Float:g_flLastSurvivalTick

// ======================================================================
// Macros for team index
// ======================================================================
stock getTeamIdx(id) {
    return _:cs_get_user_team(id) - 1
}

// ======================================================================
// Plugin Lifecycle
// ======================================================================
public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)

    g_iMaxPlayers = get_maxplayers()
    g_iFreezeTime = DEFAULT_FREEZE_TIME
    g_iLicenseLimit = DEFAULT_LICENSE_LIMIT
    g_iSpawnProtect = 1
    g_iCollisionMode = 1

    // CVar
    register_cvar("hns_freezetime", "5")
    register_cvar("hns_license_limit", "50")

    // Events
    register_event("HLTV",      "Ev_NewRound",  "a", "1=0", "2=0")
    register_event("DeathMsg",  "Ev_DeathMsg",  "a")
    register_event("CurWeapon", "Ev_CurWeapon", "be", "1=1")
    register_logevent("Ev_RoundEnd", 2, "1=Round_End")

    // Block buy commands
    register_clcmd("buy",       "Cmd_BlockBuy")
    register_clcmd("buyammo1",  "Cmd_BlockBuy")
    register_clcmd("buyammo2",  "Cmd_BlockBuy")
    register_clcmd("cl_autobuy","Cmd_BlockBuy")
    register_clcmd("cl_rebuy",  "Cmd_BlockBuy")

    // Chat commands
    register_clcmd("say /hxhns",   "Cmd_MainMenu")
    register_clcmd("say_team /hxhns","Cmd_MainMenu")
    register_clcmd("say /help",    "Cmd_MainMenu")
    register_clcmd("say_team /help","Cmd_MainMenu")

    // Console commands
    register_concmd("hns_freezetime", "Cmd_SetFreezeTime", ADMIN_CVAR, "<seconds>")
    register_concmd("hns_license_limit","Cmd_SetLicenseLimit",ADMIN_CVAR,"<number|-1=unlimited>")

    // Ham hooks
    RegisterHam(Ham_Spawn,         "player", "Ham_Spawn_Post",       1)
    RegisterHam(Ham_Killed,        "player", "Ham_Killed_Post",      1)
    RegisterHam(Ham_TakeDamage,    "player", "Ham_TakeDamage_Pre",   0)
    RegisterHam(Ham_AddPlayerItem, "player", "Ham_AddItem_Pre",      0)

    // FM hooks
    register_forward(FM_PlayerPreThink, "FM_PreThink")
    register_forward(FM_Voice_SetClientListening, "FM_VoiceListen")

    // Menus
    register_menu("hns_main",        1023, "HandleMainMenu")
    register_menu("hns_shop",        1023, "HandleShopMenu")
    register_menu("hns_licmain",     1023, "HandleLicMain")
    register_menu("hns_licsub",      1023, "HandleLicSub")
    register_menu("hns_admin",       1023, "HandleAdminMenu")
    register_menu("hns_adm_rtime",   1023, "HandleAdmRoundTime")
    register_menu("hns_adm_freeze",  1023, "HandleAdmFreeze")
    register_menu("hns_adm_coll",    1023, "HandleAdmCollision")
    register_menu("hns_adm_prot",    1023, "HandleAdmProtect")
    register_menu("hns_adm_limit",   1023, "HandleAdmLimit")
    register_menu("hns_mute",        1023, "HandleMuteMenu")

    // Data vault
    g_vault = nvault_open("hns_data")
    if (g_vault == INVALID_HANDLE)
        set_fail_state("Cannot open nvault hns_data")

    // Periodic tasks
    set_task(1.0, "Task_PlayTime",  TASK_PLAYTIME,  _, _, "b")
    set_task(1.0, "Task_Survival",  TASK_SURVIVAL,  _, _, "b")
    set_task(0.5, "Task_HUD",       TASK_HUD,       _, _, "b")

    // Server settings
    server_cmd("sv_airaccelerate 100")
    server_cmd("mp_freezetime 0")
    server_cmd("mp_buytime 0")
    server_cmd("mp_friendlyfire 0")
}

public plugin_precache() {
    g_sBeamSprite = precache_model("sprites/laserbeam.spr")
}

public plugin_cfg() {
    server_cmd("sv_airaccelerate 100")
    g_iFreezeTime = get_cvar_num("hns_freezetime")
    if (g_iFreezeTime < 0) g_iFreezeTime = 0
    g_iLicenseLimit = get_cvar_num("hns_license_limit")
}

public plugin_end() {
    nvault_close(g_vault)
}

// ======================================================================
// Client Events
// ======================================================================
public client_putinserver(id) {
    ResetPlayerRound(id)
    g_iStoredMoney[id] = 0
    g_iLicenses[id] = 0
    g_iPlayTimeSec[id] = 0
    g_iSuperhumanLv[id] = 0
    g_bInLicMenu[id] = 0
    g_iLicPage[id] = 0
    for (new i = 1; i <= g_iMaxPlayers; i++)
        g_bMuted[id][i] = 0
    LoadPlayerData(id)
}

public client_disconnected(id) {
    SavePlayerData(id)
    remove_task(TASK_CLAIRVOYANCE + id)
    remove_task(TASK_AUTOCV + id)
    remove_task(TASK_KUNGFU + id)
    remove_task(TASK_FALLSHOP + id)
    ResetPlayerRound(id)
}

ResetPlayerRound(id) {
    g_iRoundMoney[id] = 0
    g_iRoundKills[id] = 0
    g_bFrozen[id] = 0
    g_bClairvoyanceRound[id] = 0
    g_flMedkitCD[id] = 0.0
    g_iFlashBought[id] = 0
    g_iSmokeBought[id] = 0
    g_flFlashCD[id] = 0.0
    g_bFallShopActive[id] = 0
    g_bKungFuActive[id] = 0
    g_bAutoCV[id] = 0
}

// ======================================================================
// Round Events
// ======================================================================
public Ev_NewRound() {
    g_bRoundActive = 0
    g_bFreezePeriod = 1
    g_flRoundStartTime = get_gametime()
    g_flLastSurvivalTick = get_gametime()
    g_bCTAllSurvived = 0
    g_bTAllSurvived = 0

    // Reset team license usage & effects
    for (new t = 0; t < 2; t++) {
        g_iTeamLicUsed[t] = 0
        g_iTeamSpeedLv[t] = 0
        g_iTeamMaxHPLv[t] = 0
        g_iTeamFlashLv[t] = 0
        g_iTeamLightKnifeLv[t] = 0
        g_iTeamFallLv[t] = 0
        g_iTeamEnemyAALv[t] = 0
        g_iTeamGravityLv[t] = 0
    }

    // Reset per-player round data
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_connected(i)) {
            ResetPlayerRound(i)
            g_iRoundMoney[i] = DEFAULT_MONEY
            SyncMoney(i)
        }
        remove_task(TASK_CLAIRVOYANCE + i)
        remove_task(TASK_AUTOCV + i)
        remove_task(TASK_KUNGFU + i)
        remove_task(TASK_FALLSHOP + i)
    }

    // Freeze task
    remove_task(TASK_FREEZE)
    if (g_iFreezeTime > 0)
        set_task(float(g_iFreezeTime), "Task_UnfreezeCTs", TASK_FREEZE)

    // Show team license display for 15s
    remove_task(TASK_LICDISPLAY)
    set_task(1.0, "Task_LicDisplay", TASK_LICDISPLAY, _, _, "a", 15)
}

public Ev_RoundEnd() {
    if (!g_bFreezePeriod && !g_bRoundActive) return;
    g_bRoundActive = 0
    g_bFreezePeriod = 0

    new ctAlive = CountAlive(CS_TEAM_CT);
    new tAlive  = CountAlive(CS_TEAM_T);
    new ctTotal = CountTotal(CS_TEAM_CT);
    new tTotal  = CountTotal(CS_TEAM_T);

    g_bCTAllSurvived = (ctAlive == ctTotal && ctTotal > 0) ? 1 : 0
    g_bTAllSurvived  = (tAlive  == tTotal  && tTotal  > 0) ? 1 : 0

    new ctWon = (ctAlive > 0 && tAlive == 0) ? 1 : 0

    if (ctWon) {
        g_iConsecutiveCTLoss = 0
        GiveTeamMoney(CS_TEAM_CT, 2000);
        GiveTeamMoney(CS_TEAM_T,  100);
    } else {
        g_iConsecutiveCTLoss++
        GiveTeamMoney(CS_TEAM_T,  2000);
        GiveTeamMoney(CS_TEAM_CT, 100);
    }

    // ---- License rewards ----
    // T: survive = +1
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_alive(i) && cs_get_user_team(i) == CS_TEAM_T) {
            AddLicense(i, 1)
            client_print(i, print_chat, "[许可证] 存活至回合结束，获得1张许可证！")
        }
    }
    // T: all survive = +1 extra
    if (g_bTAllSurvived) {
        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (is_user_alive(i) && cs_get_user_team(i) == CS_TEAM_T) {
                AddLicense(i, 1)
                client_print(i, print_chat, "[许可证] 全员存活，额外获得1张！")
            }
        }
    }
    // T: survive + CT all survived = +5
    if (g_bTAllSurvived && g_bCTAllSurvived) {
        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (is_user_alive(i) && cs_get_user_team(i) == CS_TEAM_T) {
                AddLicense(i, 5)
                client_print(i, print_chat, "[许可证] 双方全员存活，获得5张许可证！")
            }
        }
    }

    // CT: best killer = +1 (on win)
    if (ctWon && ctTotal > 0) {
        new bestKiller = 0, bestKills = 0
        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (is_user_connected(i) && cs_get_user_team(i) == CS_TEAM_CT && g_iRoundKills[i] > bestKills) {
                bestKills = g_iRoundKills[i]
                bestKiller = i
            }
        }
        if (bestKiller > 0) {
            AddLicense(bestKiller, 1)
            client_print(bestKiller, print_chat, "[许可证] 本回合最佳，额外获得1张许可证！")
        }
    }
    // CT: perfect win = +1 all
    if (ctWon && g_bCTAllSurvived && tTotal > 0 && tAlive == 0) {
        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (is_user_connected(i) && cs_get_user_team(i) == CS_TEAM_CT) {
                AddLicense(i, 1)
                client_print(i, print_chat, "[许可证] 完胜！额外获得1张许可证！")
            }
        }
    }
    // CT: single CT kills all T = +5
    if (tTotal > 0) {
        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (is_user_connected(i) && cs_get_user_team(i) == CS_TEAM_CT && g_iRoundKills[i] >= tTotal) {
                AddLicense(i, 5)
                client_print(i, print_chat, "[许可证] 击杀全部T方，获得5张许可证！")
            }
        }
    }

    // ---- License bonus (differential) ----
    CalcLicenseBonus(ctWon)

    // Save all data
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_connected(i)) SavePlayerData(i)
    }
}

public Ev_DeathMsg() {
    new killer = read_data(1)
    new victim = read_data(2)

    if (killer != victim && is_user_connected(killer)) {
        g_iRoundKills[killer]++
        if (cs_get_user_team(killer) == CS_TEAM_CT) {
            AddMoney(killer, 1000)
            if (g_iRoundKills[killer] >= 3) {
                AddLicense(killer, 1)
                client_print(killer, print_chat, "[许可证] 击杀达标，获得1张许可证！")
            }
        }
    }

    // Check auto clairvoyance: 1 CT alive + 3+ T alive
    if (is_user_connected(victim)) {
        new ctAlive = CountAlive(CS_TEAM_CT);
        new tAlive  = CountAlive(CS_TEAM_T);
        if (ctAlive == 1 && tAlive >= 3) {
            new players[32], num
            get_players(players, num, "ae", "CT")
            if (num == 1) {
                new lastCT = players[0]
                if (!g_bAutoCV[lastCT]) {
                    g_bAutoCV[lastCT] = 1
                    client_print(lastCT, print_chat, "[千里眼] 你是最后的希望！千里眼已开启！")
                    new param[2]
                    param[0] = lastCT
                    param[1] = -1  // permanent
                    Task_CVBeam(param)
                }
            }
        }
    }
}

public Ev_CurWeapon(id) {
    if (!is_user_alive(id)) return
    UpdatePlayerSpeed(id)
}

// ======================================================================
// Ham Hooks
// ======================================================================
public Ham_Spawn_Post(id) {
    if (!is_user_alive(id)) return HAM_IGNORED

    // Strip all weapons, give knife
    strip_user_weapons(id)
    give_item(id, "weapon_knife")

    // Set money
    if (g_iRoundMoney[id] <= 0) g_iRoundMoney[id] = DEFAULT_MONEY
    SyncMoney(id)

    // Apply team effects
    new team = getTeamIdx(id)
    if (team == TEAM_T || team == TEAM_CT) {
        ApplyTeamHP(id, team)
        ApplyPlayerGravity(id)
    }

    // Freeze CT
    if (g_bFreezePeriod && cs_get_user_team(id) == CS_TEAM_CT) {
        FreezePlayer(id)
    }

    return HAM_IGNORED
}

public Ham_Killed_Post(victim, attacker, shouldgib) {
    if (!is_user_alive(victim)) {
        set_pev(victim, pev_solid, SOLID_NOT)
    }
}

public Ham_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits) {
    if (!is_user_connected(attacker) || !is_user_connected(victim))
        return HAM_IGNORED

    // Spawn protection
    if (g_bFrozen[victim] && g_iSpawnProtect == 1)
        return HAM_SUPERCEDE

    // No team damage
    if (attacker != victim && cs_get_user_team(attacker) == cs_get_user_team(victim))
        return HAM_SUPERCEDE

    new atkTeam = _:cs_get_user_team(attacker)   // FIX: use int not CsTeams: tag

    // CT: only knife deals damage
    if (atkTeam == _:CS_TEAM_CT) {
        new weapon = get_user_weapon(attacker)
        if (weapon != CSW_KNIFE)
            return HAM_SUPERCEDE
    }

    // T: knife deals no damage
    if (atkTeam == _:CS_TEAM_T) {
        new weapon = get_user_weapon(attacker)
        if (weapon == CSW_KNIFE)
            return HAM_SUPERCEDE
    }

    // T HE grenade: 0.3x damage
    if (atkTeam == _:CS_TEAM_T && inflictor != attacker) {
        new classname[32]
        pev(inflictor, pev_classname, classname, charsmax(classname))
        if (equal(classname, "grenade")) {
            SetHamParamFloat(4, damage * 0.3)
            return HAM_HANDLED
        }
    }

    // Fall damage reduction
    if (damagebits & DMG_FALL) {
        new fallLv = GetFallResistLevel(victim)
        if (fallLv >= 1) {
            new hp = get_user_health(victim)
            if (floatround(damage) < hp) {
                // Non-lethal
                if (fallLv == 1)
                    SetHamParamFloat(4, floatmin(damage, 5.0))
                else
                    SetHamParamFloat(4, 0.0)
            } else {
                // Lethal
                if (fallLv == 1)
                    SetHamParamFloat(4, 40.0)
                else
                    SetHamParamFloat(4, 12.0)
            }
            return HAM_HANDLED
        }
    }

    return HAM_IGNORED
}

public Ham_AddItem_Pre(id, item) {
    if (!is_user_connected(id)) return HAM_IGNORED
    if (cs_get_user_team(id) != CS_TEAM_T) return HAM_IGNORED

    new classname[32]
    pev(item, pev_classname, classname, charsmax(classname))

    // T can only have knife + throwables
    if (equal(classname, "weapon_knife") ||
        equal(classname, "weapon_hegrenade") ||
        equal(classname, "weapon_flashbang") ||
        equal(classname, "weapon_smokegrenade"))
        return HAM_IGNORED

    return HAM_SUPERCEDE
}

// ======================================================================
// FM Hooks
// ======================================================================
public FM_PreThink(id) {
    if (!is_user_alive(id)) return FMRES_IGNORED

    // Freeze: zero velocity
    if (g_bFrozen[id]) {
        new Float:zero[3]
        zero[0] = 0.0; zero[1] = 0.0; zero[2] = 0.0
        set_pev(id, pev_velocity, zero)
        set_pev(id, pev_maxspeed, 0.0)
        return FMRES_IGNORED
    }

    // Update speed every frame (replaces Ham_ResetMaxSpeed for AMXX 1.82)
    UpdatePlayerSpeed(id)

    // Superhuman Lv2: no jump fatigue
    if (g_iSuperhumanLv[id] >= 2)
        set_pev(id, pev_fuser2, 0.0)

    // Collision management
    ManageCollision(id)

    // Enemy AA management
    ManageEnemyAA(id)

    // E key for main menu
    new button = pev(id, pev_button)
    new oldbuttons = pev(id, pev_oldbuttons)
    if ((button & IN_USE) && !(oldbuttons & IN_USE))
        ShowMainMenu(id)

    return FMRES_IGNORED
}

public FM_VoiceListen(iReceiver, iSender) {
    if (iReceiver < 1 || iReceiver > g_iMaxPlayers ||
        iSender < 1 || iSender > g_iMaxPlayers)
        return FMRES_IGNORED
    if (g_bMuted[iReceiver][iSender]) {
        engfunc(EngFunc_SetClientListening, iReceiver, iSender, 0)
        return FMRES_SUPERCEDE
    }
    return FMRES_IGNORED
}

// ======================================================================
// Freeze / Unfreeze
// ======================================================================
FreezePlayer(id) {
    g_bFrozen[id] = 1
    set_pev(id, pev_maxspeed, 0.0)
    set_pev(id, pev_gravity, 0.0)
    new Float:zero[3]
    zero[0] = 0.0; zero[1] = 0.0; zero[2] = 0.0
    set_pev(id, pev_velocity, zero)
    client_print(id, print_center, "你已被冻结，请等待搜寻者准备完毕！")
}

public Task_UnfreezeCTs() {
    g_bFreezePeriod = 0
    g_bRoundActive = 1

    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (g_bFrozen[i] && is_user_alive(i)) {
            g_bFrozen[i] = 0
            set_pev(i, pev_gravity, 1.0)
            if (g_iSpawnProtect == 2)
                set_user_health(i, GetMaxHP(i))
            ApplyPlayerGravity(i)
            client_print(i, print_center, "冻结解除，开始搜寻！")
        }
    }
}

// ======================================================================
// Main Menu
// ======================================================================
public Cmd_MainMenu(id) {
    ShowMainMenu(id)
    return PLUGIN_HANDLED
}

ShowMainMenu(id) {
    new menu[512], len, keys

    len = formatex(menu[len], charsmax(menu)-len, "\y【 捉迷藏 】\w 主菜单^n^n")
    len += formatex(menu[len], charsmax(menu)-len, "\w1. 加入游戏^n")
    keys |= MENU_KEY_1
    len += formatex(menu[len], charsmax(menu)-len, "\w2. 商店^n")
    keys |= MENU_KEY_2
    len += formatex(menu[len], charsmax(menu)-len, "\w3. 许可证商店^n")
    keys |= MENU_KEY_3
    len += formatex(menu[len], charsmax(menu)-len, "\w4. 规则说明^n")
    keys |= MENU_KEY_4

    if (get_user_flags(id) & ADMIN_LEVEL_A) {
        len += formatex(menu[len], charsmax(menu)-len, "\w5. 投票换图 (VIP)^n")
        keys |= MENU_KEY_5
    } else {
        len += formatex(menu[len], charsmax(menu)-len, "\d5. 投票换图 (仅VIP)^n")
    }

    len += formatex(menu[len], charsmax(menu)-len, "\d6. 投票踢人 (暂未开放)^n")
    len += formatex(menu[len], charsmax(menu)-len, "\w7. 禁用玩家语音^n")
    keys |= MENU_KEY_7

    if (get_user_flags(id) & ADMIN_BAN) {
        len += formatex(menu[len], charsmax(menu)-len, "\w8. 管理员菜单^n")
        keys |= MENU_KEY_8
    } else {
        len += formatex(menu[len], charsmax(menu)-len, "\d8. 管理员菜单^n")
    }

    len += formatex(menu[len], charsmax(menu)-len, "^n\r0. \w退出")
    keys |= MENU_KEY_0

    show_menu(id, keys, menu, -1, "hns_main")
}

public HandleMainMenu(id, key) {
    switch (key) {
        case 0: { // Join Game
            if (is_user_alive(id)) {
                client_print(id, print_chat, "[游戏] 你已经在游戏中！")
                return PLUGIN_HANDLED
            }
            new team = random_num(1, 2)
            cs_set_user_team(id, team == 1 ? CS_TEAM_T : CS_TEAM_CT)
            if (team == 2)
                cs_set_user_model(id, "urban")
            else
                cs_set_user_model(id, "terror")
            dllfunc(DLLFunc_Spawn, id)    // FIX: replaced ExecuteHamB for AMXX 1.82 compat
            client_print(id, print_chat, "[游戏] 你已加入 %s 方！", team == 1 ? "T" : "CT")
        }
        case 1: ShowShopMenu(id)
        case 2: ShowLicMainMenu(id)
        case 3: ShowRules(id)
        case 4: {
            if (!(get_user_flags(id) & ADMIN_LEVEL_A)) {
                client_print(id, print_chat, "[菜单] 此功能仅限VIP。")
                return PLUGIN_HANDLED
            }
            client_print(id, print_chat, "[投票] 投票换图功能暂未开放。")
        }
        case 6: ShowMuteMenu(id)
        case 7: {
            if (!(get_user_flags(id) & ADMIN_BAN)) return PLUGIN_HANDLED
            ShowAdminMenu(id)
        }
    }
    return PLUGIN_HANDLED
}

// ======================================================================
// Rules
// ======================================================================
ShowRules(id) {
    new motd[2048], len
    len = formatex(motd, charsmax(motd), "<body bgcolor='#111'><font color='#0f0' face='Arial'>")
    len += formatex(motd[len], charsmax(motd)-len, "<h2>捉迷藏规则</h2>")
    len += formatex(motd[len], charsmax(motd)-len, "<b>CT(搜寻者):</b><br>")
    len += formatex(motd[len], charsmax(motd)-len, "- 仅近战武器可造成伤害<br>")
    len += formatex(motd[len], charsmax(motd)-len, "- 连败3回合自动获得轻刀<br><br>")
    len += formatex(motd[len], charsmax(motd)-len, "<b>T(躲藏者):</b><br>")
    len += formatex(motd[len], charsmax(motd)-len, "- 近战无法造成伤害<br>")
    len += formatex(motd[len], charsmax(motd)-len, "- 可使用所有投掷物<br>")
    len += formatex(motd[len], charsmax(motd)-len, "- 无法使用主/副武器<br><br>")
    len += formatex(motd[len], charsmax(motd)-len, "<b>商店:</b> E键 或 /hxhns 打开菜单<br>")
    len += formatex(motd[len], charsmax(motd)-len, "<b>许可证:</b> 每30分钟在线获得1张<br>")
    len += formatex(motd[len], charsmax(motd)-len, "</font></body>")
    show_motd(id, motd, "捉迷藏规则")
}

// ======================================================================
// Shop Menu
// ======================================================================
ShowShopMenu(id) {
    new menu[1024], len, keys
    new team = _:cs_get_user_team(id)        // FIX: store as int
    new Float:now = get_gametime()
    new totalMoney = g_iRoundMoney[id] + g_iStoredMoney[id]

    len = formatex(menu[len], charsmax(menu)-len, "\y【 商店 】 \w金额: \g$%d \w许可证: \g%d^n^n", totalMoney, g_iLicenses[id])

    // 1. 补血包
    new Float:medCD = g_flMedkitCD[id] - now
    if (medCD > 0.0)
        len += formatex(menu[len], charsmax(menu)-len, "\d1. 补血包 [CD:%.0fs] ($3000)^n", medCD)
    else if (totalMoney < 3000)
        len += formatex(menu[len], charsmax(menu)-len, "\d1. 补血包 \r(金钱不足) \d($3000)^n")
    else {
        len += formatex(menu[len], charsmax(menu)-len, "\w1. 补血包 \y($3000)^n")
        keys |= MENU_KEY_1
    }

    // 2. 千里眼
    if (g_bClairvoyanceRound[id])
        len += formatex(menu[len], charsmax(menu)-len, "\d2. 千里眼 [已购买] ($4000)^n")
    else if (totalMoney < 4000)
        len += formatex(menu[len], charsmax(menu)-len, "\d2. 千里眼 \r(金钱不足) \d($4000)^n")
    else {
        len += formatex(menu[len], charsmax(menu)-len, "\w2. 千里眼 \y($4000)^n")
        keys |= MENU_KEY_2
    }

    // 3. 闪光弹
    new flashLimit = (team == _:CS_TEAM_T) ? 2 : 1
    new flashCost  = (team == _:CS_TEAM_T) ? 2000 : 10000
    new Float:flElapsed = now - g_flRoundStartTime
    new Float:flFlashCD = g_flFlashCD[id] - now
    if (g_iFlashBought[id] >= flashLimit)
        len += formatex(menu[len], charsmax(menu)-len, "\d3. 闪光弹 [上限] ($%d)^n", flashCost)
    else if (flElapsed > 10.0 && flFlashCD > 0.0)
        len += formatex(menu[len], charsmax(menu)-len, "\d3. 闪光弹 [CD:%.0fs] ($%d)^n", flFlashCD, flashCost)
    else if (totalMoney < flashCost)
        len += formatex(menu[len], charsmax(menu)-len, "\d3. 闪光弹 \r(金钱不足) \d($%d)^n", flashCost)
    else {
        len += formatex(menu[len], charsmax(menu)-len, "\w3. 闪光弹 \y($%d)^n", flashCost)
        keys |= MENU_KEY_3
    }

    // 4. 烟雾弹 (T only)
    if (team != _:CS_TEAM_T)
        len += formatex(menu[len], charsmax(menu)-len, "\d4. 烟雾弹 (仅T) ($3000)^n")
    else if (g_iSmokeBought[id] >= 1)
        len += formatex(menu[len], charsmax(menu)-len, "\d4. 烟雾弹 [上限] ($3000)^n")
    else if (totalMoney < 3000)
        len += formatex(menu[len], charsmax(menu)-len, "\d4. 烟雾弹 \r(金钱不足) \d($3000)^n")
    else {
        len += formatex(menu[len], charsmax(menu)-len, "\w4. 烟雾弹 \y($3000)^n")
        keys |= MENU_KEY_4
    }

    // 5. 高爆手雷 (T only)
    if (team != _:CS_TEAM_T)
        len += formatex(menu[len], charsmax(menu)-len, "\d5. 高爆手雷 (仅T) ($8000)^n")
    else if (totalMoney < 8000)
        len += formatex(menu[len], charsmax(menu)-len, "\d5. 高爆手雷 \r(金钱不足) \d($8000)^n")
    else {
        len += formatex(menu[len], charsmax(menu)-len, "\w5. 高爆手雷 \y($8000)^n")
        keys |= MENU_KEY_5
    }

    // 6. 轻功
    if (g_bKungFuActive[id])
        len += formatex(menu[len], charsmax(menu)-len, "\d6. 轻功 [生效中] ($6000)^n")
    else if (totalMoney < 6000)
        len += formatex(menu[len], charsmax(menu)-len, "\d6. 轻功 \r(金钱不足) \d($6000)^n")
    else {
        len += formatex(menu[len], charsmax(menu)-len, "\w6. 轻功 \y($6000) \d重力0.75 15s^n")
        keys |= MENU_KEY_6
    }

    // 7. 摔落伤害减免
    if (g_bFallShopActive[id])
        len += formatex(menu[len], charsmax(menu)-len, "\d7. 摔落减免 [生效中] ($7000)^n")
    else if (totalMoney < 7000)
        len += formatex(menu[len], charsmax(menu)-len, "\d7. 摔落减免 \r(金钱不足) \d($7000)^n")
    else {
        len += formatex(menu[len], charsmax(menu)-len, "\w7. 摔落减免 \y($7000) \d30s^n")
        keys |= MENU_KEY_7
    }

    // 8. 出售许可证
    if (g_iLicenses[id] >= 1) {
        len += formatex(menu[len], charsmax(menu)-len, "\w8. 出售许可证(+$1000)^n")
        keys |= MENU_KEY_8
    } else {
        len += formatex(menu[len], charsmax(menu)-len, "\d8. 出售许可证(无许可证)^n")
    }

    // 9. 许可证商店
    len += formatex(menu[len], charsmax(menu)-len, "\w9. 许可证商店^n")
    keys |= MENU_KEY_9

    len += formatex(menu[len], charsmax(menu)-len, "^n\r0. \w退出")
    keys |= MENU_KEY_0

    show_menu(id, keys, menu, -1, "hns_shop")
}

public HandleShopMenu(id, key) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED
    new team = _:cs_get_user_team(id)        // FIX: int
    new Float:now = get_gametime()
    new totalMoney = g_iRoundMoney[id] + g_iStoredMoney[id]

    switch (key) {
        case 0: { // 补血包
            if (totalMoney < 3000 || g_flMedkitCD[id] > now) { ShowShopMenu(id); return PLUGIN_HANDLED ;}
            SpendMoney(id, 3000)
            g_flMedkitCD[id] = now + 30.0
            set_user_health(id, minx(get_user_health(id) + 100, GetMaxHP(id)))
            client_print(id, print_chat, "[商店] 补血包购买成功！")
        }
        case 1: { // 千里眼
            if (totalMoney < 4000 || g_bClairvoyanceRound[id]) { ShowShopMenu(id); return PLUGIN_HANDLED ;}
            SpendMoney(id, 4000)
            g_bClairvoyanceRound[id] = 1
            client_print(id, print_chat, "[商店] 千里眼已开启 (15秒)！")
            new param[2]; param[0] = id; param[1] = 10
            Task_CVBeam(param)
        }
        case 2: { // 闪光弹
            new flashLimit = (team == _:CS_TEAM_T) ? 2 : 1
            new flashCost  = (team == _:CS_TEAM_T) ? 2000 : 10000
            new Float:flElapsed = now - g_flRoundStartTime
            if (g_iFlashBought[id] >= flashLimit || totalMoney < flashCost) { ShowShopMenu(id); return PLUGIN_HANDLED ;}
            if (flElapsed > 10.0 && g_flFlashCD[id] > now) { ShowShopMenu(id); return PLUGIN_HANDLED ;}
            SpendMoney(id, flashCost)
            g_iFlashBought[id]++
            give_item(id, "weapon_flashbang")
            if (flElapsed > 10.0) g_flFlashCD[id] = now + 60.0
            client_print(id, print_chat, "[商店] 闪光弹购买成功！")
        }
        case 3: { // 烟雾弹
            if (team != _:CS_TEAM_T || g_iSmokeBought[id] >= 1 || totalMoney < 3000) { ShowShopMenu(id); return PLUGIN_HANDLED; }
            SpendMoney(id, 3000)
            g_iSmokeBought[id]++
            give_item(id, "weapon_smokegrenade")
            client_print(id, print_chat, "[商店] 烟雾弹购买成功！")
        }
        case 4: { // HE
            if (team != _:CS_TEAM_T || totalMoney < 8000) { ShowShopMenu(id); return PLUGIN_HANDLED; }
            SpendMoney(id, 8000)
            give_item(id, "weapon_hegrenade")
            client_print(id, print_chat, "[商店] 高爆手雷购买成功！")
        }
        case 5: { // 轻功
            if (g_bKungFuActive[id] || totalMoney < 6000) { ShowShopMenu(id); return PLUGIN_HANDLED; }
            SpendMoney(id, 6000)
            g_bKungFuActive[id] = 1
            ApplyPlayerGravity(id)
            remove_task(TASK_KUNGFU + id)
            set_task(15.0, "Task_KungFuExpire", TASK_KUNGFU + id)
            client_print(id, print_chat, "[商店] 轻功已开启 (15秒)！")
        }
        case 6: { // 摔落减免
            if (g_bFallShopActive[id] || totalMoney < 7000) { ShowShopMenu(id); return PLUGIN_HANDLED; }
            SpendMoney(id, 7000)
            g_bFallShopActive[id] = 1
            remove_task(TASK_FALLSHOP + id)
            set_task(30.0, "Task_FallShopExpire", TASK_FALLSHOP + id)
            client_print(id, print_chat, "[商店] 摔落减免已开启 (30秒)！")
        }
        case 7: { // 出售许可证
            if (g_iLicenses[id] < 1) { ShowShopMenu(id); return PLUGIN_HANDLED; }
            g_iLicenses[id]--
            AddMoney(id, 1000)
            client_print(id, print_chat, "[商店] 出售1张许可证，获得 $1000！")
            SavePlayerData(id)
        }
        case 8: { // 许可证商店
            ShowLicMainMenu(id)
            return PLUGIN_HANDLED
        }
    }
    SyncMoney(id)
    ShowShopMenu(id)
    return PLUGIN_HANDLED
}

// ======================================================================
// License Menu - Main
// ======================================================================
ShowLicMainMenu(id) {
    g_bInLicMenu[id] = 1
    g_iLicPage[id] = LICPAGE_MAIN

    new menu[512], len, keys
    new team = getTeamIdx(id)
    new limitStr[16]
    if (g_iLicenseLimit < 0)
        formatex(limitStr, charsmax(limitStr), "unlimited")
    else
        formatex(limitStr, charsmax(limitStr), "%d", g_iLicenseLimit)

    len = formatex(menu[len], charsmax(menu)-len, "\yLicense Shop \rTeam(%d/%s)^n^n",
        g_iTeamLicUsed[team], limitStr)
    len += formatex(menu[len], charsmax(menu)-len, "\w1. Extra Speed (Team)^n")
    keys |= MENU_KEY_1
    len += formatex(menu[len], charsmax(menu)-len, "\w2. Max HP (Team)^n")
    keys |= MENU_KEY_2

    if (team == TEAM_T)
        len += formatex(menu[len], charsmax(menu)-len, "\w3. Faction: Flash (Team)^n")
    else
        len += formatex(menu[len], charsmax(menu)-len, "\w3. Faction: Light Knife (Team)^n")
    keys |= MENU_KEY_3

    len += formatex(menu[len], charsmax(menu)-len, "\w4. Fall Resist (Team)^n")
    keys |= MENU_KEY_4
    len += formatex(menu[len], charsmax(menu)-len, "\w5. Debuff Enemy AA (Team)^n")
    keys |= MENU_KEY_5
    len += formatex(menu[len], charsmax(menu)-len, "\w6. Superhuman (Self)^n")
    keys |= MENU_KEY_6
    len += formatex(menu[len], charsmax(menu)-len, "\w7. Low Gravity (Team)^n")
    keys |= MENU_KEY_7
    len += formatex(menu[len], charsmax(menu)-len, "\d8. (Reserved)^n")
    len += formatex(menu[len], charsmax(menu)-len, "^n\r0. \wExit")
    keys |= MENU_KEY_0

    show_menu(id, keys, menu, -1, "hns_licmain")
}

public HandleLicMain(id, key) {
    if (key == 9) {
        g_bInLicMenu[id] = 0
        return PLUGIN_HANDLED
    }
    if (key >= 0 && key <= 7) {
        g_iLicPage[id] = key + 1
        ShowLicSubPage(id, key + 1)
    }
    return PLUGIN_HANDLED
}

// ======================================================================
// License Menu - Sub Pages
// ======================================================================
ShowLicSubPage(id, page) {
    g_bInLicMenu[id] = 1
    g_iLicPage[id] = page

    new menu[512], len, keys
    new team = getTeamIdx(id)
    new limitStr[16]
    if (g_iLicenseLimit < 0)
        formatex(limitStr, charsmax(limitStr), "unlimited")
    else
        formatex(limitStr, charsmax(limitStr), "%d", g_iLicenseLimit)

    switch (page) {
        case LICPAGE_SPEED: {
            len = formatex(menu[len], charsmax(menu)-len, "\yExtra Speed (Team) \r(%d/%s)^n^n",
                g_iTeamLicUsed[team], limitStr)
            if (g_iTeamSpeedLv[team] >= 1)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. +5 Speed (Active)^n")
            else if (!CanTeamBuy(team, 5) || g_iLicenses[id] < 5)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. +5 Speed \r5 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w1. +5 Speed \y5 Lic^n")
                keys |= MENU_KEY_1
            }
            if (g_iTeamSpeedLv[team] >= 2)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. +10 Speed (Active)^n")
            else if (!CanTeamBuy(team, 12) || g_iLicenses[id] < 12)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. +10 Speed \r12 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w2. +10 Speed \y12 Lic^n")
                keys |= MENU_KEY_2
            }
        }
        case LICPAGE_MAXHP: {
            len = formatex(menu[len], charsmax(menu)-len, "\yMax HP (Team) \r(%d/%s)^n^n",
                g_iTeamLicUsed[team], limitStr)
            if (g_iTeamMaxHPLv[team] >= 1)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. HP 130 (Active)^n")
            else if (!CanTeamBuy(team, 5) || g_iLicenses[id] < 5)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. HP 130 \r5 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w1. HP 130 \y5 Lic^n")
                keys |= MENU_KEY_1
            }
            if (g_iTeamMaxHPLv[team] >= 2)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. HP 200 (Active)^n")
            else if (!CanTeamBuy(team, 12) || g_iLicenses[id] < 12)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. HP 200 \r12 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w2. HP 200 \y12 Lic^n")
                keys |= MENU_KEY_2
            }
        }
        case LICPAGE_ITEMS: {
            if (team == TEAM_T) {
                len = formatex(menu[len], charsmax(menu)-len, "\yFlash (Team) \r(%d/%s)^n^n",
                    g_iTeamLicUsed[team], limitStr)
                if (g_iTeamFlashLv[team] >= 1)
                    len += formatex(menu[len], charsmax(menu)-len, "\d1. x1 Flash (Active)^n")
                else if (!CanTeamBuy(team, 5) || g_iLicenses[id] < 5)
                    len += formatex(menu[len], charsmax(menu)-len, "\d1. x1 Flash \r5 Lic^n")
                else {
                    len += formatex(menu[len], charsmax(menu)-len, "\w1. x1 Flash \y5 Lic^n")
                    keys |= MENU_KEY_1
                }
                if (g_iTeamFlashLv[team] >= 2)
                    len += formatex(menu[len], charsmax(menu)-len, "\d2. x2 Flash (Active)^n")
                else if (!CanTeamBuy(team, 12) || g_iLicenses[id] < 12)
                    len += formatex(menu[len], charsmax(menu)-len, "\d2. x2 Flash \r12 Lic^n")
                else {
                    len += formatex(menu[len], charsmax(menu)-len, "\w2. x2 Flash \y12 Lic^n")
                    keys |= MENU_KEY_2
                }
            } else {
                len = formatex(menu[len], charsmax(menu)-len, "\yLight Knife (Team) \r(%d/%s)^n^n",
                    g_iTeamLicUsed[team], limitStr)
                if (g_iTeamLightKnifeLv[team] >= 1)
                    len += formatex(menu[len], charsmax(menu)-len, "\d1. Unlock Light Knife (Active)^n")
                else if (!CanTeamBuy(team, 5) || g_iLicenses[id] < 5)
                    len += formatex(menu[len], charsmax(menu)-len, "\d1. Unlock Light Knife \r5 Lic^n")
                else {
                    len += formatex(menu[len], charsmax(menu)-len, "\w1. Unlock Light Knife \y5 Lic^n")
                    keys |= MENU_KEY_1
                }
                if (g_iTeamLightKnifeLv[team] >= 2)
                    len += formatex(menu[len], charsmax(menu)-len, "\d2. Light Knife +2x Speed (Active)^n")
                else if (!CanTeamBuy(team, 12) || g_iLicenses[id] < 12)
                    len += formatex(menu[len], charsmax(menu)-len, "\d2. Light Knife +2x Speed \r12 Lic^n")
                else {
                    len += formatex(menu[len], charsmax(menu)-len, "\w2. Light Knife +2x Speed \y12 Lic^n")
                    keys |= MENU_KEY_2
                }
            }
        }
        case LICPAGE_FALL: {
            len = formatex(menu[len], charsmax(menu)-len, "\yFall Resist (Team) \r(%d/%s)^n^n",
                g_iTeamLicUsed[team], limitStr)
            if (g_iTeamFallLv[team] >= 1)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. Non-lethal max5/Lethal40 (Active)^n")
            else if (!CanTeamBuy(team, 8) || g_iLicenses[id] < 8)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. Non-lethal max5/Lethal40 \r8 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w1. Non-lethal max5/Lethal40 \y8 Lic^n")
                keys |= MENU_KEY_1
            }
            if (g_iTeamFallLv[team] >= 2)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. Immune Non-lethal/Lethal12 (Active)^n")
            else if (!CanTeamBuy(team, 15) || g_iLicenses[id] < 15)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. Immune Non-lethal/Lethal12 \r15 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w2. Immune Non-lethal/Lethal12 \y15 Lic^n")
                keys |= MENU_KEY_2
            }
        }
        case LICPAGE_ENEMYAA: {
            len = formatex(menu[len], charsmax(menu)-len, "\yEnemy AA (Team) \r(%d/%s)^n^n",
                g_iTeamLicUsed[team], limitStr)
            if (g_iTeamEnemyAALv[team] >= 1)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. Enemy AA=30 (Active)^n")
            else if (!CanTeamBuy(team, 5) || g_iLicenses[id] < 5)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. Enemy AA=30 \r5 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w1. Enemy AA=30 \y5 Lic^n")
                keys |= MENU_KEY_1
            }
            if (g_iTeamEnemyAALv[team] >= 2)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. Enemy AA=10+Fall Immune (Active)^n")
            else if (!CanTeamBuy(team, 15) || g_iLicenses[id] < 15)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. Enemy AA=10+Fall Immune \r15 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w2. Enemy AA=10+Fall Immune \y15 Lic^n")
                keys |= MENU_KEY_2
            }
        }
        case LICPAGE_SUPER: {
            len = formatex(menu[len], charsmax(menu)-len, "\ySuperhuman (Self) \r(%d/%s)^n^n",
                g_iTeamLicUsed[team], limitStr)
            if (g_iSuperhumanLv[id] >= 1)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. HP200+Spd+10+Grav0.875 (Active)^n")
            else if (!CanTeamBuy(team, 10) || g_iLicenses[id] < 10)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. HP200+Spd+10+Grav0.875 \r10 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w1. HP200+Spd+10+Grav0.875 \y10 Lic^n")
                keys |= MENU_KEY_1
            }
            if (g_iSuperhumanLv[id] >= 2)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. HP300+Spd+15+Grav0.75+NoFatigue (Active)^n")
            else if (g_iSuperhumanLv[id] < 1)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. Need Lv1 first^n")
            else if (!CanTeamBuy(team, 15) || g_iLicenses[id] < 15)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. HP300+Spd+15+Grav0.75+NoFatigue \r15 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w2. HP300+Spd+15+Grav0.75+NoFatigue \y15 Lic^n")
                keys |= MENU_KEY_2
            }
        }
        case LICPAGE_KUNGFU: {
            len = formatex(menu[len], charsmax(menu)-len, "\yLow Gravity (Team) \r(%d/%s)^n^n",
                g_iTeamLicUsed[team], limitStr)
            if (g_iTeamGravityLv[team] >= 1)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. Gravity 0.875 (Active)^n")
            else if (!CanTeamBuy(team, 8) || g_iLicenses[id] < 8)
                len += formatex(menu[len], charsmax(menu)-len, "\d1. Gravity 0.875 \r8 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w1. Gravity 0.875 \y8 Lic^n")
                keys |= MENU_KEY_1
            }
            if (g_iTeamGravityLv[team] >= 2)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. Gravity 0.75 (Active)^n")
            else if (!CanTeamBuy(team, 15) || g_iLicenses[id] < 15)
                len += formatex(menu[len], charsmax(menu)-len, "\d2. Gravity 0.75 \r15 Lic^n")
            else {
                len += formatex(menu[len], charsmax(menu)-len, "\w2. Gravity 0.75 \y15 Lic^n")
                keys |= MENU_KEY_2
            }
        }
    }

    len += formatex(menu[len], charsmax(menu)-len, "^n\r9. \wBack^n")
    keys |= MENU_KEY_9
    len += formatex(menu[len], charsmax(menu)-len, "\r0. \wExit")
    keys |= MENU_KEY_0

    show_menu(id, keys, menu, -1, "hns_licsub")
}

public HandleLicSub(id, key) {
    if (key == 9) {
        ShowLicMainMenu(id)
        return PLUGIN_HANDLED
    }
    if (key == 8) {                            // FIX: key 0 (position 9) is exit
        g_bInLicMenu[id] = 0
        return PLUGIN_HANDLED
    }

    new team = getTeamIdx(id)
    new page = g_iLicPage[id]
    new cost = 0
    new success = 0                            // FIX: use int, not bool

    switch (page) {
        case LICPAGE_SPEED: {
            if (key == 0) {
                cost = 5
                if (g_iTeamSpeedLv[team] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamSpeedLv[team] = 1
                    success = 1
                }
            } else if (key == 1) {
                cost = 12
                if (g_iTeamSpeedLv[team] < 2 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamSpeedLv[team] = 2
                    success = 1
                }
            }
            if (success) {
                g_iTeamLicUsed[team] += cost
                g_iLicenses[id] -= cost
                RefreshTeamSpeed(team)
                AnnounceTeamEffect(team, "Extra Speed active!")
            }
        }
        case LICPAGE_MAXHP: {
            if (key == 0) {
                cost = 5
                if (g_iTeamMaxHPLv[team] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamMaxHPLv[team] = 1
                    success = 1
                }
            } else if (key == 1) {
                cost = 12
                if (g_iTeamMaxHPLv[team] < 2 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamMaxHPLv[team] = 2
                    success = 1
                }
            }
            if (success) {
                g_iTeamLicUsed[team] += cost
                g_iLicenses[id] -= cost
                RefreshTeamHP(team)
                AnnounceTeamEffect(team, "Max HP upgraded!")
            }
        }
        case LICPAGE_ITEMS: {
            if (team == TEAM_T) {
                if (key == 0) {
                    cost = 5
                    if (g_iTeamFlashLv[team] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                        g_iTeamFlashLv[team] = 1
                        success = 1
                    }
                } else if (key == 1) {
                    cost = 12
                    if (g_iTeamFlashLv[team] < 2 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                        g_iTeamFlashLv[team] = 2
                        success = 1
                    }
                }
                if (success) {
                    g_iTeamLicUsed[team] += cost
                    g_iLicenses[id] -= cost
                    new count = (g_iTeamFlashLv[team] >= 2) ? 2 : 1
                    GiveTeamFlash(count)
                    AnnounceTeamEffect(team, "Flash delivered!")
                }
            } else {
                if (key == 0) {
                    cost = 5
                    if (g_iTeamLightKnifeLv[team] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                        g_iTeamLightKnifeLv[team] = 1
                        success = 1
                    }
                } else if (key == 1) {
                    cost = 12
                    if (g_iTeamLightKnifeLv[team] < 2 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                        g_iTeamLightKnifeLv[team] = 2
                        success = 1
                    }
                }
                if (success) {
                    g_iTeamLicUsed[team] += cost
                    g_iLicenses[id] -= cost
                    AnnounceTeamEffect(team, "Light Knife active!")
                }
            }
        }
        case LICPAGE_FALL: {
            if (key == 0) {
                cost = 8
                if (g_iTeamFallLv[team] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamFallLv[team] = 1
                    success = 1
                }
            } else if (key == 1) {
                cost = 15
                if (g_iTeamFallLv[team] < 2 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamFallLv[team] = 2
                    success = 1
                }
            }
            if (success) {
                g_iTeamLicUsed[team] += cost
                g_iLicenses[id] -= cost
                AnnounceTeamEffect(team, "Fall Resist active!")
            }
        }
        case LICPAGE_ENEMYAA: {
            if (key == 0) {
                cost = 5
                if (g_iTeamEnemyAALv[team] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamEnemyAALv[team] = 1
                    success = 1
                }
            } else if (key == 1) {
                cost = 15
                if (g_iTeamEnemyAALv[team] < 2 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamEnemyAALv[team] = 2
                    success = 1
                }
            }
            if (success) {
                g_iTeamLicUsed[team] += cost
                g_iLicenses[id] -= cost
                AnnounceTeamEffect(team, "Enemy AA debuffed!")
            }
        }
        case LICPAGE_SUPER: {
            if (key == 0) {
                cost = 10
                if (g_iSuperhumanLv[id] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iSuperhumanLv[id] = 1
                    success = 1
                }
            } else if (key == 1) {
                cost = 15
                if (g_iSuperhumanLv[id] == 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iSuperhumanLv[id] = 2
                    success = 1
                }
            }
            if (success) {
                g_iTeamLicUsed[team] += cost
                g_iLicenses[id] -= cost
                ApplySuperhuman(id)
                client_print(id, print_chat, "[License] Superhuman activated!")
            }
        }
        case LICPAGE_KUNGFU: {
            if (key == 0) {
                cost = 8
                if (g_iTeamGravityLv[team] < 1 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamGravityLv[team] = 1
                    success = 1
                }
            } else if (key == 1) {
                cost = 15
                if (g_iTeamGravityLv[team] < 2 && CanTeamBuy(team, cost) && g_iLicenses[id] >= cost) {
                    g_iTeamGravityLv[team] = 2
                    success = 1
                }
            }
            if (success) {
                g_iTeamLicUsed[team] += cost
                g_iLicenses[id] -= cost
                RefreshTeamGravity(team)
                AnnounceTeamEffect(team, "Low Gravity active!")
            }
        }
    }

    if (!success && cost > 0) {
        client_print(id, print_chat, "[License] Purchase failed!")
    }

    SavePlayerData(id)
    RefreshAllLicMenus()
    ShowLicSubPage(id, page)
    return PLUGIN_HANDLED
}

// ======================================================================
// License Helper Functions
// ======================================================================
CanTeamBuy(team, cost) {
    if (g_iLicenseLimit < 0) return 1            // unlimited
    if (g_iLicenseLimit == 0) return 0           // blocked
    return (g_iTeamLicUsed[team] + cost <= g_iLicenseLimit) ? 1 : 0  // FIX: return int not bool
}

AnnounceTeamEffect(team, const msg[]) {        // FIX: removed CsTeams: tag
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_connected(i) && getTeamIdx(i) == team)
            client_print(i, print_chat, "[License] %s", msg)
    }
}

RefreshAllLicMenus() {
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_connected(i) && g_bInLicMenu[i]) {
            if (g_iLicPage[i] == LICPAGE_MAIN)
                ShowLicMainMenu(i)
            else
                ShowLicSubPage(i, g_iLicPage[i])
        }
    }
}

GiveTeamFlash(count) {                         // FIX: removed CsTeams: tag
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_alive(i) && cs_get_user_team(i) == CS_TEAM_T) {
            for (new c = 0; c < count; c++)
                give_item(i, "weapon_flashbang")
        }
    }
}

// ======================================================================
// Admin Menu
// ======================================================================
ShowAdminMenu(id) {
    new menu[512], len, keys

    len = formatex(menu[len], charsmax(menu)-len, "\yAdmin Menu^n^n")
    len += formatex(menu[len], charsmax(menu)-len, "\w1. Set Round Time \d(Current: %ds)^n", get_cvar_num("mp_roundtime") * 60)
    keys |= MENU_KEY_1
    len += formatex(menu[len], charsmax(menu)-len, "\w2. Set Freeze Time \d(Current: %ds)^n", g_iFreezeTime)
    keys |= MENU_KEY_2
    len += formatex(menu[len], charsmax(menu)-len, "\w3. Collision Mode^n")
    keys |= MENU_KEY_3
    len += formatex(menu[len], charsmax(menu)-len, "\w4. Spawn Protection^n")
    keys |= MENU_KEY_4
    len += formatex(menu[len], charsmax(menu)-len, "\w5. License Team Limit^n")
    keys |= MENU_KEY_5
    len += formatex(menu[len], charsmax(menu)-len, "^n\r0. \wExit")
    keys |= MENU_KEY_0

    show_menu(id, keys, menu, -1, "hns_admin")
}

public HandleAdminMenu(id, key) {
    switch (key) {
        case 0: ShowAdmRoundTime(id)
        case 1: ShowAdmFreeze(id)
        case 2: ShowAdmCollision(id)
        case 3: ShowAdmProtect(id)
        case 4: ShowAdmLimit(id)
    }
    return PLUGIN_HANDLED
}

ShowAdmRoundTime(id) {
    new menu[512], len, keys
    len = formatex(menu[len], charsmax(menu)-len, "\yRound Time^n^n")
    len += formatex(menu[len], charsmax(menu)-len, "\w1. 3 min^n")
    keys |= MENU_KEY_1
    len += formatex(menu[len], charsmax(menu)-len, "\w2. 5 min^n")
    keys |= MENU_KEY_2
    len += formatex(menu[len], charsmax(menu)-len, "\w3. 8 min^n")
    keys |= MENU_KEY_3
    len += formatex(menu[len], charsmax(menu)-len, "\w4. 10 min^n")
    keys |= MENU_KEY_4
    len += formatex(menu[len], charsmax(menu)-len, "^n\r9. \wBack^n")
    keys |= MENU_KEY_9
    len += formatex(menu[len], charsmax(menu)-len, "\r0. \wExit")
    keys |= MENU_KEY_0
    show_menu(id, keys, menu, -1, "hns_adm_rtime")
}

public HandleAdmRoundTime(id, key) {
    if (key == 9) { ShowAdminMenu(id); return PLUGIN_HANDLED; }
    if (key == 8) return PLUGIN_HANDLED
    new times[4]
    times[0] = 3; times[1] = 5; times[2] = 8; times[3] = 10   // FIX: avoid initializer list
    if (key >= 0 && key <= 3) {
        server_cmd("mp_roundtime %d", times[key])
        client_print(id, print_console, "[Admin] Round time: %d min (+%ds freeze)", times[key], g_iFreezeTime)
    }
    ShowAdmRoundTime(id)
    return PLUGIN_HANDLED
}

ShowAdmFreeze(id) {
    new menu[512], len, keys
    len = formatex(menu[len], charsmax(menu)-len, "\yFreeze Time^n^n")
    len += formatex(menu[len], charsmax(menu)-len, "\w1. No freeze^n")
    keys |= MENU_KEY_1
    len += formatex(menu[len], charsmax(menu)-len, "\w2. 5 sec^n")
    keys |= MENU_KEY_2
    len += formatex(menu[len], charsmax(menu)-len, "\w3. 10 sec^n")
    keys |= MENU_KEY_3
    len += formatex(menu[len], charsmax(menu)-len, "\w4. 30 sec^n")
    keys |= MENU_KEY_4
    len += formatex(menu[len], charsmax(menu)-len, "\w5. Custom^n")
    keys |= MENU_KEY_5
    len += formatex(menu[len], charsmax(menu)-len, "^n\r9. \wBack^n")
    keys |= MENU_KEY_9
    len += formatex(menu[len], charsmax(menu)-len, "\r0. \wExit")
    keys |= MENU_KEY_0
    show_menu(id, keys, menu, -1, "hns_adm_freeze")
}

public HandleAdmFreeze(id, key) {
    if (key == 9) { ShowAdminMenu(id); return PLUGIN_HANDLED ;}
    if (key == 8) return PLUGIN_HANDLED
    new times[4]
    times[0] = 0; times[1] = 5; times[2] = 10; times[3] = 30  // FIX: avoid initializer list
    if (key >= 0 && key <= 3) {
        g_iFreezeTime = times[key]
        set_cvar_num("hns_freezetime", times[key])
        client_print(id, print_console, "[Admin] Freeze time: %d sec", times[key])
    } else if (key == 4) {
        client_cmd(id, "messagemode hns_freezetime")
    }
    ShowAdmFreeze(id)
    return PLUGIN_HANDLED
}

public Cmd_SetFreezeTime(id, level, cid) {
    if (!cmd_access(id, level, cid, 2)) return PLUGIN_HANDLED
    new arg[16]
    read_argv(1, arg, charsmax(arg))
    new val = str_to_num(arg)
    if (val < 0) val = 0
    if (val > 120) val = 120
    g_iFreezeTime = val
    set_cvar_num("hns_freezetime", val)
    client_print(id, print_console, "[Admin] Freeze time: %d sec", val)
    return PLUGIN_HANDLED
}

ShowAdmCollision(id) {
    new menu[512], len, keys
    len = formatex(menu[len], charsmax(menu)-len, "\yCollision Mode^n^n")
    if (g_iCollisionMode == 1) {
        len += formatex(menu[len], charsmax(menu)-len, "\r1. Teammate no collision^n")
        len += formatex(menu[len], charsmax(menu)-len, "\w2. All players collide^n")
    } else {
        len += formatex(menu[len], charsmax(menu)-len, "\w1. Teammate no collision^n")
        len += formatex(menu[len], charsmax(menu)-len, "\r2. All players collide^n")
    }
    keys |= MENU_KEY_1
    keys |= MENU_KEY_2
    len += formatex(menu[len], charsmax(menu)-len, "^n\r9. \wBack^n")
    keys |= MENU_KEY_9
    len += formatex(menu[len], charsmax(menu)-len, "\r0. \wExit")
    keys |= MENU_KEY_0
    show_menu(id, keys, menu, -1, "hns_adm_coll")
}

public HandleAdmCollision(id, key) {
    if (key == 9) { ShowAdminMenu(id); return PLUGIN_HANDLED; }
    if (key == 8) return PLUGIN_HANDLED
    if (key == 0) g_iCollisionMode = 1
    else if (key == 1) g_iCollisionMode = 2
    ShowAdmCollision(id)
    return PLUGIN_HANDLED
}

ShowAdmProtect(id) {
    new menu[512], len, keys
    len = formatex(menu[len], charsmax(menu)-len, "\ySpawn Protection^n^n")
    len += formatex(menu[len], charsmax(menu)-len, "\w1. Protected^n")
    keys |= MENU_KEY_1
    len += formatex(menu[len], charsmax(menu)-len, "\w2. No protect + heal on unfreeze^n")
    keys |= MENU_KEY_2
    len += formatex(menu[len], charsmax(menu)-len, "\w3. No protection^n")
    keys |= MENU_KEY_3
    len += formatex(menu[len], charsmax(menu)-len, "^n\r9. \wBack^n")
    keys |= MENU_KEY_9
    len += formatex(menu[len], charsmax(menu)-len, "\r0. \wExit")
    keys |= MENU_KEY_0
    show_menu(id, keys, menu, -1, "hns_adm_prot")
}

public HandleAdmProtect(id, key) {
    if (key == 9) { ShowAdminMenu(id); return PLUGIN_HANDLED;}
    if (key == 8) return PLUGIN_HANDLED
    if (key >= 0 && key <= 2) g_iSpawnProtect = key + 1
    ShowAdmProtect(id)
    return PLUGIN_HANDLED
}

ShowAdmLimit(id) {
    new menu[512], len, keys
    len = formatex(menu[len], charsmax(menu)-len, "\yLicense Team Limit^n^n")
    len += formatex(menu[len], charsmax(menu)-len, "\w1. 20^n")
    keys |= MENU_KEY_1
    len += formatex(menu[len], charsmax(menu)-len, "\w2. 30^n")
    keys |= MENU_KEY_2
    len += formatex(menu[len], charsmax(menu)-len, "\w3. 50^n")
    keys |= MENU_KEY_3
    len += formatex(menu[len], charsmax(menu)-len, "\w4. Unlimited^n")
    keys |= MENU_KEY_4
    len += formatex(menu[len], charsmax(menu)-len, "\w5. 0^n")
    keys |= MENU_KEY_5
    len += formatex(menu[len], charsmax(menu)-len, "^n\r9. \wBack^n")
    keys |= MENU_KEY_9
    len += formatex(menu[len], charsmax(menu)-len, "\r0. \wExit")
    keys |= MENU_KEY_0
    show_menu(id, keys, menu, -1, "hns_adm_limit")
}

public HandleAdmLimit(id, key) {
    if (key == 9) { ShowAdminMenu(id); return PLUGIN_HANDLED ;}
    if (key == 8) return PLUGIN_HANDLED
    new limits[5]
    limits[0] = 20; limits[1] = 30; limits[2] = 50; limits[3] = -1; limits[4] = 0  // FIX: avoid initializer
    if (key >= 0 && key <= 4) {
        g_iLicenseLimit = limits[key]
        set_cvar_num("hns_license_limit", limits[key])
        client_print(id, print_console, "[Admin] License limit: %d", limits[key])
    }
    ShowAdmLimit(id)
    return PLUGIN_HANDLED
}

public Cmd_SetLicenseLimit(id, level, cid) {
    if (!cmd_access(id, level, cid, 2)) return PLUGIN_HANDLED
    new arg[16]
    read_argv(1, arg, charsmax(arg))
    g_iLicenseLimit = str_to_num(arg)
    set_cvar_num("hns_license_limit", g_iLicenseLimit)
    return PLUGIN_HANDLED
}

// ======================================================================
// Mute Menu
// ======================================================================
ShowMuteMenu(id) {
    new menu[512], len, keys
    len = formatex(menu[len], charsmax(menu)-len, "\yMute Player^n^n")
    new count = 0
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (!is_user_connected(i) || i == id) continue
        count++
        new name[32]
        get_user_name(i, name, charsmax(name))
        if (g_bMuted[id][i])
            len += formatex(menu[len], charsmax(menu)-len, "\d%d. %s [Muted]^n", count, name)
        else {
            len += formatex(menu[len], charsmax(menu)-len, "\w%d. %s^n", count, name)
            keys |= (1 << (count - 1))
        }
        if (count >= 9) break
    }
    len += formatex(menu[len], charsmax(menu)-len, "^n\r0. \wExit")
    keys |= MENU_KEY_0
    show_menu(id, keys, menu, -1, "hns_mute")
}

public HandleMuteMenu(id, key) {
    if (key == 9) return PLUGIN_HANDLED
    new idx = 0
    new target = 0
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (!is_user_connected(i) || i == id) continue
        idx++
        if (idx == key + 1) { target = i; break ;}
    }
    if (target > 0) {
        g_bMuted[id][target] = g_bMuted[id][target] ? 0 : 1   // FIX: no bool negation
        new name[32]
        get_user_name(target, name, charsmax(name))
        client_print(id, print_chat, "[Voice] %s %s", name, g_bMuted[id][target] ? "muted" : "unmuted")
    }
    ShowMuteMenu(id)
    return PLUGIN_HANDLED
}

// ======================================================================
// Money System
// ======================================================================
AddMoney(id, amount) {
    g_iRoundMoney[id] += amount
    SyncMoney(id)
}

SpendMoney(id, amount) {
    if (g_iRoundMoney[id] >= amount) {
        g_iRoundMoney[id] -= amount
    } else {
        new remaining = amount - g_iRoundMoney[id]
        g_iRoundMoney[id] = 0
        g_iStoredMoney[id] -= remaining
        if (g_iStoredMoney[id] < 0) g_iStoredMoney[id] = 0
    }
    SyncMoney(id)
}

GiveTeamMoney(team, amount) {                  // FIX: removed CsTeams: tag
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_connected(i) && getTeamIdx(i) == team) {
            g_iStoredMoney[i] += g_iRoundMoney[i] + amount
            g_iRoundMoney[i] = 0
            SyncMoney(i)
        }
    }
}

SyncMoney(id) {
    if (!is_user_connected(id)) return
    new total = g_iRoundMoney[id] + g_iStoredMoney[id]
    cs_set_user_money(id, (total > 16000) ? 16000 : total, 1)
}

// ======================================================================
// Speed System
// ======================================================================
UpdatePlayerSpeed(id) {
    if (g_bFrozen[id]) {
        set_pev(id, pev_maxspeed, 0.0)
        return
    }

    new weapon = get_user_weapon(id)
    new Float:baseSpeed = 250.0

    switch (weapon) {
        case CSW_AWP: baseSpeed = 210.0
        case CSW_SCOUT: baseSpeed = 260.0
        case CSW_SG550: baseSpeed = 210.0       // FIX: split multi-case for 1.82
        case CSW_G3SG1: baseSpeed = 210.0
    }

    new team = getTeamIdx(id)
    new Float:bonus = 0.0

    if (team == TEAM_T || team == TEAM_CT) {
        if (g_iTeamSpeedLv[team] >= 2) bonus += 10.0
        else if (g_iTeamSpeedLv[team] >= 1) bonus += 5.0
    }

    if (g_iSuperhumanLv[id] >= 2) bonus += 15.0
    else if (g_iSuperhumanLv[id] >= 1) bonus += 10.0

    set_pev(id, pev_maxspeed, baseSpeed + bonus)
}

RefreshTeamSpeed(team) {
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_alive(i) && getTeamIdx(i) == team)
            UpdatePlayerSpeed(i)
    }
}

// ======================================================================
// HP System
// ======================================================================
GetMaxHP(id) {
    new team = getTeamIdx(id)
    new maxhp = 100

    if (team == TEAM_T || team == TEAM_CT) {
        if (g_iTeamMaxHPLv[team] >= 2) maxhp = 200
        else if (g_iTeamMaxHPLv[team] >= 1) maxhp = 130
    }

    if (g_iSuperhumanLv[id] >= 2) maxhp = 300
    else if (g_iSuperhumanLv[id] >= 1) maxhp = maxx(maxhp, 200)

    return maxhp
}

ApplyTeamHP(id, team) {
    new maxhp = GetMaxHP(id)
    set_user_health(id, maxhp)
    team = team ; // FIX: suppress unused warning (parameter kept for API consistency)
}

RefreshTeamHP(team) {
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_alive(i) && getTeamIdx(i) == team) {
            new maxhp = GetMaxHP(i)
            if (get_user_health(i) > maxhp)
                set_user_health(i, maxhp)
        }
    }
}

// ======================================================================
// Gravity System
// ======================================================================
ApplyPlayerGravity(id) {
    new team = getTeamIdx(id)
    new Float:grav = 1.0

    if (team == TEAM_T || team == TEAM_CT) {
        if (g_iTeamGravityLv[team] >= 2) grav = 0.75
        else if (g_iTeamGravityLv[team] >= 1) grav = 0.875
    }

    if (g_bKungFuActive[id] && grav > 0.75) grav = 0.75    // FIX: avoid floatmin tag issue
    if (g_iSuperhumanLv[id] >= 2 && grav > 0.75) grav = 0.75
    else if (g_iSuperhumanLv[id] >= 1 && grav > 0.875) grav = 0.875

    set_pev(id, pev_gravity, grav)
}

RefreshTeamGravity(team) {
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_alive(i) && getTeamIdx(i) == team)
            ApplyPlayerGravity(i)
    }
}

// ======================================================================
// Superhuman
// ======================================================================
ApplySuperhuman(id) {
    if (!is_user_alive(id)) return
    new maxhp = GetMaxHP(id)
    set_user_health(id, maxhp)
    ApplyPlayerGravity(id)
    UpdatePlayerSpeed(id)
}

// ======================================================================
// Collision System
// ======================================================================
ManageCollision(id) {
    if (!is_user_alive(id)) return

    if (g_iCollisionMode == 1) {
        new myTeam = cs_get_user_team(id)
        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (i != id && is_user_alive(i)) {
                if (cs_get_user_team(i) == myTeam)
                    set_pev(i, pev_solid, SOLID_NOT)
                else
                    set_pev(i, pev_solid, SOLID_SLIDEBOX)
            }
        }
    }
}

// ======================================================================
// Enemy AA Management
// ======================================================================
ManageEnemyAA(id) {
    new myTeam = getTeamIdx(id)
    if (myTeam < 0) return

    new enemyTeam = 1 - myTeam
    if (g_iTeamEnemyAALv[enemyTeam] >= 1) {
        new Float:aa = (g_iTeamEnemyAALv[enemyTeam] >= 2) ? 10.0 : 30.0
        if (!(pev(id, pev_flags) & FL_ONGROUND)) {
            set_cvar_float("sv_airaccelerate", aa)
        }
    }
}

// ======================================================================
// Fall Damage Level
// ======================================================================
GetFallResistLevel(id) {
    new team = getTeamIdx(id)
    new level = 0

    if (g_bFallShopActive[id]) level = maxx(level, 1)

    if (team == TEAM_T || team == TEAM_CT) {
        if (g_iTeamFallLv[team] >= 2) level = maxx(level, 2)
        else if (g_iTeamFallLv[team] >= 1) level = maxx(level, 1)
    }

    return level
}

// ======================================================================
// Clairvoyance Effect
// ======================================================================
public Task_CVBeam(param[2]) {
    new id = param[0]
    new count = param[1]

    if (!is_user_alive(id)) return
    if (count == 0) return

    new myTeam = _:cs_get_user_team(id)        // FIX: store as int
    new enemyTag[4]
    if (myTeam == _:CS_TEAM_T)
        copy(enemyTag, 3, "CT")
    else
        copy(enemyTag, 3, "T")

    new players[32], num
    get_players(players, num, "ae", enemyTag)

    for (new i = 0; i < num; i++) {
        new enemy = players[i]
        if (!is_user_alive(enemy)) continue
        message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id)
        write_byte(TE_BEAMENTS)
        write_short(id)
        write_short(enemy)
        write_short(g_sBeamSprite)
        write_byte(0)   // start frame
        write_byte(15)  // framerate
        write_byte(15)  // life (1.5s)
        write_byte(8)   // width
        write_byte(0)   // noise
        write_byte(0)   // R
        write_byte(255) // G
        write_byte(0)   // B
        write_byte(120) // alpha
        write_byte(0)   // speed
        message_end()
    }

    new nextParam[2]
    nextParam[0] = id
    nextParam[1] = (count == -1) ? -1 : count - 1
    set_task(1.5, "Task_CVBeam", TASK_CLAIRVOYANCE + id, nextParam, 2)
}

// ======================================================================
// Shop Task Callbacks
// ======================================================================
public Task_KungFuExpire(taskID) {
    new id = taskID - TASK_KUNGFU
    if (!is_user_connected(id)) return
    g_bKungFuActive[id] = 0
    ApplyPlayerGravity(id)
    client_print(id, print_chat, "[Shop] Kung Fu expired.")
}

public Task_FallShopExpire(taskID) {
    new id = taskID - TASK_FALLSHOP
    if (!is_user_connected(id)) return
    g_bFallShopActive[id] = 0
    client_print(id, print_chat, "[Shop] Fall Resist expired.")
}

// ======================================================================
// Periodic Tasks
// ======================================================================
public Task_PlayTime() {
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (!is_user_connected(i)) continue
        g_iPlayTimeSec[i]++
        if (g_iPlayTimeSec[i] >= PLAYTIME_PER_LICENSE) {
            g_iPlayTimeSec[i] = 0
            AddLicense(i, 1)
            client_print(i, print_chat, "[License] 30 min online: +1 License!")
            SavePlayerData(i)
        }
    }
}

public Task_Survival() {
    new Float:now = get_gametime()
    if (now - g_flLastSurvivalTick >= 60.0) {
        g_flLastSurvivalTick = now
        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (is_user_alive(i) && cs_get_user_team(i) == CS_TEAM_T) {
                AddMoney(i, 500)
                client_print(i, print_chat, "[Shop] Survival bonus +$500!")
            }
        }
    }
}

// ======================================================================
// License Display (round start)
// ======================================================================
public Task_LicDisplay() {
    for (new t = 0; t < 2; t++) {
        new limitStr[16]
        if (g_iLicenseLimit < 0)
            formatex(limitStr, charsmax(limitStr), "Inf")
        else if (g_iLicenseLimit == 0)
            formatex(limitStr, charsmax(limitStr), "Off")
        else
            formatex(limitStr, charsmax(limitStr), "%d", g_iLicenseLimit)

        for (new i = 1; i <= g_iMaxPlayers; i++) {
            if (is_user_connected(i) && getTeamIdx(i) == t) {
                set_hudmessage(255, 200, 0, -1.0, 0.15, 0, 0.0, 1.2, 0.0, 0.0, 3)
                show_hudmessage(i, "Team License: %d/%s", g_iTeamLicUsed[t], limitStr)
            }
        }
    }
}

// ======================================================================
// HUD Display
// ======================================================================
public Task_HUD() {
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (!is_user_alive(i) || !is_user_connected(i)) continue

        set_hudmessage(100, 200, 50, 0.75, 0.85, 0, 0.0, 1.2, 0.0, 0.0, 1)
        show_hudmessage(i, "Round: $%d^nStored: $%d^nLicense: %d",
            g_iRoundMoney[i], g_iStoredMoney[i], g_iLicenses[i])

        new Float:vel[3]
        pev(i, pev_velocity, vel)
        new Float:speed = floatsqroot(vel[0] * vel[0] + vel[1] * vel[1])
        set_hudmessage(255, 255, 255, -1.0, 0.55, 0, 0.0, 1.2, 0.0, 0.0, 2)
        show_hudmessage(i, "Speed: %.0f", speed)
    }
}

// ======================================================================
// License Helpers
// ======================================================================
AddLicense(id, amount) {
    g_iLicenses[id] += amount
    SavePlayerData(id)
}

// ======================================================================
// License Bonus (differential)
// ======================================================================
CalcLicenseBonus(ctWon) {                      // FIX: plain int parameter
    new winnerIdx, loserIdx

    if (ctWon) {
        winnerIdx = TEAM_CT
        loserIdx = TEAM_T
    } else {
        winnerIdx = TEAM_T
        loserIdx = TEAM_CT
    }

    new winnerUsed = g_iTeamLicUsed[winnerIdx]  // FIX: direct index, no tag math
    new loserUsed  = g_iTeamLicUsed[loserIdx]

    new bonus = 0
    new unlimitedBonus = 0

    if (winnerUsed < loserUsed) {
        bonus = loserUsed - winnerUsed
        if (winnerUsed == 0 && loserUsed > 0) {
            unlimitedBonus = 1
        } else {
            bonus = minx(bonus, 3)
        }
    }

    if (bonus <= 0) return

    if (unlimitedBonus) {
        new count = 0
        if (winnerIdx == TEAM_CT) {
            new sorted[33]
            new sortedKills[33]
            for (new i = 1; i <= g_iMaxPlayers; i++) {
                if (is_user_connected(i) && getTeamIdx(i) == winnerIdx) {
                    sorted[count] = i
                    sortedKills[count] = g_iRoundKills[i]
                    count++
                }
            }
            for (new a = 0; a < count - 1; a++) {
                for (new b = a + 1; b < count; b++) {
                    if (sortedKills[b] > sortedKills[a]) {
                        new tmp = sorted[a]
                        sorted[a] = sorted[b]
                        sorted[b] = tmp
                        tmp = sortedKills[a]
                        sortedKills[a] = sortedKills[b]
                        sortedKills[b] = tmp
                    }
                }
            }
            if (count > 0) {
                new perPlayer = bonus / count
                new remainder = bonus % count
                for (new i = 0; i < count; i++) {
                    new amt = perPlayer + (i < remainder ? 1 : 0)
                    if (amt > 0) {
                        AddLicense(sorted[i], amt)
                        client_print(sorted[i], print_chat, "[License] Bonus +%d!", amt)
                    }
                }
            }
        } else {
            for (new i = 1; i <= g_iMaxPlayers; i++) {
                if (is_user_alive(i) && getTeamIdx(i) == winnerIdx)
                    count++
            }
            if (count > 0) {
                new perPlayer = bonus / count
                new remainder = bonus % count
                new assigned = 0
                for (new i = 1; i <= g_iMaxPlayers; i++) {
                    if (is_user_alive(i) && getTeamIdx(i) == winnerIdx) {
                        new amt = perPlayer + (assigned < remainder ? 1 : 0)
                        if (amt > 0) {
                            AddLicense(i, amt)
                            client_print(i, print_chat, "[License] Bonus +%d!", amt)
                        }
                        assigned++
                    }
                }
            }
        }
    } else {
        if (winnerIdx == TEAM_CT) {
            new sorted[33]
            new sortedKills[33]
            new count = 0
            for (new i = 1; i <= g_iMaxPlayers; i++) {
                if (is_user_connected(i) && getTeamIdx(i) == winnerIdx) {
                    sorted[count] = i
                    sortedKills[count] = g_iRoundKills[i]
                    count++
                }
            }
            for (new a = 0; a < count - 1; a++) {
                for (new b = a + 1; b < count; b++) {
                    if (sortedKills[b] > sortedKills[a]) {
                        new tmp = sorted[a]
                        sorted[a] = sorted[b]
                        sorted[b] = tmp
                        tmp = sortedKills[a]
                        sortedKills[a] = sortedKills[b]
                        sortedKills[b] = tmp
                    }
                }
            }
            for (new i = 0; i < bonus && i < count; i++) {
                AddLicense(sorted[i], 1)
                client_print(sorted[i], print_chat, "[License] Bonus +1!")
            }
        } else {
            new count = 0
            for (new i = 1; i <= g_iMaxPlayers; i++) {
                if (is_user_alive(i) && getTeamIdx(i) == winnerIdx)
                    count++
            }
            if (count > 0) {
                new assigned = 0
                for (new i = 1; i <= g_iMaxPlayers && assigned < bonus; i++) {
                    if (is_user_alive(i) && getTeamIdx(i) == winnerIdx) {
                        AddLicense(i, 1)
                        client_print(i, print_chat, "[License] Bonus +1!")
                        assigned++
                    }
                }
            }
        }
    }
}

// ======================================================================
// Utility: Count Players
// ======================================================================
CountAlive(team) {                             // FIX: removed CsTeams: tag
    new count = 0
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_alive(i) && getTeamIdx(i) == team) count++
    }
    return count
}

CountTotal(team) {                             // FIX: removed CsTeams: tag
    new count = 0
    for (new i = 1; i <= g_iMaxPlayers; i++) {
        if (is_user_connected(i) && getTeamIdx(i) == team) count++
    }
    return count
}

// ======================================================================
// Block Buy
// ======================================================================
public Cmd_BlockBuy(id) {
    return PLUGIN_HANDLED
}

// ======================================================================
// nvault Save / Load
// ======================================================================
SavePlayerData(id) {
    if (!is_user_connected(id)) return
    new authid[35]
    get_user_authid(id, authid, charsmax(authid))
    new data[128]
    formatex(data, charsmax(data), "%d %d %d",
        g_iStoredMoney[id], g_iLicenses[id], g_iPlayTimeSec[id])
    nvault_set(g_vault, authid, data)
}

LoadPlayerData(id) {
    new authid[35]
    get_user_authid(id, authid, charsmax(authid))
    new data[128]
    new len
    if (nvault_lookup(g_vault, authid, data, charsmax(data), len)) {
        new sMoney[16], sLic[16], sTime[16]
        parse(data, sMoney, charsmax(sMoney), sLic, charsmax(sLic), sTime, charsmax(sTime))
        g_iStoredMoney[id] = str_to_num(sMoney)
        g_iLicenses[id] = str_to_num(sLic)
        g_iPlayTimeSec[id] = str_to_num(sTime)
    }
}
