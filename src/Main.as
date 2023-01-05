void Main() {
    startnew(MainLoop);
    startnew(Map::UpdateMapInfoLoop);
    startnew(InitSettings);
    startnew(ScreenShot::Main);
    startnew(RefreshMapsWithScreenshots);
}

void MainLoop() {
    while(true) {
        yield();
        // in map or not in map
        if (S_MiniMapEnabled && (GetApp().CurrentPlayground !is null && IsEditorConditionCheckOkay)) {
            MiniMap::MiniMapStart();
            // if map loop ends early, then don't reset while current playground !is null
            while (GetApp().CurrentPlayground !is null) yield();
        } else {
            // trace('S_MiniMapEnabled: ' + tostring(S_MiniMapEnabled));
            // trace('cp !is null: ' + tostring(GetApp().CurrentPlayground !is null));
            // trace('editor check: ' + tostring(IsEditorConditionCheckOkay));
            // trace('editor !is null: ' + tostring(GetApp().Editor !is null));
            // trace('curr stage: ' + int(ScreenShot::currStage) + ', ' + tostring(ScreenShot::currStage));
            // sleep(1000);
        }
    }
}

// replaces condition: Editor is null
bool get_IsEditorConditionCheckOkay() {
    return S_AllowInEditor || GetApp().Editor is null || int(ScreenShot::currStage) > 0;
}

void Update(float dt) {
    if (S_MiniMapEnabled)
        MiniMap::UpdateMiniMap(dt);
}

/** Render function called every frame intended only for menu items in `UI`.
*/
void RenderMenu() {
    if (UI::MenuItem("\\$e66" + Icons::Map + "\\$z " + Meta::ExecutingPlugin().Name, "", S_MiniMapEnabled)) {
        S_MiniMapEnabled = !S_MiniMapEnabled;
    }
}

void Render() {
    // render screenshot wizard
    ScreenShot::Render();
    // if we check GetApp().RootMap here then the minimap can show up in the editor, etc
    if (S_MiniMapEnabled && GetApp().CurrentPlayground !is null && IsEditorConditionCheckOkay)
        MiniMap::Render();
}

UI::InputBlocking OnKeyPress(bool down, VirtualKey key) {
    if (S_MiniMapEnabled && key == S_ShortcutKey && down && IsEditorConditionCheckOkay && GetApp().CurrentPlayground !is null) {
        S_MiniMapState = (S_MiniMapState + 1) % 3; // off, small, big
        if (S_DisableSmallMinimap && S_MiniMapState == 1) S_MiniMapState = 2;
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
    MiniMap::bigMiniMap = S_MiniMapState == 2;
}
