void Main() {
    startnew(MainLoop);
    startnew(Map::UpdateMapInfoLoop);
    startnew(InitSettings);
}

void MainLoop() {
    while(true) {
        yield();
        // in map or not in map
        if (GetApp().CurrentPlayground !is null) {
            MiniMap::MiniMapStart();
            // if map loop ends early, then keep going while current playground !is null
            while (GetApp().CurrentPlayground !is null) yield();
        }
    }
}

void Update(float dt) {
    MiniMap::UpdateMiniMap(dt);
}

void Render() {
    if (GetApp().RootMap !is null)
        MiniMap::Render();
}

UI::InputBlocking OnKeyPress(bool down, VirtualKey key) {
    if (key == S_ShortcutKey && down) {
        S_MiniMapState = (S_MiniMapState + 1) % 3; // off, small, big
        MiniMap::bigMiniMap = S_MiniMapState == 2;
    }
    return UI::InputBlocking::DoNothing;
}

void OnSettingsChanged() {
    UpdateDefaultSettings();
    if (GetApp().CurrentPlayground !is null && MiniMap::minimapPlayerObservations.Length != S_MiniMapGridParts)
        startnew(MiniMap::MiniMapStart);
}

void UpdateDefaultSettings() {
    if (S_MiniMapSize == 0)
        S_MiniMapSize = InitMiniMapSize();
    if (S_MiniMapPosition.LengthSquared() == 0.) {
        Recalc_S_MiniMapPosition();
    }
    if (S_BigMiniMapSize == 0) {
        S_BigMiniMapSize = uint(Math::Min(Draw::GetHeight(), Draw::GetWidth()) / 1.5);
    }
}

void InitSettings() {
    yield();
    yield();
    yield();
    yield();
    yield();
    UpdateDefaultSettings();
    startnew(MiniMap::MiniMapStart);
    MiniMap::bigMiniMap = S_MiniMapState == 2;
}
