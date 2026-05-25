#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <engine>
#include <hamsandwich>

#define PLUGIN "Hide and Seek Mod"
#define VERSION "1.0"
#define AUTHOR "AMXX Community"

#define FREEZE_TASKID 1000
#define CLAIRVOYANCE_TASKID 2000

// 玩家数据变量
new g_iMoney[33];
new bool:g_bFrozen[33];
new Float:g_flRoundStartTime;

// 商店CD与限制变量
new Float:g_flMedkitCD[33];
new bool:g_bClarivoyanceBought[33];
new Float:g_flFlashCD[33];
new g_iFlashBought[33];
new g_iSmokeBought[33];
new bool:g_bExtraHPBought[33];
new g_iSpeedBought[33];
new bool:g_bHasLightKnife[33];

// 缓存与Cvar
new g_sBeamSprite;
new g_pCvarFreezeTime;
new bool:g_bRoundFreezePeriod;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // 注册控制台变量 (默认冻结时间15秒，管理员可在amxx.cfg或控制台更改)
    g_pCvarFreezeTime = register_cvar("hns_ct_freezetime", "15.0");

    // 注册事件
    register_event("HLTV", "Event_HLTV", "a", "1=0", "2=0");
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");

    // 禁用标准购买指令，防止玩家绕过插件购买武器
    register_clcmd("buy", "BlockBuy");
    register_clcmd("buyammo1", "BlockBuy");
    register_clcmd("buyammo2", "BlockBuy");
    register_clcmd("cl_autobuy", "BlockBuy");
    register_clcmd("cl_rebuy", "BlockBuy");

    // Ham 注入
    RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn", 1);
    RegisterHam(Ham_TakeDamage, "player", "Ham_PlayerTakeDamage", 0);

    // 注册商店旧版菜单（兼容性最好）
    register_menu("ShopMenu", 1023, "HandleShopMenu");

    // 循环更新屏幕右下角个人资金HUD信息
    set_task(1.0, "HUD_MoneyThink", _, _, _, "b");
}

public plugin_precache() {
    // 预载千里眼效果的激光线精灵
    g_sBeamSprite = precache_model("sprites/laserbeam.spr");
}

public BlockBuy(id) {
    return PLUGIN_HANDLED;
}

// 每回合初始化阶段
public Event_HLTV() {
    g_bRoundFreezePeriod = true;
    g_flRoundStartTime = get_gametime();

    new Float:fFreezeTime = get_pcvar_float(g_pCvarFreezeTime);
    if (fFreezeTime < 1.0) fFreezeTime = 5.0;

    // 清除上局残留的千里眼任务
    for (new i = 1; i <= 32; i++) {
        remove_task(CLAIRVOYANCE_TASKID + i);
    }

    remove_task(FREEZE_TASKID);
    set_task(fFreezeTime, "UnfreezeCTs", FREEZE_TASKID);
}

// 玩家重生
public Ham_PlayerSpawn(id) {
    if (!is_user_alive(id)) return;

    // 重置玩家商店购买数据
    g_bClarivoyanceBought[id] = false;
    g_iFlashBought[id] = 0;
    g_iSmokeBought[id] = 0;
    g_bExtraHPBought[id] = false;
    g_iSpeedBought[id] = 0;
    g_bHasLightKnife[id] = false;
    g_flMedkitCD[id] = 0.0;
    g_flFlashCD[id] = 0.0;

    // 设定初始资金
    g_iMoney[id] = 10000;
    SyncClientMoney(id);

    // 开局冻结CT
    if (g_bRoundFreezePeriod && cs_get_user_team(id) == CS_TEAM_CT) {
        g_bFrozen[id] = true;
        set_pev(id, pev_movetype, MOVETYPE_NONE);

        new Float:vecZero[3] = {0.0, 0.0, 0.0};
        entity_set_vector(id, EV_VEC_velocity, vecZero);

        client_print(id, print_center, "你已被悬空冻结，请等待土匪躲藏完毕！");
    } else {
        g_bFrozen[id] = false;
    }
}

