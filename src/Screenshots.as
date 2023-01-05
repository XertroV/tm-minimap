class MapWithScreenshot {
    vec2 padding, offset, min, max, center;
    vec3 min3, max3, center3, camPos;
    float rotation, camPitch;
    string mapUid, imgPath, jsonPath, mapName, mapAuthor;
    Json::Value@ j;
    ScreenShot::Aspect aspect;
    float aspectRatio, fov;
    mat4 rot, imgRot, camRot, camDiffRot, trans, untrans, unrot, perspective, projection;

    MapWithScreenshot(const string &in imgPath, const string &in jsonPath) {
        this.imgPath = imgPath;
        this.jsonPath = jsonPath;
        @j = Json::FromFile(jsonPath);
        mapUid = j['uid'];
        mapName = j['name'];
        mapAuthor = j.Get('author', "Unknown");
        padding = vec2(j['padding.x'], j['padding.y']);
        offset = vec2(j['offset.x'], j['offset.y']);
        min = vec2(j['min.x'], j['min.y']);
        max = vec2(j['max.x'], j['max.y']);
        center = (max + min) / 2.;
        min3 = vec3(min.x, 0, min.y);
        max3 = vec3(max.x, 0, max.y);
        center3 = vec3(center.x, 0, center.y);
        camPos = vec3(j['camPos.x'], j['camPos.y'], j['camPos.z']);
        rotation = j['rotation'];
        camPitch = j.Get('camPitch', -90);
        fov = j['fov'];
        aspect = ScreenShot::Aspect(int(j['aspect']));
        aspectRatio = ScreenShot::AspectToRatio(aspect);
        imgRot = mat4::Rotate(Math::ToRad(rotation), vec3(0, 1, 0));
        camRot = mat4::Rotate(Math::ToRad(-camPitch), vec3(1, 0, 0));
        camDiffRot = mat4::Rotate(-Math::ToRad(camPitch + 90), vec3(1, 0, 0));
        rot = imgRot * camRot;
        trans = mat4::Translate(camPos);
        untrans = mat4::Inverse(trans);
        unrot = mat4::Inverse(rot);
        perspective = mat4::Perspective(fov, aspectRatio, 1, 100000);
        projection = perspective * mat4::Inverse(trans * rot);
    }

    MemoryBuffer@ ReadImageFile() {
        IO::File img(imgPath, IO::FileMode::Read);
        auto buf = img.Read(img.Size());
        img.Close();
        return buf;
    }

    vec2 ProjectPoint(vec3 pos) {
        vec4 ret = projection * pos;
        if (ret.w == 0)
            return vec2();
        return ret.xyz.xy / ret.w;
    }
}


MapWithScreenshot@[] mapsWithScreenshots;
dictionary mapWithScreenshotsLookup;


void RefreshMapsWithScreenshots() {
    mapsWithScreenshots.RemoveRange(0, mapsWithScreenshots.Length);
    mapWithScreenshotsLookup.DeleteAll();

    // find candidate map UIDs
    auto bgFolder = IO::FromStorageFolder("bgs");
    auto files = IO::IndexFolder(bgFolder, false);
    string[] checkUids;
    for (uint i = 0; i < files.Length; i++) {
        auto file = files[i];
        auto fileLower = file.ToLower();
        if (fileLower.EndsWith(".jpg") || fileLower.EndsWith(".json") || fileLower.EndsWith(".png")) {
            auto parts = file.Split("/");
            auto noExt = parts[parts.Length - 1].Split(".")[0];
            if (noExt.Length > 23 && noExt.Length < 30 && checkUids.Find(noExt) == -1) {
                checkUids.InsertLast(noExt);
                // trace('cand: ' + noExt);
            }
        }
    }
    trace('Refreshing MapsWithScreenshots, found ' + checkUids.Length + ' candidates.');

    // check the right files exist and, if so,
    for (uint i = 0; i < checkUids.Length; i++) {
        auto uid = checkUids[i];
        auto basePath = bgFolder + "/" + uid;
        auto hasPng = IO::FileExists(basePath + ".png");
        auto hasJpg = IO::FileExists(basePath + ".jpg");
        auto hasJson = IO::FileExists(basePath + ".json");
        if (!hasJson || !(hasJpg || hasPng)) continue;
        MapWithScreenshot@ mws = null;
        try {
            // prefer png because transparency. ppl can edit the .jpg after it's generated.
            @mws = MapWithScreenshot(basePath + (hasPng ? ".png" : ".jpg"), basePath + ".json");
        } catch {
            warn("Exception loading map with screenshot (uid:" + uid + "): " + getExceptionInfo());
        }
        if (mws is null) continue;
        mapsWithScreenshots.InsertLast(mws);
        @mapWithScreenshotsLookup[uid] = mws;
    }
    trace('Found ' + mapsWithScreenshots.Length + ' maps with screenshots and config.');
}

MapWithScreenshot@ GetMapScreenshotOrNull(const string &in uid) {
    MapWithScreenshot@ ret = null;
    if (mapWithScreenshotsLookup.Get(uid, @ret)) {
        return ret;
    }
    trace('no screenshot data found for ' + uid);
    trace(tostring(mapWithScreenshotsLookup.GetSize()));
    trace(tostring(mapWithScreenshotsLookup.Exists(uid)));
    trace(tostring(mapWithScreenshotsLookup.GetKeys().Find(uid)));
    auto keys = mapWithScreenshotsLookup.GetKeys();
    for (uint i = 0; i < keys.Length; i++) {
        auto item = keys[i];
        print(item);

    }
    return null;
    // if (!mapWithScreenshotsLookup.Exists(uid)) return null;
    // MapWithScreenshot@ ret = cast<MapWithScreenshot>(mapWithScreenshotsLookup[uid]);
    // if (ret is null) warn("GetMapScreenshotOrNull unexpected null for " + uid);
    // return ret;
}
