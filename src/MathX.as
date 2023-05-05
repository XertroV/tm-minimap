namespace MathX {
    vec2 Clamp(vec2 &in val, float min, float max) {
        return vec2(
            Math::Clamp(val.x, min, max),
            Math::Clamp(val.y, min, max)
        );
    }
}
