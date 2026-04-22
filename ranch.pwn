#include <a_samp>
#include <a_mysql>
#include <streamer>
#include <dc_cmd>

// --- Конфигурация БД ---
#define MYSQL_HOST          "127.0.0.1"
#define MYSQL_USER          "root"
#define MYSQL_PASS          ""
#define MYSQL_DB            "ranchrp"

#define MAX_GH_SLOTS        5
#define GH_TIME_GROW        600
#define GH_TIME_FAST        300

#define OBJ_BASE            3169
#define OBJ_TOMATO_CRATE    1271

enum gh_info_struct {
    gh_sql_id,
    Float:gh_pos_x,
    Float:gh_pos_y,
    Float:gh_pos_z,
    Float:gh_pos_a,
    gh_time_start,
    gh_is_upgraded,
    gh_stage,
    gh_area_id,
    gh_label_id,
    gh_main_obj_id,
    gh_crates_id[5]
};

new gh_data[MAX_PLAYERS][MAX_GH_SLOTS][gh_info_struct];
new gh_selected_slot[MAX_PLAYERS] = {-1, ...};
new MySQL:db_handle;

// --- Вспомогательные функции ---

stock Gh_ResetSlot(playerid, slot) {
    gh_data[playerid][slot][gh_sql_id] = 0;

    if(IsValidDynamicArea(DynamicArea:gh_data[playerid][slot][gh_area_id]))
        DestroyDynamicArea(DynamicArea:gh_data[playerid][slot][gh_area_id]);

    if(IsValidDynamic3DTextLabel(Text3D:gh_data[playerid][slot][gh_label_id]))
        DestroyDynamic3DTextLabel(Text3D:gh_data[playerid][slot][gh_label_id]);

    if(IsValidDynamicObject(DynamicObject:gh_data[playerid][slot][gh_main_obj_id]))
        DestroyDynamicObject(DynamicObject:gh_data[playerid][slot][gh_main_obj_id]);

    for(new i = 0; i < 5; i++) {
        if(IsValidDynamicObject(DynamicObject:gh_data[playerid][slot][gh_crates_id][i]))
            DestroyDynamicObject(DynamicObject:gh_data[playerid][slot][gh_crates_id][i]);

        gh_data[playerid][slot][gh_crates_id][i] = _:INVALID_STREAMER_ID;
    }

    gh_data[playerid][slot][gh_area_id] = _:INVALID_STREAMER_ID;
    gh_data[playerid][slot][gh_label_id] = _:INVALID_STREAMER_ID;
    gh_data[playerid][slot][gh_main_obj_id] = _:INVALID_STREAMER_ID;
}

stock Gh_Refresh(playerid, slot) {
    if(gh_data[playerid][slot][gh_sql_id] == 0) return;

    new
        duration = (gh_data[playerid][slot][gh_is_upgraded]) ? GH_TIME_FAST : GH_TIME_GROW,
        elapsed = gettime() - gh_data[playerid][slot][gh_time_start];

    new Float:progress = (float(elapsed) / float(duration)) * 100.0;
    if(progress > 100.0) progress = 100.0;

    new current_stage = (progress >= 100.0) ? 5 : floatround(progress / 20.0, floatround_floor);

    static label_text[128];
    format(label_text, sizeof label_text, "{FFFFFF}Теплица с помидорами\n{FFFFFF}Созревание: {00FF00}%.1f%%\n{FFFFFF}Улучшение: %s",
        progress, (gh_data[playerid][slot][gh_is_upgraded] ? ("{00FF00}X2") : ("{FF6347}Нет")));

    UpdateDynamic3DTextLabelText(Text3D:gh_data[playerid][slot][gh_label_id], -1, label_text);

    if(current_stage != gh_data[playerid][slot][gh_stage]) {
        gh_data[playerid][slot][gh_stage] = current_stage;

        new Float:cx = gh_data[playerid][slot][gh_pos_x] + (4.5 * floatsin(-gh_data[playerid][slot][gh_pos_a] - 90.0, degrees));
        new Float:cy = gh_data[playerid][slot][gh_pos_y] + (4.5 * floatcos(-gh_data[playerid][slot][gh_pos_a] - 90.0, degrees));

        for(new i = 0; i < 5; i++) {
            if(IsValidDynamicObject(DynamicObject:gh_data[playerid][slot][gh_crates_id][i]))
                DestroyDynamicObject(DynamicObject:gh_data[playerid][slot][gh_crates_id][i]);

            if(i < current_stage) {
                gh_data[playerid][slot][gh_crates_id][i] = _:CreateDynamicObject(OBJ_TOMATO_CRATE,
                    cx, cy, gh_data[playerid][slot][gh_pos_z] - 0.85 + (i * 0.42), 0.0, 0.0, gh_data[playerid][slot][gh_pos_a], .playerid = playerid);
            }
        }
    }
}

