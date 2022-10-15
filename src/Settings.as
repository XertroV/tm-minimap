[Setting category="MiniMap" name="Map Size (px)" description="Size of the minimap" min="100" max="1000"]
uint S_MiniMapSize = Draw::GetHeight() / 3;

[Setting category="MiniMap" name="Grid Partitions" description="How many partitions to break the minimap grid up into along X/Y axes. Worst case O(n^2) complexity: higher values => much higher performance cost. Example render times: 160: ~10ms, 80: 4.1ms, 40: 1.6ms, 20: <1.0ms" min="20" max="200"]
uint S_MiniMapGridParts = 50;

[Setting category="MiniMap" name="Screen Location (%)" description="Where on the screen to draw the minimap (%). Drag the values to change." drag min="0" max="100"]
vec2 S_MiniMapPosition = (GetScreenWH() - F2Vec(float(S_MiniMapSize) + 50)) / GetScreenWH() * 100;

void Recalc_S_MiniMapPosition(float padding = 50) {
    S_MiniMapPosition = (GetScreenWH() - F2Vec(float(S_MiniMapSize) + 50)) / GetScreenWH() * 100;
}

[Setting category="MiniMap" name="Shortcut Key" description="Tap the shortcut key to toggle the map. 3 states: off, small, large"]
VirtualKey S_ShortcutKey = VirtualKey::M;

[Setting hidden]
int S_MiniMapState = 1; // 0=off, 1=small, 2=big

[Setting category="MiniMap" name="Update When Hidden?" description="Keep track of players locations when the minimap is hidden? (Low performance impact; ~0.2ms / frame with 30 players.)"]
bool S_UpdateWhenHidden = true;

[Setting category="Colors" name="CP Color" color]
vec4 S_CP_Color = vec4(0.055f, 0.780f, 0.118f, 1.000f);

[Setting category="Colors" name="Player Color" color]
vec4 S_Player_Color = vec4(0.875f, 0.058f, 0.711f, 0.843f);

[Setting category="Colors" name="Camera Color" color]
vec4 S_Camera_Color = vec4(1, 1, 0, 1);
