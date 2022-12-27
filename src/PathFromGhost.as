#if DEV
uint RunCount = 0;

array<vec3> GetPathForRootMapFromGhost() {
    auto thisRun = ++RunCount;
    if (!Permissions::CreateLocalReplay()) return NoPathNotifyMissingPermission("CreateLocalReplay");
    while (GetApp().RootMap is null) yield();
    while (GetApp().PlaygroundScript is null) yield();
    auto ps = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    while (GetApp().PlaygroundScript.DataFileMgr is null) yield();
    CGameDataFileManagerScript@ dataFileMgr = ps.DataFileMgr;
    if (RunCount != thisRun) return {};
    auto ghost = dataFileMgr.Map_GetAuthorGhost(GetApp().RootMap);
    if (ghost is null) return _GetPathFromRecord(thisRun);
    return RipGhost(ghost);
}

NadeoApi@ api;

array<vec3> _GetPathFromRecord(uint thisRun) {
    if (!Permissions::PlayRecords()
        || !Permissions::ViewRecords())
        return NoPathNotifyMissingPermission("PlayRecords or ViewRecords");
    // todo: download record ghost
    while (GetApp().RootMap is null) yield();
    while (GetApp().PlaygroundScript is null) yield();
    auto ps = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    // api stuff
    if (api is null) @api = NadeoApi();
    sleep(2000);
    if (RunCount != thisRun) return {}; // before API call
    auto recs = api.GetMapRecords("Personal_Best", GetApp().RootMap.MapInfo.MapUid, true, 1);
    auto tops = recs['tops'];
    if (tops.GetType() != Json::Type::Array) {
        warn('api did not return an array for records; instead got: ' + Json::Write(recs));
        return {};
    }
    auto accountId = string(tops[0]['top'][0]['accountId']);
    // get ghost
    MwFastBuffer<wstring> pids = MwFastBuffer<wstring>();
    pids.Add(accountId);
    if (ps.ScoreMgr is null) {
        warn("ps.ScoreMgr is null");
        return {};
    }
    auto gameMode = ps.ServerModeName;
    trace(gameMode);
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    // CGameMasterServerUserInfo@ msUser = app.ManiaPlanetScriptAPI.MasterServer_MSUsers[0];
    // auto msUser = app.ManiaPlanetScriptAPI.MasterServer_MSUsers[0];
    CGameUserScript@ msUser = GetApp().UserManagerScript.Users[0];
    auto userId = msUser.Id;
    auto mapUid = GetApp().RootMap.MapInfo.MapUid;
    if (RunCount != thisRun) return {}; // before downloading ghost
    auto recordsReq = ps.ScoreMgr.Map_GetPlayerListRecordList(userId, pids, mapUid, "PersonalBest", "", "", "");
    while (recordsReq.IsProcessing) yield();
    if (recordsReq.HasFailed) {
        warn("Failed to get ghost records: " + recordsReq.ErrorType + " " + recordsReq.ErrorCode);
        return {};
    }
    MwFastBuffer<CMapRecord@> records = recordsReq.MapRecordList;
    auto item = records[0];
    auto ghostDl = ps.DataFileMgr.Ghost_Download(item.FileName, item.ReplayUrl);
    while (ghostDl.IsProcessing) yield();
    if (ghostDl.HasFailed) {
        warn("Failed to get ghost: " + ghostDl.ErrorType + " " + ghostDl.ErrorCode);
        return {};
    }
    auto g = ghostDl.Ghost;
    if (RunCount != thisRun) return {}; // before ripping ghost
    return RipGhost(g);
}

array<vec3> NoPathNotifyMissingPermission(const string &in permission) {
    // we don't need this, so we just warn
    warn("Cannot load map path from author ghost or record ghost due to missing permission: " + permission);
    return {};
}


vec3[] RipGhost(CGameGhostScript@ ghost) {
    // return {};
    if (ghost.Result is null) {
        trace("Ghost " + ghost.Nickname + " has a null result. Cannot rip.");
        return {};
    }
    if (GetApp().RootMap is null) return {};
    if (GetApp().PlaygroundScript is null) return {};
    auto ps = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    while (ps !is null && ps.UIManager.UIAll.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
    if (ps is null) return {};
    sleep(5000);
    while (ps !is null && ps.UIManager.UIAll.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();

    auto startTime = ps.Now;
    auto ghostId = ps.Ghost_Add(ghost, true);
    vec3[] positions = {};
    // ps.UIManager.UIAll.SpectatorForceCameraType = 1;
    // ps.UIManager.UIAll.Spectator_SetForcedTarget_Ghost(ghostId);
    for (int t = -1000; t < ghost.Result.Time+500; t += 100) {
        ps.Ghosts_SetStartTime(startTime - t);
        yield();
        positions.InsertLast(ps.Ghost_GetPosition(ghostId));
        // yield();
    }
    ps.Ghost_Remove(ghostId);
    ps.Ghost_Release(ghost.Id);
    ps.Ghosts_SetStartTime(-1);
    // ps.UIManager.UIAll.SpectatorForceCameraType = specCam;
    return positions;
}


class NadeoApi {
    string liveSvcUrl;

    NadeoApi() {
        NadeoServices::AddAudience("NadeoLiveServices");
        liveSvcUrl = NadeoServices::BaseURL();
    }

    void AssertGoodPath(const string &in path) {
        if (path.Length <= 0 || !path.StartsWith("/")) {
            throw("API Paths should start with '/'!");
        }
    }

    const string LengthAndOffset(uint length, uint offset) {
        return "length=" + length + "&offset=" + offset;
    }

    /* LIVE SERVICES API CALLS */

    Json::Value CallLiveApiPath(const string &in path) {
        AssertGoodPath(path);
        return FetchLiveEndpoint(liveSvcUrl + path);
    }

    /* see COTD_HUD/example/getMapRecords.json */
    Json::Value GetMapRecords(const string &in seasonUid, const string &in mapUid, bool onlyWorld = true, uint length=5, uint offset=0) {
        // Personal_Best
        string qParams = onlyWorld ? "?onlyWorld=true" : "";
        if (onlyWorld) qParams += "&" + LengthAndOffset(length, offset);
        return CallLiveApiPath("/api/token/leaderboard/group/" + seasonUid + "/map/" + mapUid + "/top" + qParams);
    }
}

Json::Value FetchLiveEndpoint(const string &in route) {
    trace("[FetchLiveEndpoint] Requesting: " + route);
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) { yield(); }
    auto req = NadeoServices::Get("NadeoLiveServices", route);
    req.Start();
    while(!req.Finished()) { yield(); }
    return Json::Parse(req.String());
}
#endif
