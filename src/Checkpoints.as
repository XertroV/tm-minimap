vec3[]@ GetCheckpointPositions() {
    auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    while (cp is null) {
        yield();
        @cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    }
    MwFastBuffer<CGameScriptMapLandmark@> landmarks = cp.Arena.MapLandmarks;
    auto positions = array<vec3>();
    auto lcps = dictionary();
    for (uint i = 0; i < landmarks.Length; i++) {
        auto landmark = cast<CSmScriptMapLandmark>(landmarks[i]);
        if (landmark is null) continue;
        positions.InsertLast(landmark.Position);
    }
    return positions;
}

vec3[][]@ GetLinkedCheckpointPositions() {
    auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    while (cp is null) {
        yield();
        @cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    }
    MwFastBuffer<CGameScriptMapLandmark@> landmarks = cp.Arena.MapLandmarks;
    auto lcps = dictionary();
    for (uint i = 0; i < landmarks.Length; i++) {
        auto landmark = cast<CSmScriptMapLandmark>(landmarks[i]);
        if (landmark is null) continue;
        if (landmark.Tag == "LinkedCheckpoint") {
            array<vec3> linkedPos;
            if (!lcps.Get('' + landmark.Order, linkedPos)) {
                linkedPos = array<vec3>();
            }
            linkedPos.InsertLast(landmark.Position);
            lcps['' + landmark.Order] = linkedPos;
        }
    }
    auto linkedPositions = array<array<vec3>>();
    auto lpKeys = lcps.GetKeys();
    for (uint i = 0; i < lpKeys.Length; i++) {
        linkedPositions.InsertLast(cast<vec3[]>(lcps[lpKeys[i]]));
    }
    return linkedPositions;
}