// --- Коллбэки ---

public OnGameModeInit() {
    db_handle = mysql_connect(MYSQL_HOST, MYSQL_USER, MYSQL_PASS, MYSQL_DB);
    SetTimer("Gh_GlobalTick", 1000, true);
    return 1;
}

public OnPlayerConnect(playerid) {
    gh_selected_slot[playerid] = -1;
    for(new i = 0; i < MAX_GH_SLOTS; i++) {
        gh_data[playerid][i][gh_sql_id] = 0;
        gh_data[playerid][i][gh_area_id] = _:INVALID_STREAMER_ID;
        gh_data[playerid][i][gh_label_id] = _:INVALID_STREAMER_ID;
        gh_data[playerid][i][gh_main_obj_id] = _:INVALID_STREAMER_ID;
        for(new o = 0; o < 5; o++) gh_data[playerid][i][gh_crates_id][o] = _:INVALID_STREAMER_ID;
    }

    new query[128];
    mysql_format(db_handle, query, sizeof query, "SELECT * FROM greenhouses WHERE owner_id = %d LIMIT %d", playerid, MAX_GH_SLOTS);
    mysql_tquery(db_handle, query, "OnPlayerGreenhousesLoad", "d", playerid);
    return 1;
}

forward OnPlayerGreenhousesLoad(playerid);
public OnPlayerGreenhousesLoad(playerid) {
    new rows = cache_num_rows();
    for(new i = 0; i < rows; i++) {
        cache_get_value_name_int(i, "id", gh_data[playerid][i][gh_sql_id]);
        cache_get_value_name_float(i, "pos_x", gh_data[playerid][i][gh_pos_x]);
        cache_get_value_name_float(i, "pos_y", gh_data[playerid][i][gh_pos_y]);
        cache_get_value_name_float(i, "pos_z", gh_data[playerid][i][gh_pos_z]);
        cache_get_value_name_float(i, "angle", gh_data[playerid][i][gh_pos_a]);
        cache_get_value_name_int(i, "start_time", gh_data[playerid][i][gh_time_start]);
        cache_get_value_name_int(i, "is_upgraded", gh_data[playerid][i][gh_is_upgraded]);

        new Float:x = gh_data[playerid][i][gh_pos_x];
        new Float:y = gh_data[playerid][i][gh_pos_y];
        new Float:z = gh_data[playerid][i][gh_pos_z];
        new Float:a = gh_data[playerid][i][gh_pos_a];

        gh_data[playerid][i][gh_main_obj_id] = _:CreateDynamicObject(OBJ_BASE, x, y, z - 1.35, 0.0, 0.0, a, .playerid = playerid);
        gh_data[playerid][i][gh_area_id] = _:CreateDynamicSphere(x, y, z, 3.5, .playerid = playerid);
        gh_data[playerid][i][gh_label_id] = _:CreateDynamic3DTextLabel("...", 0xFFFFFFFF, x, y, z + 2.2, 12.0, .playerid = playerid);

        gh_data[playerid][i][gh_stage] = -1;
        Gh_Refresh(playerid, i);
    }
}

public OnPlayerDisconnect(playerid, reason) {
    new query[256];
    for(new i = 0; i < MAX_GH_SLOTS; i++) {
        if(gh_data[playerid][i][gh_sql_id] == 0) continue;

        mysql_format(db_handle, query, sizeof query, "UPDATE greenhouses SET start_time = %d, is_upgraded = %d WHERE id = %d",
            gh_data[playerid][i][gh_time_start], gh_data[playerid][i][gh_is_upgraded], gh_data[playerid][i][gh_sql_id]);
        mysql_tquery(db_handle, query);

        Gh_ResetSlot(playerid, i);
    }
    return 1;
}

forward Gh_GlobalTick();
public Gh_GlobalTick() {
    for(new i = GetPlayerPoolSize(); i >= 0; i--) {
        if(!IsPlayerConnected(i)) continue;
        for(new s = 0; s < MAX_GH_SLOTS; s++) {
            if(gh_data[i][s][gh_sql_id] != 0) Gh_Refresh(i, s);
        }
    }
}

