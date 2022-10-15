vec3[]@ GetCheckpointPositions() {
    auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    while (cp is null) {
        yield();
        @cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    }
    MwFastBuffer<CGameScriptMapLandmark@> landmarks = cp.Arena.MapLandmarks;
    auto positions = array<vec3>();
    for (uint i = 0; i < landmarks.Length; i++) {
        auto landmark = cast<CSmScriptMapLandmark>(landmarks[i]);
        if (landmark is null) continue;
        positions.InsertLast(landmark.Position);
    }
    return positions;
}
