[Setting category="MiniMap" name="Enable Minimap" description="When unchecked, the minimap can only be enabled via the 'Scripts' menu."]
bool S_MiniMapEnabled = true;

[Setting category="MiniMap" name="Map Size (px)" description="Size of the minimap" min="100" max="1000"]
uint S_MiniMapSize = 0;

uint InitMiniMapSize() { return  Draw::GetHeight() / 3; }

[Setting category="MiniMap" name="Big Map Size (px)" description="Size of the minimap when it is in 'big' mode" min="100" max="3000"]
uint S_BigMiniMapSize = 0;

[Setting category="MiniMap" name="Grid Partitions" description="How many partitions to break the minimap grid up into along X/Y axes. Worst case O(n^2) complexity: higher values => much higher performance cost. Example render times: 160: ~10ms, 80: 4.1ms, 40: 1.6ms, 20: <1.0ms" min="20" max="200"]
uint S_MiniMapGridParts = 50;

[Setting category="MiniMap" name="Fade Grid Squares" description="Grid squares are highlighted based on how long players have spent in them, and will fade over time. This prevents weird paths sticking around if someone goes way off track. A bias is applied based on the number of grid partitions."]
bool S_FadeGridSquares = true;

[Setting category="MiniMap" name="Grid Square Persistence" description="A modifier for how slowly grid squares fade. Higher numbers => longer fade." min="1" max="100"]
float S_GridSquarePersistence = 20.0;

[Setting category="MiniMap" name="Draw Grid Lines" description="Horizontal and vertical lines outlining each grid square."]
bool S_DrawGridLines = true;

[Setting category="MiniMap" name="Screen Location (%)" description="Where on the screen to draw the minimap (%). Drag the values to change." drag min="0" max="100"]
vec2 S_MiniMapPosition = vec2(0, 0);

void Recalc_S_MiniMapPosition(float padding = 50) {
    S_MiniMapPosition = (GetScreenWH() - F2Vec(float(S_MiniMapSize) + padding)) / GetScreenWH() * 100;
}

[Setting category="MiniMap" name="Shortcut Key" description="Tap the shortcut key to toggle the map. 3 states: off, small, large"]
VirtualKey S_ShortcutKey = VirtualKey::M;

[Setting hidden]
int S_MiniMapState = 1; // 0=off, 1=small, 2=big

[Setting category="MiniMap" name="Update When Hidden?" description="Keep track of players locations when the minimap is hidden? (Low performance impact; ~0.2ms / frame with 30 players.)"]
bool S_UpdateWhenHidden = true;

[Setting category="Appearance" name="CP Color" color]
vec4 S_CP_Color = vec4(0.055f, 0.780f, 0.118f, 1.000f);

[Setting category="Appearance" name="Player Color" color]
vec4 S_Player_Color = vec4(0.875f, 0.058f, 0.711f, 0.843f);

[Setting category="Appearance" name="Camera Color" color]
vec4 S_Camera_Color = vec4(0.931f, 0.464f, 0.061f, 1.000f);

[Setting category="Appearance" name="Linked CP Indicator Color" color]
vec4 S_Linked_Color = vec4(0.056f, 0.528f, 0.811f, .4f);

[Setting category="Appearance" name="CP Size" min="1" max="40" description="Scaled to pixels at 1080p"]
float S_CP_Size = 10.0;

[Setting category="Appearance" name="Player Size" min="1" max="40" description="Scaled to pixels at 1080p"]
float S_Player_Size = 10.0;

[Setting category="Appearance" name="Camera Size" min="1" max="40" description="Scaled to pixels at 1080p"]
float S_Camera_Size = 10.0;

enum MiniMapShapes {
    Circle,
    Square,
    Arrow,
    TriArrow,
    QuadArrow,
    Ring
}

[Setting category="Appearance" name="CP Shape"]
MiniMapShapes S_CP_Shape = MiniMapShapes::Ring;

[Setting category="Appearance" name="Player Shape"]
MiniMapShapes S_Player_Shape = MiniMapShapes::QuadArrow;

[Setting category="Appearance" name="Camera Shape"]
MiniMapShapes S_Camera_Shape = MiniMapShapes::QuadArrow;

/* advanced */

[Setting category="Advanced" name="Allow Minimap in Editor?" description="The minimap will be disabled in the editor unless this is checked."]
bool S_AllowInEditor = false;

[Setting category="Bg Image Settings" name="BG Alpha" min="0.0" max="1.0"]
float S_BgImageAlpha = 0.5;



[SettingsTab name="Bg Image Wizard" icon="PictureO"]
void Render_S_BackgroundImages() {
    if (!Permissions::OpenAdvancedMapEditor()) {
        UI::Text("Sorry, this feature is only available with club access.");
        return;
    }
    UI::AlignTextToFramePadding();
    UI::TextWrapped("Use the wizard to take new screenshots:");
    UI::BeginDisabled(ScreenShot::currStage != ScreenShot::WizStage::Uninitialized);
    if (UI::Button("Start Wizard")) {
        ScreenShot::InitWizard();
    }
    UI::EndDisabled();
    UI::Separator();
    UI::AlignTextToFramePadding();
    UI::Text("Maps with screenshots (" + mapsWithScreenshots.Length + ")  ");
    UI::SameLine();
    if (UI::Button("Refresh##maps-with-screenshots")) {
        startnew(RefreshMapsWithScreenshots);
    }
    // todo: list maps
    if (UI::BeginTable("mws list", 3, UI::TableFlags::SizingStretchProp)) {
        UI::TableSetupColumn("Name");
        UI::TableSetupColumn("Author");
        UI::TableSetupColumn("UID");
        UI::TableHeadersRow();
        for (uint i = 0; i < mapsWithScreenshots.Length; i++) {
            auto mws = mapsWithScreenshots[i];
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::Text(ColoredString(mws.mapName));
            UI::TableNextColumn();
            UI::Text(ColoredString(mws.mapAuthor));
            UI::TableNextColumn();
            UI::Text(ColoredString(mws.mapUid));

        }
        UI::EndTable();
    }
}
