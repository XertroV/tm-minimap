namespace MiniMap {
    array<vec3> cpPositions;
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
        mmStateInitialized = false;
        mmIsScreenShot = false;
        @mws = null;
        @mmBgTexture = null;
        debugLogCount = 0;
        cpPositions.RemoveRange(0, cpPositions.Length);
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
            cpPositions = GetCheckpointPositions();
            if (cpPositions.Length > 0) break;
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
            if (mws !is null) {
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
        @mmBgTexture = nvg::LoadTexture(mws.ReadImageFile());
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
            max += vec3(50, 0, 50);
            min -= vec3(50, 0, 50);
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

    void UpdateMiniMap(float dt) {
        if (!IsEditorConditionCheckOkay) return;
        if (!mmStateInitialized) return;
        if (!S_UpdateWhenHidden && S_MiniMapState == 0) return;
        PrepMinMapVars();
        if (!mmIsScreenShot)
            ObservePlayers();
    }

    void Render() {
        if (S_MiniMapState == 0) return;
        if (!mmStateInitialized) return;
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

        // calc screen shot equiv
        // vec2 xy = vec2(world.x, world.z);
        // vec3 newPos = (mws.rot * (world - mws.center3)).xyz;
        // trace('world: ' + world.ToString() + " -> " + newPos.ToString());
        // auto xy = vec2(newPos.x, newPos.z) / maxXZLen * NbGridParts;
        // return xy;
    }

    void ObservePlayerInWorld(vec3 pos, float weight = 1.0) {
        auto gridPos = WorldToGridPosF(pos);
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

    void DrawMiniMapBackgroundImage() {
        if (mmBgTexture is null) return;
        // float oldW = wh.x;
        // auto imgSize = mmBgTexture.GetSize();
        // float aspect = imgSize.x / imgSize.y;
        // auto _wh = vec2(wh.x * aspect, wh.y);
        // auto _tl = vec2(tl.x - (_wh.x - wh.x), tl.y);
        nvg::Reset();
        nvg::BeginPath();
        nvg::Rect(tl, wh);
        nvg::FillPaint(nvg::TexturePattern(tl, wh, 0, mmBgTexture, S_BgImageAlpha));
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
            DrawMarkerAt(WorldToGridPosF(cpPositions[i]), vec3(0, 1, 0), S_CP_Color, S_CP_Shape, S_CP_Size);
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

    void DrawMiniMapPlayers() {
        if (GetApp().GameScene is null) return;
        auto viss = VehicleState::GetAllVis(GetApp().GameScene);
        for (uint i = 0; i < viss.Length; i++) {
            DrawMarkerAt(WorldToGridPosF(viss[i].AsyncState.Position), viss[i].AsyncState.Dir, S_Player_Color, S_Player_Shape, S_Player_Size);
        }
    }

    void DrawMiniMapCamera() {
        auto cam = Camera::GetCurrent();
        if (cam is null) return;
        auto nextLoc = cam.NextLocation;
        vec3 dir = vec3(nextLoc.xz, nextLoc.yz, nextLoc.zz);
        DrawMarkerAt(WorldToGridPosF(Camera::GetCurrentPosition()), dir, S_Camera_Color, S_Camera_Shape, S_Camera_Size);
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

    void nvgIndicatorStrokeFill(vec4 col) {
        nvg::FillColor(col);
        nvg::Fill();
        nvg::StrokeWidth(.4);
        nvg::StrokeColor(col);
        nvg::Stroke();
    }

    void DrawMarkerAt(vec2 pos, vec3 dir, vec4 col, MiniMapShapes shape, float size) {
        // if there is no xz component to the direction vector, make the shape a circle.
        if (dir.x == dir.z && dir.z == 0) {
            shape = MiniMapShapes::Circle;
        }
        if (mmIsScreenShot) {
            dir = (mat4::Inverse(mws.imgRot) * dir).xyz * -1.;
        }
        size = size * ScaleFactor;
        vec2 _off = mmIsScreenShot ? vec2() : F2Vec(.5);
        vec4 rect = GetMMPosRect(pos + _off);
        nvg::Reset();
        nvg::BeginPath();
        switch (shape) {
            case MiniMapShapes::Circle:
                nvg::Circle(rect.xyz.xy, size / 2);
            break;
            case MiniMapShapes::Arrow:
                nvgArrow(rect.xyz.xy, size, vec2(dir.x, dir.z), col);
            break;
            case MiniMapShapes::TriArrow:
                nvgTriArrow(rect.xyz.xy, size, vec2(dir.x, dir.z), col);
            break;
            case MiniMapShapes::QuadArrow:
                nvgQuadArrow(rect.xyz.xy, size, vec2(dir.x, dir.z), col);
            break;
            case MiniMapShapes::Square:
            default:
                nvg::Rect(rect.x, rect.y, size, size);
            break;
        }
        nvgIndicatorStrokeFill(col);
        nvg::ClosePath();
    }

    float get_ScaleFactor() {
        return Draw::GetHeight() / 1080.0 * (bigMiniMap ? float(S_BigMiniMapSize) / float(S_MiniMapSize) : 1.0);
    }

    float TAU = 6.28318530717958647692;
    mat3 rotateLeft90 = mat3::Rotate(TAU / 4.);
    mat3 rotate180 = mat3::Rotate(TAU / 2.);
    mat3 rotateRight90 = mat3::Rotate(- TAU / 4.);


    /**
     * something like this:
     *      /\
     *     /  \
     *    / /\ \
     *    V    V
     */
    void nvgArrow(vec2 pos, float size, vec2 &in dir, vec4 col) {
        auto dirNormd = dir.Normalized();
        // shift pos back a bit to center the arrow better
        // pos -= dirNormd * .25;
        auto dirLeft = (rotateLeft90 * dirNormd).xy;
        auto tip = pos + dirNormd * size;
        auto bl = pos + (dirLeft - dirNormd) * size / 1.7;
        auto br = pos - (dirLeft + dirNormd) * size / 1.7;

        nvg::MoveTo(tip);
        nvg::LineTo(br);
        nvg::LineTo(pos);
        nvg::LineTo(tip);
        nvgIndicatorStrokeFill(col);
        nvg::ClosePath();
        nvg::BeginPath();
        nvg::MoveTo(tip);
        nvg::LineTo(pos);
        nvg::LineTo(bl);
        nvg::LineTo(tip);
    }

    void nvgQuadArrow(vec2 pos, float size, vec2 &in dir, vec4 col) {
        auto dirNormd = dir.Normalized();
        // shift pos back a bit to center the arrow better
        // pos -= dirNormd * .25;
        auto dirLeft = (rotateLeft90 * dirNormd).xy;
        auto tip = pos + dirNormd * size;
        auto tail = pos - (dirNormd * size / 2);
        auto bl = pos + (dirLeft) * size / 2.;
        auto br = pos - (dirLeft) * size / 2.;

        nvg::MoveTo(tip);
        nvg::LineTo(bl);
        nvg::LineTo(tail);
        nvg::LineTo(br);
        nvg::LineTo(tip);
    }

    void nvgTriArrow(vec2 pos, float size, vec2 &in dir, vec4 col) {
        auto dirNormd = dir.Normalized();
        // shift pos back a bit to center the arrow better
        // pos -= dirNormd * .25;
        auto dirLeft = (rotateLeft90 * dirNormd).xy;
        auto tip = pos + dirNormd * size;
        auto bl = pos + (dirLeft - dirNormd) * size / 1.7;
        auto br = pos - (dirLeft + dirNormd) * size / 1.7;
        // simple triangle
        nvg::MoveTo(tip);
        nvg::LineTo(br);
        nvg::LineTo(bl);
        nvg::LineTo(tip);
    }
}
