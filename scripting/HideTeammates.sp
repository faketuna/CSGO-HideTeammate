#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <clientprefs>
#include <sdktools> 

#include <multicolors>
//#tryinclude <leader>

#define MAX_BUTTONS 25
int g_LastButtons[MAXPLAYERS+1];

ConVar sm_hide_enabled, sm_hide_maximum;

Handle g_HideCookie;
Handle g_Hide_EnableCookie;
Handle g_Hide_RightClick_Cookie;
bool g_HidePlayers[MAXPLAYERS+1][MAXPLAYERS+1];
bool bEnabled = true;

bool g_bHide[MAXPLAYERS+1];
bool g_bRightClickUnHide[MAXPLAYERS+1];
bool g_bIsHiding[MAXPLAYERS+1];
int g_iHide[MAXPLAYERS+1];
int g_iHideP2[MAXPLAYERS+1];

float timer_distance;
float timer_vec_target[3];
float timer_vec_client[3];

public Plugin myinfo = 
{
    name = "Hide Teammates",
    author = "DarkerZ [RUS]",
    description = "Hide players based on individual distances",
    version = "1.6.2",
    url = "dark-skill.ru"
}

public void OnPluginStart()
{
    RegConsoleCmd("sm_hide", Command_Hide);
    RegConsoleCmd("sm_hideall", Command_HideAll);

    sm_hide_enabled    = CreateConVar("sm_hide_enabled", "1", "Disabled/enabled [0/1]", _, true, 0.0, true, 1.0);
    sm_hide_maximum    = CreateConVar("sm_hide_maximum", "8000", "The maximum distance a player can choose [1000-8000]", _, true, 1000.0, true, 8000.0);
    sm_hide_enabled.AddChangeHook(OnConVarChange);

    LoadTranslations("HideTeammates.phrases");

    g_HideCookie = RegClientCookie("cookie_hide_teammates", "Hide Teammates", CookieAccess_Protected);
    g_Hide_EnableCookie = RegClientCookie("cookie_hide_teammates_enable", "Hide Teammates Enable", CookieAccess_Protected);
    g_Hide_RightClick_Cookie = RegClientCookie("cookie_ht_temp_unhide", "Hide Teammates Unhide Temporary", CookieAccess_Protected);
    SetCookieMenuItem(PrefMenu, 0, "Hide Teammates");

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            OnClientPutInServer(client);
            if (AreClientCookiesCached(client))
            {
                OnClientCookiesCached(client);
            }
        }
    }

    AutoExecConfig(true);

    HookEvent("player_death", OnPlayerDeath);
}

public void OnMapStart()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        for (int target = 1; target <= MaxClients; target++)
        {
            g_HidePlayers[client][target] = false;
        }
    }
    if (!bEnabled) return;

    CreateTimer(0.3, HideTimer, _,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client) 
{
    if (!bEnabled) return;
    SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client)) return;
    
    char sCookieValue[4];
    
    GetClientCookie(client, g_Hide_EnableCookie, sCookieValue, sizeof(sCookieValue));
    
    if (!StrEqual(sCookieValue, ""))
    {
        g_bHide[client] = view_as<bool>(StringToInt(sCookieValue));
        g_bIsHiding[client] = g_bHide[client];
    }
    else
    {
        g_bHide[client] = false;
        g_bIsHiding[client] = false;
    }
    
    GetClientCookie(client, g_HideCookie, sCookieValue, sizeof(sCookieValue));
    
    if (!StrEqual(sCookieValue, ""))
    {
        g_iHide[client] = StringToInt(sCookieValue);
        g_iHideP2[client] = g_iHide[client]*g_iHide[client];
    }
    else
    {
        g_iHide[client] = 0;
        g_iHideP2[client] = 0;
    }

    GetClientCookie(client, g_Hide_RightClick_Cookie, sCookieValue, sizeof(sCookieValue));

    
    if (!StrEqual(sCookieValue, ""))
    {
        g_bRightClickUnHide[client] = view_as<bool>(StringToInt(sCookieValue));
    }
    else
    {
        g_bRightClickUnHide[client] = false;
    }
}

public void OnClientDisconnect(int client)
{
    g_bHide[client] = false;
    g_iHide[client] = 0;
    g_iHideP2[client] = 0;
    
    for (int target = 1; target <= MaxClients; target++)
    {
        g_HidePlayers[client][target] = false;
    }
    SDKUnhook(client, SDKHook_SetTransmit, Hook_SetTransmit);
}

