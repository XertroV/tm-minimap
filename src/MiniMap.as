namespace MiniMap {

    array<vec3> cpPositions;
    vec3 min, max; // map boundaries
    float maxXZLen;
    array<array<uint>> minimapPlayerObservations;
    bool mmStateInitialized = false;
    uint debugLogCount = 0;

    void ClearMiniMapState() {
        mmStateInitialized = false;
        debugLogCount = 0;
        cpPositions.RemoveRange(0, cpPositions.Length);
        if (minimapPlayerObservations.Length != S_MiniMapGridParts) InitGrid();
        for (uint y = 0; y < minimapPlayerObservations.Length; y++) {
            auto xs = minimapPlayerObservations[y];
            for (uint x = 0; x < xs.Length; x++) {
                xs[x] = 0;
            }
        }
        trace("cleared minimap state.");
    }

    void InitGrid() {
        minimapPlayerObservations.Resize(S_MiniMapGridParts + 1);
        for (uint i = 0; i < minimapPlayerObservations.Length; i++) {
            auto item = minimapPlayerObservations[i];
            item.Resize(S_MiniMapGridParts + 1);
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
            cpPositions = GetCheckpointPositions();
            if (cpPositions.Length > 0) break;
            yield();
        }
        trace("Found " + cpPositions.Length + " unique CPs to draw.");

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

        // add a small amount of padding
        vec3 mapSize = max - min;
        float padding = 0.05;
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
        return;
    }

    void UpdateMiniMap(float dt) {
        if (!mmStateInitialized) return;
        if (!S_UpdateWhenHidden && S_MiniMapState == 0) return;
        PrepMinMapVars();
        ObservePlayers();
    }

    void Render() {
        if (S_MiniMapState == 0) return;
        if (!mmStateInitialized) return;
        DrawMiniMapBackground();
        DrawMiniMapPlayerObservations();
        DrawMiniMapCheckpoints();
        DrawMiniMapPlayers();
        DrawMiniMapCamera();
    }

    void LogMMUpdate() {
#if DEV
    if (debugLogCount < 100) {
        debugLogCount++;
        trace('MM update called. Initialized? ' + (mmStateInitialized ? 'yes' : 'no'));
    }
#endif
    }

    vec2 tl;
    vec2 wh;
    // vec2 bigTL;
    // vec2 bigWH;
    float sideLen;
    float spacing;
    bool bigMiniMap = false;
    // vec2 get_tl() { return bigMiniMap ? bigTL : _tl; }
    // vec2 get_wh() { return bigMiniMap ? bigWH : _wh; }

    void PrepMinMapVars() {
        sideLen = bigMiniMap ? Draw::GetHeight()/2 : S_MiniMapSize;
        spacing = sideLen / S_MiniMapGridParts;
        wh = F2Vec(sideLen);
        tl = bigMiniMap ? (GetScreenWH() - wh) / 2 : GetScreenWH() * S_MiniMapPosition / 100;
    }

    uint onPlayerTick = 3 * S_MiniMapGridParts;
    // for keeping track of where are player hotspots
    float avgObvsPerSquare;
    const uint tickDown = 1;

    void ObservePlayers() {
        if (GetApp().GameScene is null) return;
        auto viss = VehicleState::GetAllVis(GetApp().GameScene);
        for (uint i = 0; i < viss.Length; i++) {
            auto vis = viss[i];
            ObservePlayerInWorld(vis.AsyncState.Position);
        }
    }

    int2 WorldToGridPos(vec3 world) {
        auto gridPos = (world - min) / maxXZLen * S_MiniMapGridParts;
        return int2(int(gridPos.x), int(gridPos.z));
    }

    void ObservePlayerInWorld(vec3 pos) {
        auto gridPos = WorldToGridPos(pos);
        if (gridPos.x < 0 || gridPos.x > int(S_MiniMapGridParts)) return;
        if (gridPos.y < 0 || gridPos.y > int(S_MiniMapGridParts)) return;
        minimapPlayerObservations[gridPos.y][gridPos.x] += onPlayerTick;
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

    void DrawMiniMapPlayerObservations() {
        DrawMMGrid();  // 30% draw time with ~30 cols
        uint totObs = 0; // totalObservations
        uint maxObs = 0;
        for (uint y = 0; y < minimapPlayerObservations.Length; y++) {
            auto xs = minimapPlayerObservations[y];
            for (uint x = 0; x < xs.Length; x++) {
                auto count = xs[x];
                if (count == 0) continue;
                DrawPlayerObservationCount(vec2(x, y), count);
                totObs += count;
                maxObs = Math::Max(count, maxObs);
                if (count >= tickDown)
                    xs[x] -= tickDown;
                else
                    xs[x] = 0;
            }
        }
        float totalSqs = float(S_MiniMapGridParts * S_MiniMapGridParts);
        avgObvsPerSquare = float(totObs) / totalSqs;
    }

    void DrawMiniMapCheckpoints() {
        for (uint i = 0; i < cpPositions.Length; i++) {
            DrawCpAt(WorldToGridPos(cpPositions[i]));
        }
    }

    void DrawMiniMapPlayers() {
        if (GetApp().GameScene is null) return;
        auto viss = VehicleState::GetAllVis(GetApp().GameScene);
        for (uint i = 0; i < viss.Length; i++) {
            DrawPlayerAt(WorldToGridPos(viss[i].AsyncState.Position));
        }
    }

    void DrawMiniMapCamera() {
        DrawPlayerAt(WorldToGridPos(Camera::GetCurrentPosition()), S_Camera_Color);
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
        if (count == 0) return vec4();
        auto ret = F4Vec(Math::Max(1.0, float(count) / 30.0)) * vec4(.5, .5, .5, .2);
        // ret.w /= 3.0;
        return ret;
    }

    void DrawMMGrid() {
        float parts = float(S_MiniMapGridParts);
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

    vec4 GetMMPosRect(vec2 pos) {
        auto xy = tl + pos * wh / float(S_MiniMapGridParts);
        auto _wh = wh / S_MiniMapGridParts;
        return vec4(xy.x, xy.y, _wh.x, _wh.y);
    }

    void DrawCpAt(int2 pos) {
        DrawPlayerAt(pos, S_CP_Color);
    }

    void DrawPlayerAt(int2 pos, vec4 col = S_Player_Color) {
        vec4 rect = GetMMPosRect(vec2(pos.x, pos.y));
        nvg::BeginPath();
        nvg::Rect(rect.x, rect.y, rect.z, rect.w);
        nvg::FillColor(col);
        nvg::Fill();
        nvg::ClosePath();
    }
}