// 解冻CT
public UnfreezeCTs() {
    g_bRoundFreezePeriod = false;
    new players[32], num;
    get_players(players, num, "ae", "CT");

    for (new i = 0; i < num; i++) {
        new id = players[i];
        if (g_bFrozen[id]) {
            g_bFrozen[id] = false;
            set_pev(id, pev_movetype, MOVETYPE_WALK);
            client_print(id, print_center, "冻结解除，开始搜寻！");
        }
    }
}

// 伤害判定 (T近战无伤、HE伤害减免)
public Ham_PlayerTakeDamage(victim, inflictor, attacker, Float:damage, damagebits) {
    if (!is_user_connected(attacker) || !is_user_connected(victim))
        return HAM_IGNORED;

    new CsTeams:attackerTeam = cs_get_user_team(attacker);

    // 1、T方近战武器（小刀）不可造成伤害
    if (attackerTeam == CS_TEAM_T) {
        new weapon = get_user_weapon(attacker);
        if (weapon == CSW_KNIFE) {
            return HAM_SUPERCEDE;
        }
    }

    // 8、高爆手雷：伤害与伤害范围降低 (仅T方购买)
    // 检查是否为T方的投掷物伤害
    if (attackerTeam == CS_TEAM_T && inflictor != attacker) {
        new szClassname[32];
        entity_get_string(inflictor, EV_SZ_classname, szClassname, charsmax(szClassname));
        if (equal(szClassname, "grenade")) {
            // 将基础伤害缩减为原来的40%，波及半径范围相应缩小
            SetHamParamFloat(4, damage * 0.5);
            return HAM_HANDLED;
        }
    }

    return HAM_IGNORED;
}

// 'E' 键检测呼出商店菜单
public client_PreThink(id) {
    if (!is_user_alive(id)) return;

    new button = pev(id, pev_button);
    new oldbuttons = pev(id, pev_oldbuttons);

    // 检测+use键（E键）的按下瞬间
    if ((button & IN_USE) && !(oldbuttons & IN_USE)) {
        ShowShopMenu(id);
    }
}