CMD:creategh(playerid) {
    new slot = -1;
    for(new i = 0; i < MAX_GH_SLOTS; i++) {
        if(gh_data[playerid][i][gh_sql_id] == 0) { slot = i; break; }
    }
    if(slot == -1) return SendClientMessage(playerid, -1, "{FF6347}Ошибка: {FFFFFF}Нельзя иметь более 5 теплиц.");

    new Float:p[3], Float:a;
    GetPlayerPos(playerid, p[0], p[1], p[2]);
    GetPlayerFacingAngle(playerid, a);

    new query[256];
    mysql_format(db_handle, query, sizeof query,
        "INSERT INTO greenhouses (owner_id, pos_x, pos_y, pos_z, angle, start_time) VALUES (%d, %.4f, %.4f, %.4f, %.4f, %d)",
        playerid, p[0], p[1], p[2], a, gettime());

    mysql_tquery(db_handle, query, "OnGreenhouseCreated", "didfff", playerid, slot, p[0], p[1], p[2], a);
    return 1;
}

forward OnGreenhouseCreated(playerid, slot, Float:x, Float:y, Float:z, Float:a);
public OnGreenhouseCreated(playerid, slot, Float:x, Float:y, Float:z, Float:a) {
    gh_data[playerid][slot][gh_sql_id] = _:cache_insert_id();
    gh_data[playerid][slot][gh_pos_x] = x;
    gh_data[playerid][slot][gh_pos_y] = y;
    gh_data[playerid][slot][gh_pos_z] = z;
    gh_data[playerid][slot][gh_pos_a] = a;
    gh_data[playerid][slot][gh_time_start] = gettime();
    gh_data[playerid][slot][gh_is_upgraded] = 0;
    gh_data[playerid][slot][gh_stage] = -1;

    gh_data[playerid][slot][gh_main_obj_id] = _:CreateDynamicObject(OBJ_BASE, x, y, z - 1.35, 0.0, 0.0, a, .playerid = playerid);
    gh_data[playerid][slot][gh_area_id] = _:CreateDynamicSphere(x, y, z, 3.5, .playerid = playerid);
    gh_data[playerid][slot][gh_label_id] = _:CreateDynamic3DTextLabel("...", 0xFFFFFFFF, x, y, z + 2.2, 12.0, .playerid = playerid);

    Gh_Refresh(playerid, slot);
    SendClientMessage(playerid, 0x00FF00FF, "Теплица с помидорами успешно установлена!");
    return 1;
}

public OnPlayerKeyStateChange(playerid, newkeys, oldkeys) {
    if(newkeys & KEY_WALK) {
        for(new i = 0; i < MAX_GH_SLOTS; i++) {
            if(gh_data[playerid][i][gh_sql_id] != 0 && IsPlayerInDynamicArea(playerid, DynamicArea:gh_data[playerid][i][gh_area_id])) {
                gh_selected_slot[playerid] = i;
                ShowPlayerDialog(playerid, 7777, DIALOG_STYLE_LIST, "Управление теплицей",
                    "1. Собрать урожай (ящики)\n2. Улучшить теплицу (x2 скорость)", "Выбрать", "Закрыть");
                return 1;
            }
        }
    }
    return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[]) {
    if(dialogid == 7777 && response) {
        new slot = gh_selected_slot[playerid];
        if(slot == -1 || gh_data[playerid][slot][gh_sql_id] == 0) return 1;

        if(listitem == 0) {
            if(gh_data[playerid][slot][gh_stage] < 5)
                return SendClientMessage(playerid, -1, "{FF6347}Ошибка: {FFFFFF}Помидоры еще не созрели.");

            gh_data[playerid][slot][gh_time_start] = gettime();
            gh_data[playerid][slot][gh_stage] = -1;

            Gh_Refresh(playerid, slot);
            SendClientMessage(playerid, 0x32CD32FF, "Вы успешно собрали ящики с помидорами!");
        }
        else if(listitem == 1) {
            if(gh_data[playerid][slot][gh_is_upgraded])
                return SendClientMessage(playerid, -1, "{FF6347}Ошибка: {FFFFFF}Данная теплица уже была улучшена.");

            gh_data[playerid][slot][gh_is_upgraded] = 1;

            new query[128];
            mysql_format(db_handle, query, sizeof query, "UPDATE greenhouses SET is_upgraded = 1 WHERE id = %d", gh_data[playerid][slot][gh_sql_id]);
            mysql_tquery(db_handle, query);

            Gh_Refresh(playerid, slot);
            SendClientMessage(playerid, 0x32CD32FF, "Теплица улучшена! Скорость роста увеличена в 2 раза.");
        }
    }
    return 1;
}
