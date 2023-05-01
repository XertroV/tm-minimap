namespace MiniMap {
    CpPositionData@ cpPositions = CpPositionData();
    array<array<vec3>> linkedCpPositions;
    vec3 min, max, rawMin, rawMax; // map boundaries
    float maxXZLen;
    array<array<uint>> minimapPlayerObservations;
    bool mmStateInitialized = false;
    uint debugLogCount = 0;
    // array<vec3> blockPositions;
    // array<int2> blockGridPositions;
    bool mmIsScreenShot = false;
    MapWithScreenshot@ mws;
    nvg::Texture@ mmBgTexture;

    void ClearMiniMapState() {
        exceptionsWarned = 0;
        mmStateInitialized = false;
        mmIsScreenShot = false;
        @mws = null;
        @mmBgTexture = null;
        debugLogCount = 0;
        @cpPositions = CpPositionData();
        if (minimapPlayerObservations.Length != S_MiniMapGridParts) InitGrid();
        for (uint y = 0; y < minimapPlayerObservations.Length; y++) {
            auto xs = minimapPlayerObservations[y];
            for (uint x = 0; x < xs.Length; x++) {
                xs[x] = 0;
            }
        }
        // seenBlocks.DeleteAll();
        trace("cleared minimap state.");
    }

    void InitGrid() {
        minimapPlayerObservations.Resize(NbGridParts);
        for (uint i = 0; i < minimapPlayerObservations.Length; i++) {
            auto item = minimapPlayerObservations[i];
            item.Resize(NbGridParts);
            for (uint j = 0; j < item.Length; j++) {
                item[j] = 0;
            }
        }
    }

    // main start code

    void MiniMapStart() {
        ClearMiniMapState();
        while (cpPositions.Length == 0) {
            // get positions of CPs (waits for them to load)
            @cpPositions = GetCheckpointPositions();
            // cpPositions = cpPosData.
            if (cpPositions.positions.Length > 0) break;
            yield();
        }
        trace("Found " + cpPositions.Length + " unique CPs to draw.");
        linkedCpPositions = GetLinkedCheckpointPositions();
        trace("Found " + linkedCpPositions.Length + " sets of linked CPs to draw.");
        // blockPositions = GetBlockPositions();
        // trace("Found " + blockPositions.Length + " block positions to draw.");

        // calc map boundaries
        min = cpPositions[0]; // always >= min
        max = cpPositions[0]; // always <= max
        for (uint i = 0; i < cpPositions.Length; i++) {
            auto pos = cpPositions[i];
            min.x = Math::Min(min.x, pos.x);
            min.y = Math::Min(min.y, pos.y);
            min.z = Math::Min(min.z, pos.z);
            max.x = Math::Max(max.x, pos.x);
            max.y = Math::Max(max.y, pos.y);
            max.z = Math::Max(max.z, pos.z);
        }
        rawMin = min;
        rawMax = max;

        auto map = GetApp().RootMap;
        if (map !is null) {
            @mws = GetMapScreenshotOrNull(map.EdChallengeId);
            if (mws !is null && !S_DisableBackgroundImages) {
                MMStart_ScreenShot();
                return;
            }
        }
        MMStart_InitGrid();
    }


    void MMStart_ScreenShot() {
        mmIsScreenShot = true;
        max.x = mws.max.x;
        max.z = mws.max.y;
        min.x = mws.min.x;
        min.z = mws.min.y;
        maxXZLen = Math::Max(max.z - min.z, max.x - min.x);
        @mmBgTexture = nvg::LoadTexture(mws.ReadImageFile(), 1);
        if (mmBgTexture is null) {
            warn("Failed to load texture: " + mws.imgPath);
        }
        mmStateInitialized = true;
    }

    void MMStart_InitGrid() {
        // if this is true, then the xz area is very small;
        // it must be non-zero anyway, so pad it out to guarentee it,
        // and also to provide a minimum minimap size.
        if (((max - min) * vec3(1, 0, 1)).LengthSquared() < 10000) {
            max += vec3(16, 0, 16);
            min -= vec3(16, 0, 16);
        }

        // add a small amount of padding (sometimes the map route goes outside the cp bounding box)
        vec3 mapSize = max - min;
        float padding = 0.1;
        min -= mapSize * padding;
        max += mapSize * padding;

        trace("Calculated map min: " + min.ToString());
        trace("Calculated map max: " + max.ToString());

        // square up the map
        float xLen = max.x - min.x;
        float zLen = max.z - min.z;
        maxXZLen = Math::Max(xLen, zLen);
        float d = Math::Abs(xLen - zLen);
        if (xLen > zLen) {
            max.z += d/2;
            min.z -= d/2;
        }
        else {
            max.x += d/2;
            min.x -= d/2;
        }

        // ready to draw; handled by UpdateMiniMap
        mmStateInitialized = true;
    }

    uint exceptionsWarned = 0;

    void UpdateMiniMap() {
        if (!IsEditorConditionCheckOkay) return;
        if (!mmStateInitialized) return;
        if (!S_UpdateWhenHidden && S_MiniMapState == 0) return;
        if (S_MiniMapState == 0 && mmIsScreenShot) return;
        PrepMinMapVars();
        try {
            ObservePlayers();
        } catch {
            if (exceptionsWarned < 10)
                warn("Exception updating minimap: " + getExceptionInfo());
            exceptionsWarned++;
        }
    }

    void Render() {
        if (S_MiniMapState == 0) return;
        if (!mmStateInitialized) return;
        // don't display when the menu is open
        if (GetApp().Network.PlaygroundClientScriptAPI.IsInGameMenuDisplayed) return;
        if (bigMiniMap)
            DrawBigMmBgColor();
        if (mmIsScreenShot) {
            DrawMiniMapBackgroundImage();
        } else {
            if (S_DrawGridLines)
                DrawMMGrid();  // ~0.15ms draw time with 50 cols
            DrawMiniMapBackground();
            DrawMiniMapPlayerObservations();
        }
        // DrawMiniMapBlocks();
        DrawMiniMapCheckpoints();
        DrawMiniMapCheckpointLinks();
        DrawMiniMapPlayers();
        DrawMiniMapCamera();
    }

    // void ConvertBlockPositions() {
    //     blockGridPositions.RemoveRange(0, blockGridPositions.Length);
    //     for (uint i = 0; i < blockPositions.Length; i++) {
    //         blockGridPositions.InsertLast(WorldToGridPos(blockPositions[i]));
    //     }
    // }

#if DEV
    void TryGettingGhostPositions() {
        auto ripGhost = GetPathForRootMapFromGhost();
        trace("Found " + ripGhost.Length + " ripGhost positions to draw.");
        for (uint i = 0; i < ripGhost.Length; i += 20) {
            auto item = ripGhost[i];
            trace("ix:" + i + " -- " + item.ToString());
        }
        yield();
        for (uint i = 0; i < ripGhost.Length; i++) {
            ObservePlayerInWorld(ripGhost[i], 10000);
        }
    }
#endif

    vec2 tl;
    vec2 wh;
    float sideLen;
    float spacing;
    bool bigMiniMap = false;

    void PrepMinMapVars() {
        sideLen = bigMiniMap ? S_BigMiniMapSize : S_MiniMapSize;
        spacing = sideLen / NbGridParts;
        wh = F2Vec(sideLen);
        tl = bigMiniMap ? (GetScreenWH() - wh) / 2 : GetScreenWH() * S_MiniMapPosition / 100;
        if (mmIsScreenShot) {
            float x = wh.x;
            wh.x *= mws.aspectRatio;
            float extra = wh.x - x;
            tl.x -= extra / (bigMiniMap ? 2. : 1.);
        }
    }

    uint get_onPlayerTick() { return 3 * NbGridParts; }
    // for keeping track of where are player hotspots
    float avgObvsPerSquare = 1;
    const uint tickDown = 1;

    vec2[] playerScreenPositions;
    vec2[] playerGridPositions;
    vec3[] playerPositions;
    vec3[] playerDirs;
    vec3[] playerUps;
    CSmPlayer@[] players;

    uint warnedTooManyPlayersCount = 0;

    void ObservePlayer(uint i, CSceneVehicleVis@ vis, CSmPlayer@ player) {
        if (i >= players.Length) {
            if (i == players.Length && warnedTooManyPlayersCount < 10) {
                warn("Tried to observe too many players.");
                warnedTooManyPlayersCount++;
            }
            return;
        }
        // bool isGhost = player is null;
        @players[i] = player;
        playerUps[i] = vis.AsyncState.Up;
        playerDirs[i] = vis.AsyncState.Dir;
        playerPositions[i] = vis.AsyncState.Position;
        auto gridPos = WorldToGridPosF(vis.AsyncState.Position);
        playerGridPositions[i] = gridPos;
        playerScreenPositions[i] = GetMMPosRect(gridPos).xyz.xy;
        if (!mmIsScreenShot) {
            ObservePlayerInWorld(gridPos);
        }
        UpdateMinMaxPlayerGridPos(i, gridPos);
    }

    vec2 minPlayerGridPos, maxPlayerGridPos;

    void UpdateMinMaxPlayerGridPos(uint i, vec2 gridPos) {
        if (i == 0) {
            minPlayerGridPos = gridPos;
            maxPlayerGridPos = gridPos;
        } else {
            if (gridPos.x < minPlayerGridPos.x) minPlayerGridPos.x = gridPos.x;
            if (gridPos.y < minPlayerGridPos.y) minPlayerGridPos.y = gridPos.y;
            if (gridPos.x > maxPlayerGridPos.x) maxPlayerGridPos.x = gridPos.x;
            if (gridPos.y > maxPlayerGridPos.y) maxPlayerGridPos.y = gridPos.y;
        }
    }

    void ObservePlayers() {
        auto scene = GetApp().GameScene;
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        if (scene is null || cp is null) return;
        auto viss = VehicleState::GetAllVis(scene);
        CSmPlayer@ viewingPlayer = VehicleState::GetViewingPlayer();
        int viewingIx = -1;
        if (viss.Length == 0) return;
        playerDirs.Resize(viss.Length);
        playerUps.Resize(viss.Length);
        playerPositions.Resize(viss.Length);
        playerGridPositions.Resize(viss.Length);
        playerScreenPositions.Resize(viss.Length);
        players.Resize(viss.Length);
        uint ix;
        uint skipped = 0;
        for (ix = 0; ix < cp.Players.Length; ix++) {
            auto player = cast<CSmPlayer>(cp.Players[ix]);
            auto vis = VehicleState::GetVis(scene, player);
            if (vis is null) {
                skipped++;
            } else {
                ObservePlayer(ix - skipped, vis, player);
                if (S_FocusModeJustMe && viewingPlayer !is null && player.Id.Value == viewingPlayer.Id.Value) {
                    viewingIx = ix - skipped;
                }
            }
        }
        ix -= skipped;
        for (uint i = 0; i < viss.Length; i++) {
            auto vis = viss[i];
            if (VisIsPlayer(vis)) continue;
            ObservePlayer(ix, vis, null);
            ix++;
        }

        if (S_FocusModeJustMe && viewingIx >= 0) {
            UpdateMinMaxPlayerGridPos(0, playerGridPositions[viewingIx]);
        }

        CalcZoomFactor();
    }

    float zoomFactor = 1., sizeZoom = 1.;
    // the point around which to zoom, measured in uv coords between 0 and 1. (.5, .5) is the center of the map.
    vec2 zoomAround = vec2(.5, .5);
    vec2 pxZoomAround;
    mat3 zoomScale, pxToZoomedPx;

    void CalcZoomFactor() {
        auto lastZoomF = zoomFactor;
        auto lastZoomAround = pxZoomAround;
        vec2 aspectVec = vec2(mws is null ? 1. : mws.aspectRatio, 1.);
        // for use with a bg image in small mode
        if (!mmIsScreenShot || mws is null || playerPositions.Length == 0 || !S_FocusModeSmall) {
            zoomFactor = 1.;
            zoomAround = vec2(.5, .5);
        } else if (Vec2Eq(minPlayerGridPos, maxPlayerGridPos)) {
            zoomFactor = 1. / (S_FocusModePadding / 100. * 2.);
            zoomAround = minPlayerGridPos / aspectVec;
        } else {
            // scale x by mws.aspectRatio so min/max values should be between 0 and 1;
            // print(minPlayerGridPos.ToString() + ", " + maxPlayerGridPos.ToString());
            auto playersBoxSize = (maxPlayerGridPos - minPlayerGridPos) / aspectVec;
            // print("players box size: " + playersBoxSize.ToString());
            auto span = Math::Max(playersBoxSize.x, playersBoxSize.y) + (S_FocusModePadding / 100. * 2.);
            zoomFactor = 1. / span;
            // print(''+zoomFactor);
            zoomAround = minPlayerGridPos / aspectVec + playersBoxSize / 2.;
            if (span > 1) zoomAround = vec2(.5, .5);

            // print('zoomAround: ' + zoomAround.ToString() + ", box size: " + playersBoxSize.ToString() + ", span: " + span);
        }
        pxZoomAround = tl + wh * zoomAround;
        float lerpAmt = 0.08;
        if (lastZoomAround.LengthSquared() > 0) {
            auto ls = (pxZoomAround - lastZoomAround).LengthSquared();
            if (ls < 0.001)
                lerpAmt = 0.5;
            if ((pxZoomAround - lastZoomAround).LengthSquared() > 0.0004)
                pxZoomAround = Math::Lerp(lastZoomAround, pxZoomAround, lerpAmt);
        }

        zoomFactor = Math::Clamp(zoomFactor, 1., 8.);
        zoomFactor = Math::Lerp(lastZoomF, zoomFactor, lerpAmt);
        zoomScale = mat3::Scale(zoomFactor);
        sizeZoom = bigMiniMap ? 1. : (zoomFactor ** 0.4);

        pxToZoomedPx = mat3::Translate(pxZoomAround * vec2(1, 1)) * zoomScale * mat3::Translate(pxZoomAround * vec2(-1, -1));

        // vec2 zoomAroundCorrection = ;
        pxToZoomedPx = mat3::Translate((tl + wh / 2.) - pxZoomAround) * pxToZoomedPx;

        vec2 padding = vec2(S_FocusModePadding / 100., S_FocusModePadding / 100.);
        auto minPlayerVirtPos = MaxVec2(vec2(0, 0), (minPlayerGridPos / aspectVec - padding));
        auto maxPlayerVirtPos = MinVec2(vec2(1, 1), (maxPlayerGridPos / aspectVec + padding));
        vec2 minPlayerPx = (pxToZoomedPx * (minPlayerVirtPos * wh + tl)).xy;
        vec2 maxPlayerPx = (pxToZoomedPx * (maxPlayerVirtPos * wh + tl)).xy;
        vec2 correctionMinRef = vec2(Math::Min(minPlayerPx.x, tl.x), Math::Min(minPlayerPx.y, tl.y));
        vec2 correctionMaxRef = vec2(Math::Min(maxPlayerPx.x, tl.x), Math::Min(maxPlayerPx.y, tl.y));
        vec2 cmrTrans = tl - correctionMinRef;
        vec2 correctionMin = vec2(Math::Max(0, cmrTrans.x), Math::Max(0, cmrTrans.y));
        pxToZoomedPx = mat3::Translate(correctionMin) * pxToZoomedPx;
        cmrTrans = correctionMaxRef - tl - wh;
        vec2 correctionMax = vec2(Math::Max(0, cmrTrans.x), Math::Max(0, cmrTrans.y)) * -1;
        pxToZoomedPx = mat3::Translate(correctionMax) * pxToZoomedPx;

        if (!S_FocusModeSmall) {
            pxToZoomedPx = mat3::Identity();
        }

        // transCorrection = mat3::Translate();
        // print('tl: ' + tl.ToString() + ', pxZoomAround: ' + pxZoomAround.ToString());
        // pxToZoomedPx = mat3::Translate(pxZoomAround * -1.) * zoomScale * mat3::Translate(pxZoomAround);
    }

    int2 WorldToGridPos(vec3 world) {
        auto gridPos = (world - min) / maxXZLen * S_MiniMapGridParts;
        return int2(int(gridPos.x), int(gridPos.z));
    }

    vec2 WorldToGridPosF(vec3 world) {
        if (mmIsScreenShot) {
            // auto cameraPos = vec3(.x - m_offset.x, CameraHeight, minimapMidPoint.z - m_offset.y);
            vec2 ret = (mws.ProjectPoint(world) + vec2(1., 1.)) / 2.;
            ret.x = ret.x * mws.aspectRatio;
            // trace('world: ' + world.ToString() + " -> " + ret.ToString());
            return ret;
            // world = (mws.trans * (mat4::Inverse(mws.trans * mws.rot) * world)).xyz * vec3(1, 1, 1);
        }
        auto gridPos = (world - min) / maxXZLen * NbGridParts;
        return vec2(gridPos.x, gridPos.z); // +- 0.5?
    }

    void ObservePlayerInWorld(vec3 pos, float weight = 1.0) {
        ObservePlayerInWorld(WorldToGridPosF(pos), weight);
    }

    void ObservePlayerInWorld(vec2 gridPos, float weight = 1.0) {
        if (gridPos.x < 0 || gridPos.x > float(NbGridParts)) return;
        if (gridPos.y < 0 || gridPos.y > float(NbGridParts)) return;
        NotePlayerAt(gridPos, weight);
    }
    void NotePlayerAt(vec2 p, float weight = 1.0) {
        // we overlap 4 coords
        auto xr = p.x % 1;
        auto yb = p.y % 1;
        auto rb = xr * yb;
        auto rt = xr * (1 - yb);
        auto lb = (1-xr) * yb;
        auto lt = (1 - xr) * (1 - yb);
        auto x = int(p.x);
        auto y = int(p.y);
        int _max = int(NbGridParts);
        if (x < 0 || x >= _max || y < 0 || y >= _max) return;
        if (minimapPlayerObservations.Length != _max || minimapPlayerObservations[y].Length != _max) return;
        // sometimes an index OOB exception happens below, so exit if lengths don't seem right
        minimapPlayerObservations[y][x] += uint(lt * onPlayerTick);
        if (x+1 < _max) minimapPlayerObservations[y][x+1] += uint(rt * onPlayerTick);
        if (y+1 < _max) minimapPlayerObservations[y+1][x] += uint(lb * onPlayerTick);
        if (x+1 < _max && y+1 < _max)
            minimapPlayerObservations[y+1][x+1] += uint(rb * onPlayerTick * weight);
    }

    /* main drawing logic */

    void DrawMiniMapBackground() {
        nvg::Reset();
        nvg::BeginPath();
        nvg::Rect(tl, wh);
        // nvg::FillColor(vec4(1, Math::Abs(Time::Now / 1000.0 % 2.0 - 1), 0, 1));
        nvg::FillColor(bigMiniMap ? vec4(0, 0, 0, .5) : vec4(0, 0, 0, .2));
        nvg::Fill();
        nvg::ClosePath();
    }

    void DrawBigMmBgColor() {
        nvg::Reset();
        nvg::BeginPath();
        nvg::Rect(vec2(), vec2(Draw::GetWidth(), Draw::GetHeight()));
        nvg::FillColor(S_BigBg_Color);
        nvg::Fill();
        nvg::ClosePath();
    }

    void DrawMiniMapBackgroundImage() {
        if (mmBgTexture is null) return;
        vec2 texTL = tl;
        vec2 drawWH = wh;
        if (S_FocusModeSmall && !bigMiniMap && zoomFactor != 1.) {
            texTL = (pxToZoomedPx * texTL).xy;
            drawWH = (zoomScale * drawWH).xy;
        }
        nvg::Reset();
        nvg::BeginPath();
        nvg::Rect(tl, wh);
        nvg::FillPaint(nvg::TexturePattern(texTL, drawWH, 0, mmBgTexture, S_BgImageAlpha));
        if (zoomFactor > 1. && !bigMiniMap) {
            vec2 sTL = (pxToZoomedPx * GetMMPosRect(vec2(0, 0)).xyz.xy).xy;
            vec2 sWH = (pxToZoomedPx * GetMMPosRect(vec2(mws.aspectRatio, 1)).xyz.xy).xy - sTL;
            nvg::Scissor(sTL.x, sTL.y, sWH.x, sWH.y);
        }
        nvg::Fill();
        nvg::ClosePath();
        nvg::ResetScissor();
        if (S_ShowDebugShapesFocusMode) {
            nvg::BeginPath();
            nvg::Rect(texTL, drawWH);
            nvg::StrokeWidth(3.);
            nvg::Ellipse((pxToZoomedPx * pxZoomAround).xy, 10, 20);
            nvg::Circle((pxToZoomedPx * GetMMPosRect(minPlayerGridPos).xyz.xy).xy, 10);
            nvg::Circle((pxToZoomedPx * GetMMPosRect(maxPlayerGridPos).xyz.xy).xy, 10);
            nvg::StrokeColor(vec4(1, .5, .0, 1.)); nvg::Stroke();
            nvg::ClosePath();
        }
    }

    void DrawMiniMapPlayerObservations() {
        uint totObs = 0; // totalObservations
        uint maxObs = 0;
        uint reduce;
        for (uint y = 0; y < minimapPlayerObservations.Length; y++) {
            auto xs = minimapPlayerObservations[y];
            for (uint x = 0; x < xs.Length; x++) {
                auto count = xs[x];
                if (count == 0) continue;
                DrawPlayerObservationCount(vec2(x, y), count);
                totObs += count;
                maxObs = Math::Max(count, maxObs);
                reduce = !S_FadeGridSquares ? 0 : Math::Max(tickDown, uint(xs[x] / NbGridParts / S_GridSquarePersistence)); // should reduce larger numbers faster than relying on tickdown
                if (count >= reduce)
                    xs[x] -= reduce;
                else
                    xs[x] = 0;
            }
        }
        float totalSqs = float(NbGridParts * NbGridParts);
        avgObvsPerSquare = float(totObs) / totalSqs;
    }

    void DrawMiniMapBlocks() {
        // for (uint i = 0; i < blockGridPositions.Length; i++) {
        //     DrawPlayerAt(blockGridPositions[i], vec4(1,0,0,1));
        // }
    }

    void DrawMiniMapCheckpoints() {
        for (uint i = 0; i < cpPositions.Length; i++) {
            DrawMarkerAt(WorldToGridPosF(cpPositions[i]), vec3(0, 1, 0), GetCpColor(cpPositions.types[i]), S_CP_Shape, S_CP_Size);
        }
    }

    vec4 GetCpColor(CpType type) {
        switch (type) {
            case CpType::Goal: return S_Goal_Color;
            case CpType::Spawn: return S_Spawn_Color;
            case CpType::Checkpoint:
            default:
                return S_CP_Color;
        }
    }

    void DrawMiniMapCheckpointLinks() {
        vec2 offset = F2Vec(-.5);
        nvg::Reset();
        nvg::BeginPath();
        for (uint i = 0; i < linkedCpPositions.Length; i++) {
            auto linkedPoss = linkedCpPositions[i];
            // trace('linkedPoss of length: ' + linkedPoss.Length);
            for (uint x = 0; x < linkedPoss.Length; x++) {
                auto xPos = linkedPoss[x];
                for (uint y = 0; y < x; y++) {
                    auto yPos = linkedPoss[y];
                    // trace('drawing LCP: ' + xPos.ToString() + ' to ' + yPos.ToString());
                    nvg::MoveTo(GetMMPosRect(WorldToGridPosF(xPos) - offset).xyz.xy);
                    nvg::LineTo(GetMMPosRect(WorldToGridPosF(yPos) - offset).xyz.xy);
                }
            }
        }
        nvg::LineCap(nvg::LineCapType::Round);
        nvg::StrokeWidth(2.5 * ScaleFactor);
        nvg::StrokeColor(S_Linked_Color);
        nvg::Stroke();
        nvg::ClosePath();
    }

    // Get entity ID of the given vehicle vis. (From VehicleNext.as in VehicleState)
	uint GetEntityId(CSceneVehicleVis@ vis)
	{
		return Dev::GetOffsetUint32(vis, 0);
	}

    bool VisIsPlayer(CSceneVehicleVis@ vis) {
        return ((GetEntityId(vis) & 0xFF000000) != 0x04000000);
    }

    void DrawMiniMapPlayers() {
        if (GetApp().GameScene is null) return;
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        auto scene = GetApp().GameScene;
        if (cp is null) return;

        auto viss = VehicleState::GetAllVis(scene);
        for (uint i = 0; i < viss.Length; i++) {
            // only draw ghosts here
            // if ((GetEntityId(viss[i]) & 0xFF000000) != 0x04000000) continue;
            if (VisIsPlayer(viss[i])) continue;
            DrawMarkerAt(WorldToGridPosF(viss[i].AsyncState.Position), viss[i].AsyncState.Dir, viss[i].AsyncState.Up, S_Player_Color, S_Player_Shape, S_Player_Size);
        }

        // draw players after, with names
        for (uint i = 0; i < cp.Players.Length; i++) {
            auto player = cast<CSmPlayer>(cp.Players[i]);
            auto vis = VehicleState::GetVis(scene, player);
            if (vis is null) continue;
            auto team = player.EdClan;
            auto col = GetPlayerColForTeam(team);
            bool drewPlayer = DrawMarkerAt(WorldToGridPosF(vis.AsyncState.Position), vis.AsyncState.Dir, vis.AsyncState.Up, col, S_Player_Shape, S_Player_Size);
            if (S_DrawPlayerNames && drewPlayer && (bigMiniMap || S_DrawPlayerNamesInSmall))
                DrawPlayerName(vis, player);
        }
    }

    vec4 GetPlayerColForTeam(uint team) {
        if (team == 1) return S_BlueTeamColor;
        if (team == 2) return S_RedTeamColor;
        return S_Player_Color;
    }

    vec4 GetPlayerNameBgColForTeam(uint team) {
        if (team == 1) return S_BlueTeamColor * vec4(1, 1, 1, .5);
        if (team == 2) return S_RedTeamColor * vec4(1, 1, 1, .5);
        return vec4(0, 0, 0, .6);
    }

    void DrawMiniMapCamera() {
        auto cam = Camera::GetCurrent();
        if (cam is null) return;
        auto nextLoc = cam.NextLocation;
        vec3 dir = vec3(nextLoc.xz, nextLoc.yz, nextLoc.zz);
        DrawMarkerAt(WorldToGridPosF(Camera::GetCurrentPosition()), dir, S_Camera_Color, S_Camera_Shape, S_Camera_Size);
    }

    void DrawPlayerName(CSceneVehicleVis@ vis, CSmPlayer@ player) {
        if (vis is null) return;
        // auto pos = vis.AsyncState.Position;
        string name = player.User.Name;
        auto team = player.EdClan;
        auto bgCol = GetPlayerNameBgColForTeam(team);
        float fs = S_PlayerName_FontSize * ScaleFactor * sizeZoom;
        nvg::FontSize(fs);
        nvg_SetFontFaceChoice();
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);
        auto bounds = nvg::TextBounds(name);
        auto playerPos = GetMMPosRect(WorldToGridPosF(vis.AsyncState.Position)).xyz.xy;
        if (zoomFactor > 1. && !bigMiniMap) {
            playerPos = (pxToZoomedPx * playerPos).xy;
        }
        auto nameMid = playerPos + vec2(0, -1.25 * fs);
        auto boxBounds = bounds * 1.1;
        auto boxTL = nameMid - (boxBounds / 2.);
        boxTL.y -= fs * 0.05;
        nvg::BeginPath();
        nvg::Rect(boxTL, boxBounds);
        nvg::FillColor(bgCol);
        nvg::Fill();
        nvg::ClosePath();
        nvg::FillColor(vec4(1, 1, 1, 1));
        nvg::Text(nameMid, name);
    }

    /* drawing helpers */

    void DrawPlayerObservationCount(vec2 xy, uint count) {
        if (count == 0) return;
        vec4 rect = GetMMPosRect(xy);
        nvg::BeginPath();
        nvg::Rect(rect.x, rect.y, rect.z, rect.w);
        nvg::FillColor(GridSqColor(count));
        nvg::Fill();
        nvg::ClosePath();
    }

    vec4 GridSqColor(uint count) {
        if (count == 0 || avgObvsPerSquare < 0.0001) return vec4();
        auto ret = F4Vec(Math::Min(1.0, float(count) * NbGridParts / 10000));
        return ret;
    }

    void DrawMMGrid() {
        float parts = float(NbGridParts);
        float partWidth = sideLen / parts;
        nvg::Reset();
        nvg::BeginPath();
        for (float x = 0; x <= parts; x++) {
            DrawGridLine(tl + vec2(x*partWidth, 0), sideLen, true); // vertical
            DrawGridLine(tl + vec2(0, x*partWidth), sideLen, false); // horizontal
        }
        nvg::StrokeWidth(1);
        nvg::StrokeColor(vec4(0, 0, 0, .2));
        nvg::Stroke();
        nvg::ClosePath();
    }

    void DrawGridLine(vec2 xy, float len, bool vertical) {
        nvg::MoveTo(xy);
        nvg::LineTo(xy + (vertical ? vec2(0, len) : vec2(len, 0)));
    }

    int NbGridParts {
        get {
            return mmIsScreenShot ? 1 : S_MiniMapGridParts;
        }
    }

    vec4 GetMMPosRect(vec2 pos) {
        float mmGridParts = NbGridParts;
        vec2 xy = tl + pos * wh.y / mmGridParts;
        vec2 _wh = wh / mmGridParts;
        return vec4(xy.x, xy.y, _wh.x, _wh.y);
    }

    void nvgIndicatorStrokeFill(vec4 col, bool doFill = true) {
        nvg::FillColor(col);
        if (doFill) {
            nvg::Fill();
            nvg::StrokeWidth(.4);
        } else {
            auto widthMod = (bigMiniMap || S_BigMiniMapSize == 0 ? 1. : float(S_MiniMapSize) / float(S_BigMiniMapSize));
            nvg::StrokeWidth(Draw::GetHeight() / 150. * widthMod * sizeZoom);
        }
        nvg::StrokeColor(col);
        nvg::Stroke();
    }

    void DrawMarkerAt(vec2 pos, vec3 dir, vec4 col, MiniMapShapes shape, float size) {
        DrawMarkerAt(pos, dir, vec3(0, 1, 0), col, shape, size);
    }

    mat4 ImageRotation {
        get {
            if (mmIsScreenShot) return mws.imgRot;
            return mat4::Identity();
        }
    }

    bool DrawMarkerAt(vec2 pos, vec3 dir, vec3 up, vec4 col, MiniMapShapes shape, float size) {
        size *= sizeZoom;
        // if there is no xz component to the direction vector.
        if (dir.x == dir.z && dir.z == 0) {
            // shape = MiniMapShapes::Circle;
            dir = vec3(1, 0, 0);
        }
        float rotateAroundDir = Math::Angle(up, vec3(0, 1, 0));
        if (mmIsScreenShot) {
            // dir = (mat4::Inverse(mws.imgRot) * dir).xyz * -1.;
            dir = (mat4::Inverse(ImageRotation) * dir).xyz * -1;
        }
        size = size * ScaleFactor;
        vec2 _off = mmIsScreenShot ? vec2() : F2Vec(.5);
        vec4 rect = GetMMPosRect(pos + _off);
        vec2 pxPos = rect.xyz.xy;

        // apply zoom
        if (S_FocusModeSmall && !bigMiniMap && zoomFactor != 1. && mws !is null) {
            // in this mode, we don't draw objects outside the MM bounds
            auto uv = pos / vec2(mws.aspectRatio, 1.);
            pxPos = (pxToZoomedPx * pxPos).xy;
            auto lims = tl + wh;
            if (pxPos.x < tl.x - size || pxPos.y < tl.y - size || pxPos.x > lims.x + size || pxPos.y > lims.y + size)
                return false;
        }

        nvg::Reset();
        nvg::BeginPath();
        switch (shape) {
            case MiniMapShapes::Circle:
            case MiniMapShapes::Ring:
                nvg::Circle(pxPos, size / 2);
            break;
            case MiniMapShapes::Arrow:
                nvgArrow(pxPos, size, dir, rotateAroundDir, col);
            break;
            case MiniMapShapes::TriArrow:
                nvgTriArrow(pxPos, size, dir, rotateAroundDir, col);
            break;
            case MiniMapShapes::QuadArrow:
                nvgQuadArrow(pxPos, size, dir, rotateAroundDir, col);
            break;
            case MiniMapShapes::Square:
            default:
                nvg::Rect(pxPos.x - size / 2., pxPos.y - size / 2., size, size);
            break;
        }
        bool noFill = shape == MiniMapShapes::Ring || false;
        nvgIndicatorStrokeFill(col, !noFill);
        nvg::ClosePath();
        return true;
    }

    float get_BaseScaleFactor() {
        return Draw::GetHeight() / 1080.0;
    }

    float get_ScaleFactor() {
        return BaseScaleFactor * (bigMiniMap ? float(S_BigMiniMapSize) / float(S_MiniMapSize) : 1.0);
    }

    float TAU = 6.28318530717958647692;
    mat3 rotateLeft90 = mat3::Rotate(TAU / 4.);
    mat3 rotate180 = mat3::Rotate(TAU / 2.);
    mat3 rotateRight90 = mat3::Rotate(- TAU / 4.);

    mat4 rotate4Left90 = mat4::Rotate(-TAU / 4., vec3(0, 1, 0));

    mat4 CamDiffRotation {
        get {
            if (mmIsScreenShot) return mws.camDiffRot;
            return mat4::Identity();
        }
    }

    /**
     * something like this:
     *      /\
     *     /  \
     *    / /\ \
     *    V    V
     */
    void nvgArrow(vec2 pos, float size, vec3 &in dir, float angle, vec4 col) {
        mat4 pTrans = mat4::Translate(vec3(pos.x, 0, pos.y));
        auto dirNormd = dir.Normalized();
        // shift pos back a bit to center the arrow better
        // pos -= dirNormd * .25;
        auto dirLeft = (rotate4Left90 * dirNormd).xyz;
        vec3 tip = dirNormd * size;
        vec3 bl = (dirLeft - dirNormd) * size / 1.7;
        vec3 br = (dirLeft + dirNormd) * size / -1.7;

        // rotations
        // mat4::Inverse
        auto tmpRot = CamDiffRotation * mat4::Rotate(angle, dir);
        tip = (pTrans * tmpRot * tip).xyz;
        bl = (pTrans * tmpRot * bl).xyz;
        br = (pTrans * tmpRot * br).xyz;

        auto tip2 = vec2(tip.x, tip.z);
        auto bl2 = vec2(bl.x, bl.z);
        auto br2 = vec2(br.x, br.z);

        nvg::MoveTo(tip2);
        nvg::LineTo(br2);
        nvg::LineTo(pos);
        nvg::LineTo(tip2);
        nvgIndicatorStrokeFill(col);
        nvg::ClosePath();
        nvg::BeginPath();
        nvg::MoveTo(tip2);
        nvg::LineTo(pos);
        nvg::LineTo(bl2);
        nvg::LineTo(tip2);
    }

    void nvgQuadArrow(vec2 pos, float size, vec3 &in dir, float angle, vec4 col) {
        // pos -= dirNormd * .25;
        mat4 pTrans = mat4::Translate(vec3(pos.x, 0, pos.y));
        auto dirNormd = dir.Normalized();
        // shift pos back a bit to center the arrow better
        auto dirLeft = (rotate4Left90 * dirNormd).xyz;
        vec3 tip = dirNormd * size;
        vec3 bl = dirLeft * size / 2;
        vec3 br = dirLeft * size / -2;
        vec3 tail = dirNormd * size / -2.;

        // rotations
        // mat4::Inverse
        auto tmpRot = CamDiffRotation * mat4::Rotate(angle, dir);
        tip = (pTrans * tmpRot * tip).xyz;
        bl = (pTrans * tmpRot * bl).xyz;
        br = (pTrans * tmpRot * br).xyz;
        tail = (pTrans * tmpRot * tail).xyz;

        auto tip2 = vec2(tip.x, tip.z);
        auto bl2 = vec2(bl.x, bl.z);
        auto br2 = vec2(br.x, br.z);
        auto tail2 = vec2(tail.x, tail.z);

        nvg::MoveTo(tip2);
        nvg::LineTo(bl2);
        nvg::LineTo(tail2);
        nvg::LineTo(br2);
        nvg::LineTo(tip2);
    }

    void nvgTriArrow(vec2 pos, float size, vec3 &in dir, float angle, vec4 col) {
        mat4 pTrans = mat4::Translate(vec3(pos.x, 0, pos.y));
        auto dirNormd = dir.Normalized();
        // shift pos back a bit to center the arrow better
        // pos -= dirNormd * .25;
        auto dirLeft = (rotate4Left90 * dirNormd).xyz;
        vec3 tip = dirNormd * size;
        vec3 bl = (dirLeft - dirNormd) * size / 1.7;
        vec3 br = (dirLeft + dirNormd) * size / -1.7;

        // rotations
        // mat4::Inverse
        auto tmpRot = CamDiffRotation * mat4::Rotate(angle, dir);
        tip = (pTrans * tmpRot * tip).xyz;
        bl = (pTrans * tmpRot * bl).xyz;
        br = (pTrans * tmpRot * br).xyz;

        auto tip2 = vec2(tip.x, tip.z);
        auto bl2 = vec2(bl.x, bl.z);
        auto br2 = vec2(br.x, br.z);

        // simple triangle
        nvg::MoveTo(tip2);
        nvg::LineTo(br2);
        nvg::LineTo(bl2);
        nvg::LineTo(tip2);
    }
}



vec2 MaxVec2(vec2 a, vec2 b) {
    return vec2(Math::Max(a.x, b.x), Math::Max(a.y, b.y));
}

vec2 MinVec2(vec2 a, vec2 b) {
    return vec2(Math::Min(a.x, b.x), Math::Min(a.y, b.y));
}