// 展现商店菜单
public ShowShopMenu(id) {
    new menu[512], len = 0;
    new CsTeams:team = cs_get_user_team(id);
    new Float:flTime = get_gametime();

    len += formatex(menu[len], charsmax(menu) - len, "\y【 捉迷藏商店 】 \w当前金额: \g$%d^n^n", g_iMoney[id]);
    len += formatex(menu[len], charsmax(menu) - len, "1. \d特殊道具商城 (暂未开放)^n");

    // 2. 补血包
    new Float:flMedCD = g_flMedkitCD[id] - flTime;
    if (flMedCD > 0.0) {
        len += formatex(menu[len], charsmax(menu) - len, "2. \d补血包 [CD: %.0fs] ($3000)^n", flMedCD);
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "2. \w补血包 \y($3000)^n");
    }

    // 3. 千里眼
    if (g_bClarivoyanceBought[id]) {
        len += formatex(menu[len], charsmax(menu) - len, "3. \d千里眼 [本回合已买] ($4000)^n");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "3. \w千里眼 \y($4000)^n");
    }

    // 4. 闪光弹
    new Float:flRoundElapsed = flTime - g_flRoundStartTime;
    new Float:flFlashCD = g_flFlashCD[id] - flTime;
    new iFlashLimit = (team == CS_TEAM_T) ? 2 : 1;
    new iFlashCost = (team == CS_TEAM_T) ? 2000 : 10000;

    if (g_iFlashBought[id] >= iFlashLimit) {
        len += formatex(menu[len], charsmax(menu) - len, "4. \d闪光弹 [已达上限] ($%d)^n", iFlashCost);
    } else if (flRoundElapsed > 10.0 && flFlashCD > 0.0) {
        len += formatex(menu[len], charsmax(menu) - len, "4. \d闪光弹 [CD: %.0fs] ($%d)^n", flFlashCD, iFlashCost);
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "4. \w闪光弹 \y($%d)^n", iFlashCost);
    }

    // 5. 烟雾弹
    if (team != CS_TEAM_T) {
        len += formatex(menu[len], charsmax(menu) - len, "5. \d烟雾弹 (仅T可买) ($3000)^n");
    } else if (g_iSmokeBought[id] >= 1) {
        len += formatex(menu[len], charsmax(menu) - len, "5. \d烟雾弹 [已达上限] ($3000)^n");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "5. \w烟雾弹 \y($3000)^n");
    }

    // 6. 额外30血量
    if (team != CS_TEAM_CT) {
        len += formatex(menu[len], charsmax(menu) - len, "6. \d本局额外30血量 (仅CT可买) ($7000)^n");
    } else if (g_bExtraHPBought[id]) {
        len += formatex(menu[len], charsmax(menu) - len, "6. \d本局额外30血量 [已购] ($7000)^n");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "6. \w本局额外30血量 \y($7000)^n");
    }

    // 7. 额外速度
    len += formatex(menu[len], charsmax(menu) - len, "7. \w额外10点移动速度 \y($10000)^n");

    // 8. 高爆手雷
    if (team != CS_TEAM_T) {
        len += formatex(menu[len], charsmax(menu) - len, "8. \d高爆手雷 (仅T可买) ($10000)^n");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "8. \w高爆手雷 \y($10000)^n");
    }

    // 9. 轻刀
    if (team != CS_TEAM_CT) {
        len += formatex(menu[len], charsmax(menu) - len, "9. \d轻刀 (仅CT可买) ($10000)^n");
    } else if (g_bHasLightKnife[id]) {
        len += formatex(menu[len], charsmax(menu) - len, "9. \d轻刀 [已拥有] ($10000)^n");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "9. \w轻刀 \y($10000)^n");
    }

    len += formatex(menu[len], charsmax(menu) - len, "^n0. \r退出");

    new keys = MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_6|MENU_KEY_7|MENU_KEY_8|MENU_KEY_9|MENU_KEY_0;
    show_menu(id, keys, menu, -1, "ShopMenu");
}