public void OnConVarChange(Handle hCvar, const char[] oldValue, const char[] newValue)
{
    if (StrEqual(oldValue, newValue)) return;

    if (hCvar == sm_hide_enabled)
    {
        bEnabled = sm_hide_enabled.BoolValue;

        for (int client = 1; client <= MaxClients; client++)
        {
            for (int target = 1; target <= MaxClients; target++)
            {
                g_HidePlayers[client][target] = false;
            }

            if (IsClientInGame(client))
            {
                OnClientCookiesCached(client);
                if (bEnabled)
                {
                    SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
                }
                else
                {
                    SDKUnhook(client, SDKHook_SetTransmit, Hook_SetTransmit);
                }
            }
        }
        if (bEnabled)
        {
            CreateTimer(0.3, HideTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (!victim)
        return;

    for (int target = 1; target <= MaxClients; target++)
    {
        g_HidePlayers[victim][target] = false;
    }
}

public Action Command_Hide(int client, int args)
{
    SetGlobalTransTarget(client);
    if (!IsClientInGame(client))
        return Plugin_Handled;
    
    if (!bEnabled)
    {
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Disabled");
        return Plugin_Handled;
    }

    if (!AreClientCookiesCached(client))
    {
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Wait");
        return Plugin_Handled;
    }

    int customdistance = -2;

    if (args == 1)
    {
        char inputArgs[5];
        GetCmdArg(1, inputArgs, sizeof(inputArgs));
        customdistance = StringToInt(inputArgs);
    }
    
    if (args == 1 && customdistance >= 0 && customdistance <= sm_hide_maximum.IntValue)
    {
        SetClientHide(client, true, customdistance, true);
        if (g_iHide[client] == 0)
            CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Enable All Map");
        else
            CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Enable", g_iHide[client]);
    }
    else if (args >= 2 || customdistance < -2 || customdistance > sm_hide_maximum.IntValue)
    {
        CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Wrong", sm_hide_maximum.IntValue);
    }
    else if (customdistance == -1)
    {
        SetClientHide(client, false, g_iHide[client], true);
        CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Disable");
        
    }
    else if (customdistance == -2)
    {
        DisplaySettingsMenu(client);
    }
    return Plugin_Handled;
}

public Action Command_HideAll(int client, int args)
{ 
    SetGlobalTransTarget(client);
    if (!IsClientInGame(client))
        return Plugin_Handled;
    
    if (!bEnabled)
    {
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Disabled");
        return Plugin_Handled;
    }

    if (!AreClientCookiesCached(client))
    {
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Wait");
        return Plugin_Handled;
    }
    if (g_bHide[client] == true)
    {
        SetClientHide(client, false, g_iHide[client], true);
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Client Disable");
    }
    else
    {
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Client Enable All Map");
        SetClientHide(client, true, 0, true);
    }
    return Plugin_Handled;
}

public bool SetClientHide(int client, bool hide_enable, int hide_distance, bool fromCommand)
{
    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        if (fromCommand) {
            g_bIsHiding[client] = hide_enable;
        }
        g_bHide[client] = hide_enable;
        g_iHide[client] = hide_distance;
        g_iHideP2[client] = hide_distance*hide_distance;
        SetClientCookie(client, g_Hide_EnableCookie, (g_bHide[client]) ? "1" : "0");
        char sCookieValue[4];
        FormatEx(sCookieValue, sizeof(sCookieValue), "%d", g_iHide[client]);
        SetClientCookie(client, g_HideCookie, sCookieValue);
        return true;
    }
    return false;
}

public Action HideTimer(Handle timer)
{
    if (!bEnabled)
        return Plugin_Stop;

    for (int client = 1; client <= MaxClients; client++)
    {
        for (int target = 1; target <= MaxClients; target++)
        {
            g_HidePlayers[client][target] = false;
            if (IsClientInGame(client) && IsPlayerAlive(client))
            {
                if (target != client && g_bHide[client] && IsClientInGame(target) && IsPlayerAlive(target))
                {
                    #if defined _leader_included_
                    if (target == Leader_CurrentLeader())
                        continue;
                    #endif
                    if ((GetClientTeam(client) == GetClientTeam(target)))
                    {
                        if ((GetClientTeam(client) == 2) || (GetClientTeam(client) == 3))
                        {
                            if (g_iHide[client] == 0)
                            {
                                g_HidePlayers[client][target] = true;
                            }
                            else
                            {
                                GetClientAbsOrigin(target, timer_vec_target);
                                GetClientAbsOrigin(client, timer_vec_client);
                                timer_distance = GetVectorDistance(timer_vec_target, timer_vec_client, true);
                                if (timer_distance < g_iHideP2[client])
                                {
                                    g_HidePlayers[client][target] = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return Plugin_Continue;
}

public Action Hook_SetTransmit(int target, int client)
{
    if (g_HidePlayers[client][target])
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public void PrefMenu(int client, CookieMenuAction actions, any info, char[] buffer, int maxlen)
{
    if (actions == CookieMenuAction_DisplayOption)
    {
        Format(buffer, maxlen, "%T", "HideT Cookie Menu", client);
    }
    
    if (actions == CookieMenuAction_SelectOption)
    {
        DisplaySettingsMenu(client);
    }
}

void DisplaySettingsMenu(int client)
{
    SetGlobalTransTarget(client);
    if (!bEnabled)
    {
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Disabled");
        return;
    }
    
    if (!AreClientCookiesCached(client))
    {
        CPrintToChat(client, "%t %t", "HideT Tag", "HideT Wait");
        return;
    }
    
    Menu prefmenu = CreateMenu(PrefMenuHandler, MENU_ACTIONS_DEFAULT);
    
    char szMenuTitle[64];
    Format(szMenuTitle, sizeof(szMenuTitle), "%T", "HideT Menu Title", client);
    prefmenu.SetTitle(szMenuTitle);
    
    char szEnable[512];
    FormatEx(szEnable, sizeof(szEnable), "%T \n%T", g_bHide[client] ? "HideT Menu Show" : "HideT Menu Hide", client, "HideT AdjustDesc", client, sm_hide_maximum.IntValue);
    prefmenu.AddItem(g_bHide[client] ? "ht_disable" : "ht_enable", szEnable);
    
    if (g_bHide[client])
    {
        char szItem[64];
        if (g_iHide[client] == 0)
            Format(szItem, sizeof(szItem), "%T", "HideT Menu All Map", client);
        else
            Format(szItem, sizeof(szItem), "%T", "HideT Menu Distance", client, g_iHide[client]);

        switch (g_iHide[client])
        {
            case 0: { prefmenu.AddItem("hdt_125", szItem);}
            case 125: { prefmenu.AddItem("hdt_200", szItem);}
            case 200: { prefmenu.AddItem("hdt_300", szItem);}
            case 300: { prefmenu.AddItem("hdt_400", szItem);}
            case 400: { prefmenu.AddItem("hdt_500", szItem);}
            case 500: { prefmenu.AddItem("hdt_750", szItem);}
            case 750: { prefmenu.AddItem("hdt_1000", szItem);}
            case 1000: { prefmenu.AddItem("hdt_0", szItem);}
            default: { prefmenu.AddItem("hdt_0", szItem);}
        }

        char szRightClick[512];
        FormatEx(szRightClick, sizeof(szRightClick), "%t", g_bRightClickUnHide[client] ? "HideT Menu Right Click Unhide Enabled" : "HideT Menu Right Click Unhide Disabled");
        prefmenu.AddItem(g_bRightClickUnHide[client] ? "RightClick_disable" : "RightClick_enable", szRightClick);
        
    }
    
    prefmenu.ExitBackButton = true;
    prefmenu.Display(client, MENU_TIME_FOREVER);
}

public int PrefMenuHandler(Menu prefmenu, MenuAction actions, int client, int item)
{
    SetGlobalTransTarget(client);
    if (actions == MenuAction_Select)
    {
        char preference[32];
        
        GetMenuItem(prefmenu, item, preference, sizeof(preference));
        
        if (StrEqual(preference, "ht_disable"))
        {
            SetClientHide(client, false, g_iHide[client], true);
            CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Disable");
        }
        else if (StrEqual(preference, "ht_enable"))
        {
            SetClientHide(client, true, g_iHide[client], true);
            if (g_iHide[client] == 0)
                CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Enable All Map");
            else
                CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Enable", g_iHide[client]);
        }

        if (StrContains(preference, "hdt") >= 0)
        {
            SetClientHide(client, true, StringToInt(preference[4]), true);
            if (g_iHide[client] == 0)
                CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Enable All Map");
            else
                CPrintToChat(client,"%t %t", "HideT Tag", "HideT Client Enable", g_iHide[client]);
        }

        if (StrEqual(preference, "RightClick_disable"))
        {
            SetClientCookie(client, g_Hide_RightClick_Cookie, "0");
            g_bRightClickUnHide[client] = false;
        }
        else if (StrEqual(preference, "RightClick_enable"))
        {
            SetClientCookie(client, g_Hide_RightClick_Cookie, "1");
            g_bRightClickUnHide[client] = true;
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

public OnClientDisconnect_Post(client)
{
    g_LastButtons[client] = 0;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
    for (new i = 0; i < MAX_BUTTONS; i++)
    {
        new button = (1 << i);
        
        if ((buttons & button))
        {
            if (!(g_LastButtons[client] & button))
            {
                OnButtonPress(client, button);
            }
        }
        else if ((g_LastButtons[client] & button))
        {
            OnButtonRelease(client, button);
        }
    }
    
    g_LastButtons[client] = buttons;
    return Plugin_Continue;
}

OnButtonPress(client, button)
{
    if(button != IN_ATTACK2) {
        return;
    }
    if(!g_bIsHiding[client]) {
        return;
    }
    if(!g_bRightClickUnHide[client]){
        return;
    }
    SetClientHide(client, false, g_iHide[client], false);
    return;
}

OnButtonRelease(client, button)
{
    if(button != IN_ATTACK2) {
        return;
    }
    if(!g_bIsHiding[client]) {
        return;
    }
    if(!g_bRightClickUnHide[client]){
        return;
    }
    SetClientHide(client, true, g_iHide[client], false);
    return;
}