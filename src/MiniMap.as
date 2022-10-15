namespace MiniMap {
    array<vec3> cpPositions;
    vec3 min, max; // map boundaries
    float maxXZLen;
    array<array<uint>> minimapPlayerObservations;
    bool mmStateInitialized = false;
    uint debugLogCount = 0;
    array<vec3> blockPositions;
    array<int2> blockGridPositions;

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
        seenBlocks.DeleteAll();
        trace("cleared minimap state.");
    }

    void InitGrid() {
        minimapPlayerObservations.Resize(S_MiniMapGridParts);
        for (uint i = 0; i < minimapPlayerObservations.Length; i++) {
            auto item = minimapPlayerObservations[i];
            item.Resize(S_MiniMapGridParts);
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

        ConvertBlockPositions();
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
        if (S_DrawGridLines)
            DrawMMGrid();  // ~0.15ms draw time with 50 cols
        DrawMiniMapBackground();
        DrawMiniMapPlayerObservations();
        // DrawMiniMapBlocks();
        DrawMiniMapCheckpoints();
        DrawMiniMapPlayers();
        DrawMiniMapCamera();
    }

    void ConvertBlockPositions() {
        blockGridPositions.RemoveRange(0, blockGridPositions.Length);
        for (uint i = 0; i < blockPositions.Length; i++) {
            blockGridPositions.InsertLast(WorldToGridPos(blockPositions[i]));
        }
    }

    vec2 tl;
    vec2 wh;
    float sideLen;
    float spacing;
    bool bigMiniMap = false;

    void PrepMinMapVars() {
        sideLen = bigMiniMap ? S_BigMiniMapSize : S_MiniMapSize;
        spacing = sideLen / S_MiniMapGridParts;
        wh = F2Vec(sideLen);
        tl = bigMiniMap ? (GetScreenWH() - wh) / 2 : GetScreenWH() * S_MiniMapPosition / 100;
    }

    uint get_onPlayerTick() { return 3 * S_MiniMapGridParts; }
    // for keeping track of where are player hotspots
    float avgObvsPerSquare = 1;
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

    vec2 WorldToGridPosF(vec3 world) {
        auto gridPos = (world - min) / maxXZLen * S_MiniMapGridParts;
        return vec2(gridPos.x, gridPos.z); // +- 0.5?
    }

    void ObservePlayerInWorld(vec3 pos) {
        auto gridPos = WorldToGridPosF(pos);
        if (gridPos.x < 0 || gridPos.x > float(S_MiniMapGridParts)) return;
        if (gridPos.y < 0 || gridPos.y > float(S_MiniMapGridParts)) return;
        NotePlayerAt(gridPos);
    }
    void NotePlayerAt(vec2 p) {
        // we overlap 4 coords
        auto xr = p.x % 1;
        auto yb = p.y % 1;
        auto rb = xr * yb;
        auto rt = xr * (1 - yb);
        auto lb = (1-xr) * yb;
        auto lt = (1 - xr) * (1 - yb);
        auto x = int(p.x);
        auto y = int(p.y);
        int _max = int(S_MiniMapGridParts);
        if (x < 0 || x > _max || y < 0 || y > _max) return;
        minimapPlayerObservations[y][x] += uint(lt * onPlayerTick);
        if (x+1 < _max) minimapPlayerObservations[y][x+1] += uint(rt * onPlayerTick);
        if (y+1 < _max) minimapPlayerObservations[y+1][x] += uint(lb * onPlayerTick);
        if (x+1 < _max && y+1 < _max)
            minimapPlayerObservations[y+1][x+1] += uint(rb * onPlayerTick);
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
                reduce = Math::Max(tickDown, uint(xs[x] / S_MiniMapGridParts / 20.0)); // should reduce larger numbers faster than relying on tickdown
                if (count >= reduce)
                    xs[x] -= reduce;
                else
                    xs[x] = 0;
            }
        }
        float totalSqs = float(S_MiniMapGridParts * S_MiniMapGridParts);
        avgObvsPerSquare = float(totObs) / totalSqs;
    }

    void DrawMiniMapBlocks() {
        // for (uint i = 0; i < blockGridPositions.Length; i++) {
        //     DrawPlayerAt(blockGridPositions[i], vec4(1,0,0,1));
        // }
    }

    void DrawMiniMapCheckpoints() {
        for (uint i = 0; i < cpPositions.Length; i++) {
            DrawMarkerAt(WorldToGridPosF(cpPositions[i]), S_CP_Color, S_CP_Shape, S_CP_Size);
        }
    }

    void DrawMiniMapPlayers() {
        if (GetApp().GameScene is null) return;
        auto viss = VehicleState::GetAllVis(GetApp().GameScene);
        for (uint i = 0; i < viss.Length; i++) {
            DrawMarkerAt(WorldToGridPosF(viss[i].AsyncState.Position), S_Player_Color, S_Player_Shape, S_Player_Size);
        }
    }

    void DrawMiniMapCamera() {
        DrawMarkerAt(WorldToGridPosF(Camera::GetCurrentPosition()), S_Camera_Color, S_Camera_Shape, S_Camera_Size);
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
        auto ret = F4Vec(Math::Min(1.0, float(count) / avgObvsPerSquare));
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

    void DrawMarkerAt(vec2 pos, vec4 col, MiniMapShapes shape, float size) {
        size = size * Draw::GetHeight() / 1080.0 * (bigMiniMap ? float(S_BigMiniMapSize) / float(S_MiniMapSize) : 1.0);
        vec4 rect = GetMMPosRect(pos + F2Vec(.5));
        nvg::BeginPath();
        switch (shape) {
            case MiniMapShapes::Circle:
                nvg::Circle(rect.xyz.xy, size / 2);
            break;
            case MiniMapShapes::Square:
            default:
                nvg::Rect(rect.x, rect.y, size, size);
            break;
        }
        nvg::FillColor(col);
        nvg::Fill();
        nvg::ClosePath();
    }
}