// 商店菜单选择逻辑处理
public HandleShopMenu(id, key) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED;

    new CsTeams:team = cs_get_user_team(id);
    new Float:flTime = get_gametime();

    switch (key) {
        case 0: { // 1. 特殊道具商城暂留空
            client_print(id, print_chat, "[商店] 特殊道具商城暂未开放，请选择其他道具。");
        }
        case 1: { // 2. 补血包
            if (g_iMoney[id] < 3000) {
                client_print(id, print_chat, "[商店] 金钱不足 $3000。");
                return PLUGIN_HANDLED;
            }
            if (g_flMedkitCD[id] > flTime) {
                client_print(id, print_chat, "[商店] 补血包冷却中，还需 %.1f 秒。", g_flMedkitCD[id] - flTime);
                return PLUGIN_HANDLED;
            }
            g_iMoney[id] -= 3000;
            g_flMedkitCD[id] = flTime + 30.0;
            set_user_health(id, get_user_health(id) + 100);
            client_print(id, print_chat, "[商店] 成功购买补血包，生命值增加 100！");
            SyncClientMoney(id);
        }
        case 2: { // 3. 千里眼
            if (g_iMoney[id] < 4000) {
                client_print(id, print_chat, "[商店] 金钱不足 $4000。");
                return PLUGIN_HANDLED;
            }
            if (g_bClarivoyanceBought[id]) {
                client_print(id, print_chat, "[商店] 本局已购买过此道具。");
                return PLUGIN_HANDLED;
            }
            g_iMoney[id] -= 4000;
            g_bClarivoyanceBought[id] = true;
            client_print(id, print_chat, "[商店] 购买成功，千里眼生效中 (持续15秒)。");
            SyncClientMoney(id);

            // 开启探测逻辑 (10次循环，每1.5秒更新一次定位)
            new param[2];
            param[0] = id;
            param[1] = 15;
            ClairvoyanceEffect(param);
        }
        case 3: { // 4. 闪光弹
            new iFlashLimit = (team == CS_TEAM_T) ? 2 : 1;
            new iFlashCost = (team == CS_TEAM_T) ? 2000 : 10000;

            if (g_iMoney[id] < iFlashCost) {
                client_print(id, print_chat, "[商店] 金钱不足 $%d。", iFlashCost);
                return PLUGIN_HANDLED;
            }
            if (g_iFlashBought[id] >= iFlashLimit) {
                client_print(id, print_chat, "[商店] 本局购买闪光弹已达上限。");
                return PLUGIN_HANDLED;
            }

            new Float:flRoundElapsed = flTime - g_flRoundStartTime;
            if (flRoundElapsed > 10.0 && g_flFlashCD[id] > flTime) {
                client_print(id, print_chat, "[商店] 冷却中，还需 %.1f 秒。", g_flFlashCD[id] - flTime);
                return PLUGIN_HANDLED;
            }

            g_iMoney[id] -= iFlashCost;
            g_iFlashBought[id]++;
            give_item(id, "weapon_flashbang");

            if (flRoundElapsed > 10.0) {
                g_flFlashCD[id] = flTime + 60.0;
            }
            client_print(id, print_chat, "[商店] 成功购买闪光弹。");
            SyncClientMoney(id);
        }
        case 4: { // 5. 烟雾弹
            if (team != CS_TEAM_T) {
                client_print(id, print_chat, "[商店] 该道具仅限T方购买。");
                return PLUGIN_HANDLED;
            }
            if (g_iMoney[id] < 3000) {
                client_print(id, print_chat, "[商店] 金钱不足 $3000。");
                return PLUGIN_HANDLED;
            }
            if (g_iSmokeBought[id] >= 1) {
                client_print(id, print_chat, "[商店] 本局烟雾弹购买已达上限。");
                return PLUGIN_HANDLED;
            }

            g_iMoney[id] -= 3000;
            g_iSmokeBought[id]++;
            give_item(id, "weapon_smokegrenade");
            client_print(id, print_chat, "[商店] 成功购买烟雾弹。");
            SyncClientMoney(id);
        }
        case 5: { // 6. 额外30血量 (仅CT)
            if (team != CS_TEAM_CT) {
                client_print(id, print_chat, "[商店] 该道具仅限CT方购买。");
                return PLUGIN_HANDLED;
            }
            if (g_iMoney[id] < 7000) {
                client_print(id, print_chat, "[商店] 金钱不足 $7000。");
                return PLUGIN_HANDLED;
            }
            if (g_bExtraHPBought[id]) {
                client_print(id, print_chat, "[商店] 本局已购买过此道具。");
                return PLUGIN_HANDLED;
            }

            g_iMoney[id] -= 7000;
            g_bExtraHPBought[id] = true;
            set_user_health(id, get_user_health(id) + 30);
            client_print(id, print_chat, "[商店] 成功获取额外 30 点血量。");
            SyncClientMoney(id);
        }
        case 6: { // 7. 额外10速度
            if (g_iMoney[id] < 10000) {
                client_print(id, print_chat, "[商店] 金钱不足 $10000。");
                return PLUGIN_HANDLED;
            }
            g_iMoney[id] -= 10000;
            g_iSpeedBought[id]++;
            UpdatePlayerSpeed(id);
            client_print(id, print_chat, "[商店] 成功购买10点移动速度。");
            SyncClientMoney(id);
        }
        case 7: { // 8. 高爆手雷 (仅T)
            if (team != CS_TEAM_T) {
                client_print(id, print_chat, "[商店] 该道具仅限T方购买。");
                return PLUGIN_HANDLED;
            }
            if (g_iMoney[id] < 10000) {
                client_print(id, print_chat, "[商店] 金钱不足 $10000。");
                return PLUGIN_HANDLED;
            }

            g_iMoney[id] -= 10000;
            give_item(id, "weapon_hegrenade");
            client_print(id, print_chat, "[商店] 成功购买高爆手雷。");
            SyncClientMoney(id);
        }
        case 8: { // 9. 轻刀 (仅CT)
            if (team != CS_TEAM_CT) {
                client_print(id, print_chat, "[商店] 该道具仅限CT方购买。");
                return PLUGIN_HANDLED;
            }
            if (g_iMoney[id] < 10000) {
                client_print(id, print_chat, "[商店] 金钱不足 $10000。");
                return PLUGIN_HANDLED;
            }
            if (g_bHasLightKnife[id]) {
                client_print(id, print_chat, "[商店] 你已经拥有此道具。");
                return PLUGIN_HANDLED;
            }

            g_iMoney[id] -= 10000;
            g_bHasLightKnife[id] = true;
            UpdatePlayerSpeed(id);
            client_print(id, print_chat, "[商店] 成功购买轻刀 (持小刀时速度提升)。");
            SyncClientMoney(id);
        }
    }
    return PLUGIN_HANDLED;
}

