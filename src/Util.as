vec2 F2Vec(float f) {
    return vec2(f, f);
}

vec3 F3Vec(float f) {
    return vec3(f, f, f);
}

vec4 F4Vec(float f) {
    return vec4(f, f, f, f);
}

vec2 GetScreenWH() {
    return vec2(Draw::GetWidth(), Draw::GetHeight());
}

void AddSimpleTooltip(const string &in msg) {
    if (UI::IsItemHovered()) {
        UI::BeginTooltip();
        UI::Text(msg);
        UI::EndTooltip();
    }
}
