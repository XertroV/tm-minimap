namespace Map {
    string prevId = "";
    string mapId = "";

    void UpdateMapInfoLoop() {
        string _id;
        while (true) {
            _id = (GetApp().RootMap is null) ? "" : GetApp().RootMap.MapInfo.MapUid;
            if (_id != mapId) {
                prevId = mapId;
                mapId = _id;
                OnChangeMap();
            }
            yield();
        }
    }

    array<CoroutineFunc@> cbs;

    void OnChangeMap() {
        for (uint i = 0; i < cbs.Length; i++) {
            try {
                cbs[i]();
            } catch {
                warn("Caught error in cb index: " + i);
                cbs.RemoveAt(i);
                i--;
            }
        }
    }

    void RegisterMapChangeCb(CoroutineFunc@ func) {
        cbs.InsertLast(func);
    }
}
