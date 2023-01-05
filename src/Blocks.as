vec3 CoordToPos(nat3 coord) {
    return vec3(coord.x * 32, coord.y * 8, coord.z * 32);
}

// dictionary seenBlocks;



// array<vec3> GetBlockPositions() {
//     auto ret = array<vec3>();
//     if (GetApp().RootMap is null) return {};
//     auto map = GetApp().RootMap;
//     // MwFastBuffer<CGameCtnBlock@> blocks = map.Blocks;
//     for (uint i = 0; i < map.BakedBlocks.Length; i++) {
//         CGameCtnBlock@ block = map.BakedBlocks[i];
//         if (
//             // true
//             block.BlockInfo.Name != "Grass"
//             && !block.BlockInfo.IsPillar
//             && !block.BlockInfo.IsPodium
//             && !block.BlockInfo.IsTerrain
//             && !block.BlockInfo.IsInternal
//             && !block.BlockInfo.Name.Contains("Deco")
//             // && !block.DescId.GetName().Contains("Base")
//             && !block.BlockInfo.Name.Contains("Structure")
//             ) {
//             MbExplore("Block-" + Time::Now, block);
//             if (ShouldAddBlock(block.Coord))
//                 ret.InsertLast(CoordToPos(block.Coord));
//         }
//     }
//     return ret;
// }

// bool ShouldAddBlock(nat3 coord) {
//     if (!seenBlocks.Exists(coord.ToString())) {
//         seenBlocks[coord.ToString()] = true;
//         return true;
//     }
//     return false;
// }

// bool openedOnce = false;
// void MbExplore(const string &in tabName, CMwNod@ nod) {
//     if (openedOnce) return;
//     openedOnce = true;
//     ExploreNod(tabName, nod);
// }
