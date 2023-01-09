namespace ScreenShot {
    vec3 cameraPos;
    vec3 cameraPitchYawRoll;
    float camPitch = -90;
    float cameraFov = 10.;

    string mapName;
    string mapUid;
    string mapAuthor;

    // resolution (px) of the screenshot
    int2 shotRes = int2(3840, 2160);

    UI::Texture@ screenshotImage = null;

    string CurrScreenShotFilePath {
        get {
            return IO::FromUserGameFolder("ScreenShots/" + mapUid + "01" + extName);
        }
    }

    string DestScreenShotFilePath {
        get {
            auto folderPath = IO::FromStorageFolder("bgs");
            if (!IO::FolderExists(folderPath)) {
                IO::CreateFolder(folderPath, true);
            }
            return IO::FromStorageFolder("bgs/" + mapUid + extName);
        }
    }

    string DestMapInfoJsonFilePath {
        get {
            return IO::FromStorageFolder("bgs/" + mapUid + ".json");
        }
    }

    enum WizStage {
        Uninitialized,
        // instruction: open map in map editor
        Start,
        // go into validation mode to get checkpoint positions, map uid
        WaitOkValidateForCPs,
        // automate validation mode + exit validation mode
        GettingMapDetails,
        // prompt: open media tracker intro
        GotMapDetails,
        // show MT instructions, incl camera, and buttons to modify projection variables
        InMediaTracker,
        // open screen shooter, show instructions
        ShowScreenShotInstructions,
        // while screen shot preview showing
        TakingScreenShot,
        // show the screenshot and confirm it's good
        ConfirmScreenShot,
        // done
        Complete
    }

    enum FovChoice {
        Close,
        Middle,
        Far
    }

    WizStage currStage = WizStage::Uninitialized;

    void InitWizard() {
        if (currStage != WizStage::Uninitialized) return;
        currStage = WizStage::Start;
        cameraPitchYawRoll = vec3();
        cameraPos = vec3();
        mapUid = "";
        mapName = "";
        @screenshotImage = null;
        zClipLimit = 50000;
        nearZClip = 0.05;
    }

    void Main() {
        startnew(AutoUpdateCameraLoop);
        startnew(ExitIfEditorGone);
    }

    void ExitIfEditorGone() {
        while (true) {
            yield();
            if (currStage <= WizStage::Start) continue;
            if (GetApp().Editor is null) {
                currStage = WizStage::Uninitialized;
            }
        }
    }

    uint lastAutoUpdateCam = 0;
    bool requestAutoUpdate = false;

    void AutoUpdateCameraLoop() {
        while (true) {
            yield();
            if (currStage != WizStage::InMediaTracker) continue;
            if (!m_autoUpdateCamera) continue;
            if (cast<CGameEditorMediaTracker>(GetApp().Editor) is null) continue;
            if (lastAutoUpdateCam + 100 > Time::Now) continue;
            if (!requestAutoUpdate) continue;
            lastAutoUpdateCam = Time::Now;
            requestAutoUpdate = false;
            // print("Auto updating.");
            try {
                OnClickAutopopulateCamera();
            } catch {
                warn("Exception auto updating: " + getExceptionInfo());
            }
        }
    }

    mat4 rotation, perspective, translation, projection;
    [Setting hidden]
    float CameraHeight = 30000.;
    [Setting hidden]
    vec2 m_padding = vec2(5, 5);
    [Setting hidden]
    vec3 m_offset = vec3(0, 0, 0);
    float zClipLimit = 50000;
    float nearZClip = 0.05;

    float AspectRatio {
        get {
            if (shotRes.y == 0) return 16. / 9.;
            return float(shotRes.x) / float(shotRes.y);
        }
    }

    vec3 minimapMidPoint;

    void UpdateMatricies() {
        auto custRotation = mat4::Rotate(Math::ToRad(m_Rotation), vec3(0, 1, 0));
        // rotate around z axis to point down, then apply custom rotation
        rotation = custRotation * mat4::Rotate(Math::ToRad(-camPitch), vec3(1, 0, 0));
        auto rotDifference = mat4::Rotate(-Math::ToRad(camPitch + 90), vec3(1, 0, 0));
        minimapMidPoint = (mapMax + mapMin) / 2.;
        // if camPitch is not -90, we want to update our position so it's looking at the map midpoint
        vec3 camBase = (custRotation * rotDifference * vec3(0, CameraHeight, 0)).xyz;
        cameraPos = camBase + minimapMidPoint - m_offset;
        translation = mat4::Translate(cameraPos);
        UpdateShotResY();
        cameraPitchYawRoll = vec3(-camPitch, m_Rotation, 0);
        SearchForFoVAndSetProjection();
    }

    void UpdateShotResY() {
        shotRes.y = shotRes.x / AspectToRatio(S_Wiz_Aspect);
    }

    vec2 ProjectPoint(vec3 pos) {
        vec4 ret = projection * pos;
        if (ret.w == 0)
            return vec2();
        return ret.xyz.xy / ret.w;
    }

    void SearchForFoVAndSetProjection() {
        auto mapSize = mapMax - mapMin;
        vec3 pad = vec3(mapSize.x * m_padding.x, 0, mapSize.z * m_padding.y) / 100.;
        auto minTest = mapMin - pad - m_offset;
        auto maxTest = mapMax + pad - m_offset;
        maxTest.y = minTest.y;
        float fovUpper = 180.;
        float fovLower = 0.1;
        cameraFov = Math::Clamp(cameraFov, fovLower, fovUpper);
        CalcProjectionMatricies(cameraFov);
        uint count = 0;
        while (FovError(minTest, maxTest) > 0.001) {
            count++;
            if (IsFovTooHigh()) {
                fovUpper = cameraFov;
            } else {
                fovLower = cameraFov;
            }
            cameraFov = (fovUpper + fovLower) / 2.;
            // print("new fov: " + cameraFov);
            CalcProjectionMatricies(cameraFov);
            if (count > 40) {
                warn("SearchForFoVAndSetProjection looped too much; breaking");
                break;
            }
        }
    }

    void CalcProjectionMatricies(float fov) {
        perspective = mat4::Perspective(fov, AspectRatio, 1, 100000);
        projection = perspective * mat4::Inverse(translation * rotation);
    }

    vec2 fovMinTestRes;
    vec2 fovMaxTestRes;
    float fovMaxUV;

    float FovError(vec3 minTest, vec3 maxTest) {
        fovMinTestRes = ProjectPoint(minTest);
        fovMaxTestRes = ProjectPoint(maxTest);
        fovMaxUV = 0;
        for (uint i = 0; i < 8; i++) {
            auto p = vec3(i & 1 == 0 ? minTest.x : maxTest.x, i & 2 == 0 ? minTest.y : maxTest.y, i & 4 == 0 ? minTest.z : maxTest.z);
            auto res = ProjectPoint(p);
            fovMaxUV = Math::Max(fovMaxUV, Math::Max(Math::Abs(res.x), Math::Abs(res.y)));
        }
        return Math::Abs(fovMaxUV - 1.);
    }

    bool IsFovTooHigh() {
        return fovMaxUV < 1;
    }



    void Render() {
        RenderWizardInner();
    }

    void SetZClipFar() {
        auto vp = GetApp().Viewport;
        bool setZClip = currStage >= WizStage::InMediaTracker;
        if (!setZClip) return;
        auto doneWithScreenshot = currStage >= WizStage::ConfirmScreenShot;
        float farZ = doneWithScreenshot ? 50000 : zClipLimit;
        for (uint i = 0; i < vp.Cameras.Length; i++) {
            auto cam = vp.Cameras[i];
            cam.FarZ = farZ;
        }
    }

    bool RenderWizardInner() {
        switch (currStage) {
            case WizStage::Uninitialized: return false;
            case WizStage::Start: return RenderWizMain(RenderStart);
            case WizStage::WaitOkValidateForCPs: return RenderWizMain(RenderWaitOkValidateForCPs);
            case WizStage::GettingMapDetails: return RenderWizMain(RenderGettingMapDetails);
            case WizStage::GotMapDetails: return RenderWizMain(RenderGotMapDetails);
            case WizStage::InMediaTracker: return RenderWizMain(RenderInMediaTracker);
            case WizStage::ShowScreenShotInstructions: return RenderWizMain(RenderShowScreenShotInstructions);
            case WizStage::TakingScreenShot: return RenderWizMain(RenderTakingScreenShot);
            // case WizStage::ScreenShotPrompt: return RenderWizMain(RenderScreenShotPrompt);
            case WizStage::ConfirmScreenShot: return RenderWizMain(RenderConfirmScreenShot);
            case WizStage::Complete: return RenderWizMain(RenderComplete);
        }
        return false;
    }

    bool WizardWindowOpen {
        get {
            return currStage != WizStage::Uninitialized;
        }
        set {
            if (!value) {
                currStage = WizStage::Uninitialized;
            } else if (currStage == WizStage::Uninitialized) {
                startnew(InitWizard);
            }
        }
    }

    bool BeginWizWindow() {
        auto flags = UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoCollapse;
        auto ret = UI::Begin("MiniMap Screenshot Wizard", WizardWindowOpen, flags);
        if (ret) {
            UI::Text("Step " + tostring(int(currStage)) + " (" + tostring(currStage) + ")");
            UI::Separator();
        }
        return ret;
    }

    bool RenderWizMain(CoroutineFunc@ f) {
        if (BeginWizWindow()) {
            f();
        }
        UI::End();
        return true;
    }

    vec2 selectMapBtnPos = vec2(0, 200);
    void RenderStart() {
        UI::Text("Open your desired map in the advanced editor.");
        UI::Separator();
        auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
        if (editor is null) {
            UI::Text("Open a map in the editor.");
            UI::Dummy(vec2(0, UI::GetTextLineHeightWithSpacing() * 3.));
        } else {
            RenderCurrMapDetails(true);
        }
        UI::Separator();
        UI::BeginDisabled(GetApp().RootMap is null || editor is null);
        selectMapBtnPos = UI::GetCursorPos();
        if (UI::Button("Yep, that's the right map.")) {
            startnew(OnLoadedMapInEditor);
        }
        UI::EndDisabled();
        UI::Separator();
        UI::TextWrapped("\\$888If you want a quick way to load maps from URLs/TMX ids in the editor, check out the `Play Map` plugin. (Well, to load from TMX id in the editor, first load it normally, then quit, then copy the URL from the log into the editor tab.)");
    }

    void RenderWaitOkValidateForCPs() {
        UI::Text("I need to get the coordinates for all of the CPs.");
        UI::TextWrapped("I'm going to automate going into validation mode and will get the CP data, when you're ready.");
        // UI::TextWrapped("\\$<\\$fd1Note: If there is a mediatracker intro, I'm unable to automatically skip it. Please skip it for me.\\$>");
        // UI::Dummy(vec2(0, UI::GetTextLineHeightWithSpacing() * 2.5));
        UI::SetCursorPos(selectMapBtnPos);
        if (UI::Button("I'm Ready, Automate Away.##get-cps")) {
            startnew(OnBeginValidationAuto);
        }
    }

    void RenderGettingMapDetails() {
        UI::Text("Waiting for map load and acquisition of details.");
    }

    void RenderGotMapDetails() {
        UI::Text("Relevant map info acquired.");
        DrawMapBounds();
        UI::Separator();
        UI::TextWrapped("Please prepare the map for the screenshot.");
        UI::TextWrapped("\\$fd1" + Icons::ExclamationCircle + "  You might need to clear away some scenery to make sure the camera can see the map from above. Now is the time to do that. (You can come back later, though).");
        UI::Separator();
        UI::TextWrapped("Click next when you're ready to set up the camera. (You can come back later without losing settings.)");
        if (UI::Button("Take Me To MediaTracker")) {
            startnew(OnClickEnterMediaTracker);
        }
    }

    [Setting hidden]
    bool m_autoUpdateCamera = true;

    void RenderInMediaTracker() {
        ShowShotPreviewOutline();
        ShowTestPointsCube();
        auto mtEditor = cast<CGameEditorMediaTracker>(GetApp().Editor);
        if (mtEditor is null) {
            AdvanceStep(-1);
            return;
        }
        UI::Text("Camera and Environtment Setup");
        UI::Separator();
        // not wrapped to set min effective width
        UI::Text("Okay, now we need to set up the camera and stuff like the fog, color fx, etc.");
        UI::TextWrapped("Hopefully, you removed any scenary above the track earlier (otherwise, go do this now).");
        UI::Text("Next, we need to set up a \\$<\\$1efcustom camera\\$> track that will be the basis for our screenshot.");
        UI::TextWrapped("\\$fd1" + Icons::ExclamationCircle + "\\$z  You may want to remove all existing media tracks at this time.");
        UI::TextWrapped("After the camera is set up, it's up to you to set things like the fog, colors fx / grading, etc to make the map look the way that you want.");
        UI::TextWrapped("\\$69f" + Icons::InfoCircle +  "\\$z  Suggestion: in fog set all settings to 0 or the minimum to disable the default fog and clouds.");
        UI::TextWrapped("\\$fd1" + Icons::ExclamationCircle + "\\$z  You *need* a custom camera exactly called 'Custom camera' with the Target and Anchor set to 'None'. After that, set your parameters and use the autopopulate button.");
        UI::TextWrapped("\\$fd1" + Icons::ExclamationCircle + "\\$z  Always use keyframes at 00:00.000 -- the start of the timeline.");
        UI::Separator();
        if (UI::Button("Automatically set up Tracks")) {
            startnew(OnClickAutomaticTrackSetup);
        }
        UI::Text("\\$69f" + Icons::InfoCircle +  "\\$z  Note: you might want to play with (or remove) the color FX track.");
        UI::Separator();
        UI::AlignTextToFramePadding();
        UI::TextWrapped("Screenshot Parameters:");
        DrawResetSSParams();
        DrawAspectRatioChooser();
        DrawCameraFovChooser();
        UI::Separator();
        UI::AlignTextToFramePadding();
        if (UI::CollapsingHeader("Camera Details")) {
            UI::TextWrapped("Track Type: Custom Camera");
            UI::TextWrapped("Target: None");
            UI::TextWrapped("Anchor: None");
            UI::TextWrapped("Interpolation: None");
            UI::TextWrapped("Position: " + cameraPos.ToString());
            UI::TextWrapped("Rotation: " + cameraPitchYawRoll.ToString());
            UI::TextWrapped("Field of view: " + cameraFov);
            UI::TextWrapped("Near clip plane: 0.05");
            UI::Separator();
            DrawMapBounds();
            UI::Text("Debug TL: " + ProjectPoint(mapMin).ToString());
            UI::Text("Debug BR: " + ProjectPoint(mapMaxGround).ToString());
            UI::Text("Debug SS Res: " + shotRes.ToString());
        }
        UI::Separator();
        if (UI::Button("Auto-populate custom camera track values")) {
            startnew(OnClickAutopopulateCamera);
        }
        UI::SameLine();
        m_autoUpdateCamera = UI::Checkbox("Auto-update?", m_autoUpdateCamera);
        UI::Separator();
        UI::Text("When you're done, we'll take the screen shot.");
        if (UI::Button("I'm done, ready to take the shot!")) {
            startnew(OnClickStartScreenshot);
        }
    }

    void RenderShowScreenShotInstructions() {
        UI::TextWrapped("You should now see the screenshot render prompt.");
        UI::TextWrapped("This should be automatically filled out, but if not...");
        UI::AlignTextToFramePadding();
        UI::Text("Shoot Name: " + mapUid);
        UI::SameLine();
        if (UI::Button("Copy##shoot-name")) {
            IO::SetClipboard(mapUid);
        }
        UI::TextWrapped("Select 'High' quality options, and enter:");
        UI::Text("Width: " + shotRes.x);
        UI::Text("Height: " + shotRes.y);
        UI::Text("Format: JPG");

        UI::Separator();
        if (UI::Button("Go Back, take another")) {
            AdvanceStep(-1);
        }
        UI::SameLine();
        if (UI::Button("Ready, take screenshot")) {
            AdvanceStep(1);
        }
    }

    void RenderTakingScreenShot() {
        UI::TextWrapped("You should now see the screenshot (after rendering). Press a key to save or ESC to go back.");
        UI::Separator();
        UI::TextWrapped("\\$fd1" + Icons::ExclamationCircle + "\\$z  You *must* take or cancel the screenshot before pressing one of these buttons! (Undefined behavior otherwise.)");
        UI::Separator();
        if (UI::Button("No good, need another one (Back)")) {
            AdvanceStep(-2);
        }
        UI::SameLine();
        if (UI::Button("I saved it")) {
            startnew(OnScreenShotSaved);
        }
    }

    // unused
    void RenderScreenShotPrompt() {}

    void RenderConfirmScreenShot() {
        UI::Text("You like?");
        if (UI::Button("No (Back)")) OnDontLikeScreenshot();
        UI::SameLine();
        if (UI::Button("Yes (Save)")) OnLikeScreenshot();
        UI::Separator();
        if (screenshotImage is null) {
            UI::Text("Loading image...");
        } else {
            UI::Image(screenshotImage, vec2(shotRes.x, shotRes.y) / float(shotRes.y) * (Draw::GetHeight() / 2.));
        }
    }

    void RenderComplete() {
        UI::Text("Done!");
        UI::Dummy(vec2(250, 20));
        if (UI::Button("Back to start -- do another map.")) {
            currStage = WizStage::Uninitialized;
            InitWizard();
            cast<CGameManiaPlanet>(GetApp()).BackToMainMenu();
        }
        UI::Dummy(vec2(250, 20));
        if (UI::Button("Close")) {
            currStage = WizStage::Uninitialized;
            cast<CGameManiaPlanet>(GetApp()).BackToMainMenu();
        }
    }







    void RenderCurrMapDetails(bool addPadding = false) {
        auto map = GetApp().RootMap;
        if (map is null) {
            UI::Text("No map loaded.");
            return;
        }
        UI::Text("Name: " + ColoredString(map.MapName));
        UI::Text("Uid: " + map.EdChallengeId);
        UI::Text("Author: " + map.AuthorNickName);
        UI::Text("AT: " + Time::Format(map.TMObjective_AuthorTime));
    }

    void DrawMapBounds() {
        UI::Text("\\$888Bounds: " + mapMin.ToString() + " to " + mapMax.ToString());
    }

    [Setting hidden]
    int m_horizResolution = 0;

    enum Aspect {
        Square,
        r4By3,
        r16by10,
        r16by9,
        Ultrawide,
        Last
    }

    float AspectToRatio(Aspect a) {
        return a == Aspect::Square ? 1.
        : a == Aspect::r4By3 ? 4. / 3.
        : a == Aspect::r16by10 ? 16. / 10.
        : a == Aspect::r16by9 ? 16. / 9.
        : a == Aspect::Ultrawide ? 21. / 9.
        : 1.;
    }

    [Setting hidden]
    Aspect S_Wiz_Aspect = Aspect::r16by9;

    [Setting hidden]
    float m_Rotation = 0;

    void DrawResetSSParams() {
        if (UI::Button("Reset Offset, Rotation, Pitch, Padding")) {
            m_offset = vec3();
            m_Rotation = 0;
            camPitch = -90;
            m_padding = vec2(5, 5);
            UpdateMatricies();
            requestAutoUpdate = m_autoUpdateCamera;
        }
    }

    void DrawAspectRatioChooser() {
        auto origHR = shotRes.x;
        auto origRot = m_Rotation;
        auto origAspect = S_Wiz_Aspect;
        auto origOffset = m_offset;
        auto origPitch = camPitch;

        if (shotRes.x == 0) {
            shotRes.x = Draw::GetWidth();
        }
        shotRes.x = UI::SliderInt("Horiz. Pixles", shotRes.x, 1280, 8192);
        UI::SameLine(); if (UI::Button("1920")) shotRes.x = 1920;
        UI::SameLine(); if (UI::Button("2560")) shotRes.x = 2560;
        UI::SameLine(); if (UI::Button("3440")) shotRes.x = 3440;
        UI::SameLine(); if (UI::Button("3840")) shotRes.x = 3840;
        UI::SameLine(); if (UI::Button("5120")) shotRes.x = 5120;
        UI::SameLine(); if (UI::Button("7680")) shotRes.x = 7680;
        if (shotRes.x > 5120) TextWExclaimation("High resolution shots can crash TM and you may notice effects of LoD (overly simple level geometry). Tweaker can help with LoD, but may increase the risk of a crash.");

        if (UI::BeginCombo("Aspect", tostring(S_Wiz_Aspect))) {
            for (int i = 0; i < int(Aspect::Last); i++) {
                auto a = Aspect(i);
                if (UI::Selectable(tostring(a), S_Wiz_Aspect == a)) {
                    S_Wiz_Aspect = a;
                }
            }
            UI::EndCombo();
        }

        auto mapMaxDims = Math::Max(mapMax.x - mapMin.x, mapMax.z - mapMin.x) * 3.1;
        m_offset.x = Math::Clamp(UI::InputFloat("Offset x", m_offset.x, 8.), -mapMaxDims, mapMaxDims);
        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##reset-offset")) m_offset.x = 0;
        m_offset.y = UI::InputFloat("Offset y", m_offset.y, 24.);
        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##reset-offset2")) m_offset.y = 0;
        m_offset.z = Math::Clamp(UI::InputFloat("Offset z", m_offset.z, 8.), -mapMaxDims, mapMaxDims);
        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##reset-offset3")) m_offset.z = 0;
        // m_offset = UI::SliderFloat2("Offset (x,y)", m_offset, -mapMaxDims, mapMaxDims, "%.0f");
        // UI::SameLine();
        // if (UI::Button(Icons::Refresh + "##reset-offset2")) m_offset = vec2(0, 0);

        camPitch = Math::Clamp(UI::InputFloat("Camera Pitch", camPitch, 0.5), -90., 90.);
        UI::SameLine(); if (UI::Button(Icons::Refresh + "##reset-pitch")) camPitch = -90;

        m_Rotation = UI::InputFloat("Rotation (degrees)", m_Rotation, 0.5);
        m_Rotation = Math::Clamp(m_Rotation, -180., 540.);
        UI::SameLine(); if (UI::Button(Icons::Refresh + "##reset-rotation")) m_Rotation = 0.;

        if (origHR != shotRes.x || m_Rotation != origRot || origAspect != S_Wiz_Aspect || !Vec3Eq(origOffset, m_offset) || camPitch != origPitch) {
            UpdateMatricies();
            requestAutoUpdate = m_autoUpdateCamera;
        }
    }

    // [Setting hidden]
    // int m_fovMod = 0;

    void DrawCameraFovChooser() {
        // auto origFov = m_fovMod;
        // UI::Text("Zoom in/out tweak: ");
        // m_fovMod = UI::InputInt("##m_fovMod", m_fovMod);
        // if (origFov != m_fovMod) {
        //     UpdateMatricies();
        // }
        auto origCH = CameraHeight;
        auto origPadding = m_padding;
        auto origFov = cameraFov;
        auto origFar = zClipLimit;
        auto origNear = nearZClip;
        // the default zclip distance is 50000; though it can be changed (camera property from memory).
        // set max to 50k tho to be safe
        CameraHeight = UI::SliderFloat("Cam Height", CameraHeight, 1000., 50000., "%.0f");
        zClipLimit = UI::InputFloat("Far Z-Clip", zClipLimit, 64.);
        AddSimpleTooltip("Will not be visible in the preview, but works for the screenshot.");
        UI::SameLine(); if (UI::Button(Icons::Refresh + "##reset zclip")) zClipLimit = 50000;
        UI::SameLine();
        if (UI::Button("Set to cam height##far")) {
            zClipLimit = CameraHeight;
        }
        nearZClip = UI::InputFloat("Near Z-Clip", nearZClip, 64.);
        UI::SameLine(); if (UI::Button(Icons::Refresh + "##reset near zclip")) nearZClip = 0.05;
        UI::SameLine();
        if (UI::Button("Set to cam height##near")) {
            nearZClip = CameraHeight;
        }
        m_padding = UI::SliderFloat2("Edge Padding (x,y %)", m_padding, -50., 100., "%.1f");
        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##reset-padding")) m_padding = vec2(5, 5);

        bool changed = zClipLimit != origFar || nearZClip != origNear;
        changed = changed || origCH != CameraHeight || !Vec2Eq(m_padding, origPadding) || cameraFov != origFov;
        // cameraFov = Math::Clamp(UI::InputFloat("Cam FoV", cameraFov, 0.1), 0.1, 90.);
        if (changed) {
            UpdateMatricies();
            requestAutoUpdate = m_autoUpdateCamera;
        }
    }

    void ShowShotPreviewOutline() {
        auto cam = Camera::GetCurrent();
        if (cam is null) return;
        vec2 screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        vec2 uvTL = vec2(-cam.DrawRectMin.x, -cam.DrawRectMax.y);
        vec2 uvBR = vec2(-cam.DrawRectMax.x, -cam.DrawRectMin.y);
        vec2 tlCam = (uvTL / 2. + vec2(.5, .5)) * screen;
        vec2 brCam = (uvBR / 2. + vec2(.5, .5)) * screen;

        vec2 pos, size;
        // note, size.x is negative but doesn't matter here
        size = brCam - tlCam;
        vec2 camCenter = tlCam + size / 2.;
        vec2 shotSize = vec2(size.y * AspectRatio, size.y);
        pos = camCenter - shotSize / 2.;
        vec2 posBr = camCenter + shotSize / 2.;
        size = shotSize;
        // draw a rectangle over the MT camera view to aid map positioning.
        nvg::Reset();
        nvg::BeginPath();
        nvg::Rect(pos, size);
        nvg::MoveTo(vec2(pos.x, camCenter.y));
        nvg::LineTo(vec2(posBr.x, camCenter.y));
        nvg::MoveTo(vec2(camCenter.x, pos.y));
        nvg::LineTo(vec2(camCenter.x, posBr.y));
        nvg::StrokeColor(vec4(.9, .2, 0, .9));
        nvg::StrokeWidth(Draw::GetHeight() / 200.);
        nvg::Stroke();
        nvg::ClosePath();
    }

    void ShowTestPointsCube() {
        vec3[] testPoints;
        for (uint i = 0; i < 8; i++) {
            testPoints.InsertLast(vec3(
                i & 1 == 0 ? mapMin.x : mapMax.x,
                i & 2 == 0 ? mapMin.y : mapMax.y,
                i & 4 == 0 ? mapMin.z : mapMax.z
            ));
            DrawTestPointMarker(testPoints[i]);
            // break;
        }
        DrawTestPointMarker(minimapMidPoint, vec4(.9, .1, 0, .9));
    }

    void DrawTestPointMarker(vec3 p, vec4 col = vec4(.9, .5, 0, .9)) {
        auto cam = Camera::GetCurrent();
        if (cam is null) return;
        auto uvz = Camera::ToScreen(p);
        vec2 screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        vec2 uvTL = vec2(-cam.DrawRectMax.x, -cam.DrawRectMax.y);
        vec2 uvBR = vec2(-cam.DrawRectMin.x, -cam.DrawRectMin.y);
        vec2 tlCam = (uvTL / 2. + vec2(.5, .5)) * screen;
        vec2 brCam = (uvBR / 2. + vec2(.5, .5)) * screen;

        vec2 totalPx = (brCam - tlCam);
        totalPx.x = Math::Abs(totalPx.x);
        mat3 toCamSmall = mat3::Translate(tlCam) * mat3::Scale(totalPx / screen);
        vec2 pos = (toCamSmall * uvz.xy).xy;
        // print(tlCam.ToString());
        // print(brCam.ToString());
        // print(pos.ToString());

        nvg::BeginPath();
        nvg::Circle(pos, 5.);
        nvg::StrokeColor(col);
        nvg::StrokeWidth(2.);
        nvg::Stroke();
        nvg::ClosePath();
    }


    // void DrawSetMidday() {
    //     if (UI::Button("Set time to midday")) {
    //         // auto api = cast<CGameEditorMediaTrackerPluginAPI>(cast<CGameEditorMediaTracker>(GetApp().Editor).PluginAPI);
    //         auto editor = cast<CGameCtnEditorFree>(GetApp().Switcher.ModuleStack[0]);
    //         editor.MoodTimeOfDay01 = 0.5;
    //     }
    // }



    void AdvanceStep(int advAmt = 1) {
        currStage = WizStage(int(currStage) + advAmt);
    }


    void OnLoadedMapInEditor() {
        auto map = GetApp().RootMap;
        mapName = map.MapName;
        mapUid = map.EdChallengeId;
        mapAuthor = map.AuthorNickName;
        AdvanceStep();
    }

    void OnBeginValidationAuto() {
        // load validation run, get cp info, quit out back to editor
        AdvanceStep();
        startnew(OnEnterValidationCoro);
    }

    // vec3[]@ cpPositions;
    vec3 mapMin, mapMax;

    vec3 mapMaxGround {
        get {
            return vec3(mapMax.x, mapMin.y, mapMax.z);
        }
    }

    void OnEnterValidationCoro() {
        // ensure nothing gets cached
        MiniMap::mmStateInitialized = false;
        auto app = cast<CGameManiaPlanet>(GetApp());
        auto editor = cast<CGameCtnEditorFree>(app.Editor);
        editor.ButtonValidateOnClick();
        while (app.CurrentPlayground is null) yield();
        auto cp = app.CurrentPlayground;
        while (cp.UIConfigs.Length == 0) yield();
        auto uiConf = cp.UIConfigs[0];
        // while (uiConf.UISequence != CGamePlaygroundUIConfig::EUISequence::Intro) yield();
        while (uiConf.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        while (!MiniMap::mmStateInitialized) yield();
        // @cpPositions = MiniMap::cpPositions;
        // extend bounds by a standard block size
        mapMin = MiniMap::rawMin;
        mapMax = MiniMap::rawMax + vec3(32, 8, 32);
        trace('cached cp positions and stuff');
        yield();
        while (!app.Network.PlaygroundInterfaceScriptHandler.IsInGameMenuDisplayed) {
            app.Network.PlaygroundInterfaceScriptHandler.ShowInGameMenu();
            yield();
        }
        app.Network.PlaygroundInterfaceScriptHandler.CloseInGameMenu(CGameScriptHandlerPlaygroundInterface::EInGameMenuResult::Quit);
        AdvanceStep();
    }

    void OnClickEnterMediaTracker() {
        if (!Permissions::OpenAdvancedMapEditor()) {
            throw("Should not call OnClickEnterMediaTracker without adv map editor permissions.");
            return;
        }
        FindAndClickEditorButton("ButtonReplay");
        yield();
        auto app = cast<CGameManiaPlanet>(GetApp());
        app.MenuManager.DialogEditCutScenes_OnIntroEdit();
        AdvanceStep();
        UpdateMatricies();
    }

    void FindAndClickEditorButton(const string &in ButtonMobilName) {
        auto app = GetApp();
        auto editor = cast<CGameCtnEditorFree>(app.Editor);
        if (editor is null) return;
        auto iScene = editor.EditorInterface.InterfaceScene;
        for (uint i = 0; i < iScene.Mobils.Length; i++) {
            auto item = iScene.Mobils[i];
            if (item.IdName == ButtonMobilName) {
                auto controlBase = cast<CControlBase>(item);
                if (controlBase is null) continue;
                controlBase.OnAction();
                break;
            }
        }
    }

    void OnClickAutomaticTrackSetup() {
        auto editor = cast<CGameEditorMediaTracker>(GetApp().Editor);
        if (editor is null) return;
        auto api = cast<CGameEditorMediaTrackerPluginAPI>(editor.PluginAPI);
        api.RemoveAllTracks();
        yield();
        api.CreateTrack(CGameEditorMediaTrackerPluginAPI::EMediaTrackerBlockType::CameraCustom);
        yield();
        api.CreateTrack(CGameEditorMediaTrackerPluginAPI::EMediaTrackerBlockType::Fog);
        yield();
        AutoSetUpFog(1, editor);
        yield();
        api.CreateTrack(CGameEditorMediaTrackerPluginAPI::EMediaTrackerBlockType::FxColors);
        yield();
        AutoSetUpFxColors(2, editor);
        yield();
        UpdateMatricies();
        OnClickAutopopulateCamera();
    }

    void AutoSetUpFxColors(uint trackIx, CGameEditorMediaTracker@ editor) {
        auto api = cast<CGameEditorMediaTrackerPluginAPI>(editor.PluginAPI);
        api.SelectItem(trackIx, 0, 0);
        yield();
        // 0, 4, 0, 2
        /**
         * 0, 0, 0: global intensity; CControlSlider; .Nod :: CGameManialinkSlider; .Value to alter
         * 1, ...: edit far
         * 2, 0, 0 near dist (CControlEntry)
         * 3, 0, 0 near hue (CControlSlider)
         * 4, ...: near saturation label
         * 5, 0, 0/1 near sat fields :: CControlSlider/CControlEntry
         * 6, ...: near brightness
         * 7, 0, 0/1 near brightness fields :: CControlSlider/CControlEntry
         * 8, ...: near contrast
         * 9, 0, 0/1 near contrast fields :: CControlSlider/CControlEntry
         * 10, 0, 0 near inverse (CControlSlider)
         * 11, 12, 13: as above, but red, g, b
         */
        auto globalIntensity = GetOverlayElementAtPath(14, {0, 4, 0, 2, 0, 0, 0});
        auto nearSat = GetOverlayElementAtPath(14, {0, 4, 0, 2, 5, 0, 1});
        auto nearBright = GetOverlayElementAtPath(14, {0, 4, 0, 2, 7, 0, 1});
        // auto nearContrast = GetOverlayElementAtPath(14, {0, 4, 0, 2, 9, 0, 1});
        SetControlEntryValue(nearSat, "0.09");
        SetControlEntryValue(nearBright, "0.02");
        cast<CGameManialinkSlider>(globalIntensity.Nod).Value = 1.0;
        yield();
    }

    void AutoSetUpFog(uint trackIx, CGameEditorMediaTracker@ editor) {
        auto api = cast<CGameEditorMediaTrackerPluginAPI>(editor.PluginAPI);
        api.SelectItem(trackIx, 0, 0);
        yield();
        // 0, 4, 0, 2
        /**
         * 0, 0, 0: Distance; control entry
         * 1, 0, 0: fog intensity, slider
         * 2, 0, 0: sky intensity, slider
         * 3: color label, 4: color picker
         * 5 through 12: nothing / empty
         * 13, 0, 0: cloud opacity, slider
         * 14, 0, 0: cloud speed, entry
         */
        auto fog = GetOverlayElementAtPath(14, {0, 4, 0, 2, 1, 0, 0});
        auto sky = GetOverlayElementAtPath(14, {0, 4, 0, 2, 2, 0, 0});
        auto cloudO = GetOverlayElementAtPath(14, {0, 4, 0, 2, 13, 0, 0});
        // we don't really need to set this, but we do want to trigger a UI update when we change the sliders and `ControlEntry`s have a hack thing that triggers a ui update.
        auto cloudSpeed = GetOverlayElementAtPath(14, {0, 4, 0, 2, 14, 0, 0});

        cast<CGameManialinkSlider>(fog.Nod).Value = 0.;
        cast<CGameManialinkSlider>(sky.Nod).Value = 0.;
        cast<CGameManialinkSlider>(cloudO.Nod).Value = 0.;
        yield();
        SetControlEntryValue(cloudSpeed, "0.1");
        yield();
    }

    void OnClickAutopopulateCamera() {
        auto mtEdior = cast<CGameEditorMediaTracker>(GetApp().Editor);
        if (mtEdior is null) {
            warn("app.Editor does not appear to be a media tracker editor.");
            return;
        }

        // check we're focused on the custom camera
        string ccLabel = "Custom camera";
        auto api = cast<CGameEditorMediaTrackerPluginAPI>(mtEdior.PluginAPI);
        api.SetTimer("0");
        if (api.Clip.Tracks.Length > 0 && api.EditMode != CGameEditorMediaTrackerPluginAPI::EMediaTrackerBlockType::CameraCustom) {
            CGameCtnMediaTrack@ track;
            for (uint i = 0; i < api.Clip.Tracks.Length; i++) {
                @track = api.Clip.Tracks[i];
                if (track.Name == ccLabel) {
                    api.SelectItem(i, 0, 0);
                    yield();
                    break;
                }
            }
            if (track.Name != ccLabel) {
                warn("cannot find custom camera track");
                return;
            }
        }

        // we will go through the overlays to find the specific properties to modify
        // always the same: 0, 4, 0, 2 -- main frame for cam settings
        // then: 0 for target, 1 for anchor, etc
        // after that, need to custom descend based on each frames structure
        // can't set target/anchor stuff (and who cares, easy to do manually)
        // 4: interp; 6: pos inputs, 8: rot inputs, 9: fov, 10: near clip plane

        auto interp = cast<CControlButton>(GetOverlayElementAtPath(14, {0, 4, 0, 2, 4, 0, 0}));

        while (interp.Label != "None") {
            interp.OnAction();
            yield();
            @interp = cast<CControlButton>(GetOverlayElementAtPath(14, {0, 4, 0, 2, 4, 0, 0}));
        }

        // need to get these before each action because they get redrawn;

        auto posX = GetOverlayElementAtPath(14, {0, 4, 0, 2, 6, 0, 0, 1});
        SetControlEntryValue(posX, FmtFloat(cameraPos.x));

        auto posY = GetOverlayElementAtPath(14, {0, 4, 0, 2, 6, 0, 1, 1});
        SetControlEntryValue(posY, FmtFloat(cameraPos.y));

        auto posZ = GetOverlayElementAtPath(14, {0, 4, 0, 2, 6, 0, 2, 1});
        SetControlEntryValue(posZ, FmtFloat(cameraPos.z));

        auto pitch = GetOverlayElementAtPath(14, {0, 4, 0, 2, 8, 0, 0, 1});
        SetControlEntryValue(pitch, FmtFloat(cameraPitchYawRoll.x));

        auto yaw = GetOverlayElementAtPath(14, {0, 4, 0, 2, 8, 0, 1, 1});
        SetControlEntryValue(yaw, FmtFloat(cameraPitchYawRoll.y));

        auto roll = GetOverlayElementAtPath(14, {0, 4, 0, 2, 8, 0, 2, 1});
        SetControlEntryValue(roll, FmtFloat(cameraPitchYawRoll.z));

        auto fov = GetOverlayElementAtPath(14, {0, 4, 0, 2, 9, 0, 0});
        SetControlEntryValue(fov, FmtFloat(cameraFov));

        auto ncp = GetOverlayElementAtPath(14, {0, 4, 0, 2, 10, 0, 0});
        SetControlEntryValue(ncp, FmtFloat(nearZClip));
    }

    string FmtFloat(float v) {
        return Text::Format("%.3f", v);
    }

    CControlBase@ GetOverlayElementAtPath(uint overlayId, uint[] &in path) {
        auto overlay = GetApp().Viewport.Overlays[overlayId];
        auto root = cast<CControlFrame>(cast<CSceneSector>(overlay.UserData).Scene.Mobils[0]);
        return GetElementAtPath(root, path);
    }

    CControlBase@ GetElementAtPath(CControlFrame@ root, uint[] &in path) {
        CControlBase@ next = root;
        for (uint i = 0; i < path.Length; i++) {
            @next = cast<CControlFrame>(next).Childs[path[i]];
        }
        return next;
    }

    void SetControlEntryValue(CControlBase@ _el, const string &in value) {
        auto el = cast<CControlEntry>(_el);
        auto entry = cast<CGameManialinkEntry>(el.Nod);
        entry.HackValueWithEvent = value;
        // yield();
    }

    uint extEnum = 2;
    string extName = ".jpg";

    void OnClickStartScreenshot() {
        auto app = GetApp();
        auto editor = cast<CGameEditorMediaTracker>(app.Editor);
        auto api = cast<CGameEditorMediaTrackerPluginAPI>(editor.PluginAPI);
        api.ShootScreen();
        AdvanceStep();
        while (app.ActiveMenus.Length == 0) yield();
        auto menu = app.ActiveMenus[0];
        auto frame = cast<CControlFrame>(menu.CurrentFrame.Childs[0]);
        auto shootParams = cast<CGameDialogShootParams>(GetElementAtPath(frame, {1, 5, 1}).Nod);
        shootParams.SetQualityPreset_High();
        yield();
        shootParams.Width = shotRes.x;
        shootParams.Height = shotRes.y;
        shootParams.ShootName = mapUid;
        // 0: webp, 2: jpg
        shootParams.ExtScreen = extEnum;
        if (IO::FileExists(CurrScreenShotFilePath)) {
            IO::Delete(CurrScreenShotFilePath);
        }
        sleep(250);
        yield();
        shootParams.OnOk();
        AdvanceStep();
    }

    void OnScreenShotSaved() {
        AdvanceStep();
        startnew(RefreshMapsWithScreenshots);
        // @screenshotImage = UI::LoadTexture(CurrScreenShotFilePath);
        if (!IO::FileExists(CurrScreenShotFilePath)) {
            throw("Screenshot does not exist: " + CurrScreenShotFilePath);
        }
        IO::File imageFile(CurrScreenShotFilePath, IO::FileMode::Read);
        auto imageBuf = imageFile.Read(imageFile.Size());
        imageFile.Close();
        @screenshotImage = UI::LoadTexture(imageBuf);
        imageBuf.Seek(0);
        IO::File imageOut(DestScreenShotFilePath, IO::FileMode::Write);
        imageOut.Write(imageBuf);
        imageOut.Close();
    }

    void OnDontLikeScreenshot() {
        AdvanceStep(-1);
        @screenshotImage = null;
    }

    void OnLikeScreenshot() {
        startnew(SaveMapJsonData);
        AdvanceStep();
    }

    void SaveMapJsonData() {
        auto j = Json::Object();
        j['version'] = 1;
        j['name'] = mapName;
        j['uid'] = mapUid;
        j['author'] = mapAuthor;
        j['aspect'] = int(S_Wiz_Aspect);
        j['rotation'] = m_Rotation;
        j['camPitch'] = camPitch;
        j['padding.x'] = m_padding.x;
        j['padding.y'] = m_padding.y;
        j['offset.x'] = m_offset.x;
        j['offset.y'] = m_offset.y;
        j['offset.z'] = m_offset.z;
        j['min.x'] = mapMin.x;
        j['min.y'] = mapMin.y;
        j['max.x'] = mapMax.x;
        j['max.y'] = mapMax.y;
        j['camPos.x'] = cameraPos.x;
        j['camPos.y'] = cameraPos.y;
        j['camPos.z'] = cameraPos.z;
        j['fov'] = cameraFov;
        Json::ToFile(DestMapInfoJsonFilePath, j);
        startnew(RefreshMapsWithScreenshots);
    }
}


void TextWExclaimation(const string &in msg) {
    UI::TextWrapped("\\$fd1" + Icons::ExclamationCircle + "\\$z  " + msg);
}


/**
 * FrameMain/FrameAfterTools/ButtonReplay




CControlEnum: .Incr/.Decr
0: webp, 2: jpg

paths under:

    auto menu = app.ActiveMenus[0];
    auto frame = cast<CControlFrame>(menu.CurrentFrame.Childs[0]);

// {1} - FrameParameters
// {1, 2} - basics
// -- 0: file format, 2: fps, 4: resY, 6: resX
// {1, 4} - FrameQualityPreset
// -- {1, 4, 3, 0}: button preset high > button
// {1, 5} - framevideoname
// -- {1, 5, 1} - EntryVideoName
// {5} - FrameButtons

bit useless tho b/c we can just use the shoot params obj.

 */


bool Vec2Eq(vec2 a, vec2 b) {
    return a.x == b.x && a.y == b.y;
}

bool Vec3Eq(vec3 a, vec3 b) {
    return a.x == b.x && a.y == b.y && a.z == b.z;
}
