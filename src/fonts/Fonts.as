enum FontChoice {
    Montserrat_SemiBoldItalic,
    DroidSans,
    DroidSans_Bold,
    DroidSans_Mono
}

int g_nvgFontDroidSans = nvg::LoadFont("DroidSans.ttf", true, true);
int g_nvgFontDroidSansBold = nvg::LoadFont("DroidSans-Bold.ttf", true, true);
int g_nvgFontDroidSansMono = nvg::LoadFont("DroidSansMono.ttf", true, true);
int g_nvgFontMontserrat = nvg::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", true, true);

void nvg_SetFontFaceChoice() {
    auto fontChoice =
        S_NameTagFont == FontChoice::Montserrat_SemiBoldItalic ? g_nvgFontMontserrat
        : S_NameTagFont == FontChoice::DroidSans_Bold ? g_nvgFontDroidSansBold
        : S_NameTagFont == FontChoice::DroidSans_Mono ? g_nvgFontDroidSansMono
        : g_nvgFontDroidSans;
    nvg::FontFace(fontChoice);
}