// 武器切换更新速度设定
public Event_CurWeapon(id) {
    if (!is_user_alive(id)) return;
    UpdatePlayerSpeed(id);
}

// 物理移动速度修正逻辑
UpdatePlayerSpeed(id) {
    if (g_bFrozen[id]) return;

    new iWeapon = get_user_weapon(id);
    new Float:flBaseSpeed = 250.0;

    // 适配武器的基础移速
    switch(iWeapon) {
        case CSW_AWP: flBaseSpeed = 210.0;
        case CSW_SCOUT: flBaseSpeed = 260.0;
        case CSW_SG550, CSW_G3SG1: flBaseSpeed = 210.0;
        default: flBaseSpeed = 250.0;
    }

    new Float:flExtra = float(g_iSpeedBought[id]) * 10.0;

    // 轻刀增益 (仅手持小刀生效增加40速度)
    if (g_bHasLightKnife[id] && iWeapon == CSW_KNIFE) {
        flExtra += 40.0;
    }

    set_user_maxspeed(id, flBaseSpeed + flExtra);
}

// 千里眼雷达激光连线效果
public ClairvoyanceEffect(param[2]) {
    new id = param[0];
    new count = param[1];

    if (!is_user_alive(id) || count <= 0) return;

    new CsTeams:team = cs_get_user_team(id);
    new players[32], num;
    get_players(players, num, "ae", (team == CS_TEAM_T) ? "CT" : "T");

    for (new i = 0; i < num; i++) {
        new enemy = players[i];
        if (is_user_alive(enemy)) {
            // 向客户端传输在雷达或视野内与敌方相连的绿色激光（可持续性在短时间内辨别位置）
            message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
            write_byte(TE_BEAMENTS);
            write_short(id);       // 终点
            write_short(enemy);    // 起点
            write_short(g_sBeamSprite);
            write_byte(0);
            write_byte(15);
            write_byte(15); // 存活1.5秒
            write_byte(8);  // 线宽
            write_byte(0);
            write_byte(0);   // R
            write_byte(255); // G
            write_byte(0);   // B
            write_byte(120); // 透明度
            write_byte(0);
            message_end();
        }
    }

    param[1] = count - 1;
    set_task(1, "ClairvoyanceEffect", CLAIRVOYANCE_TASKID + id, param, 2);
}

// 离线重置
public client_disconnect(id) {
    remove_task(CLAIRVOYANCE_TASKID + id);
}

// 同步自带的CS内置金钱HUD (上限16000)，方便游玩
SyncClientMoney(id) {
    if (is_user_connected(id)) {
        cs_set_user_money(id, g_iMoney[id], 1);
    }
}

// 3. 屏幕右下角金钱显示HUD
public HUD_MoneyThink() {
    new players[32], num;
    get_players(players, num, "ch");

    for (new i = 0; i < num; i++) {
        new id = players[i];
        if (is_user_alive(id)) {
            // 在屏幕右下角绘制当前资金 (0.75, 0.85)
            set_hudmessage(100, 200, 50, 0.75, 0.85, 0, 0.0, 1.2, 0.0, 0.0, -1);
            show_hudmessage(id, "【 本局资金 】^n$ %d", g_iMoney[id]);
        }
    }
}