// Shape families which block.properties section a block uses.
#define WSR_FAMILY_NONE 0
#define WSR_FAMILY_SLAB_STAIR 1
#define WSR_FAMILY_FENCE 2
#define WSR_FAMILY_WALL 3
#define WSR_FAMILY_CHORUS 4
#define WSR_FAMILY_LAYERED 5
#define WSR_FAMILY_PRESSURE_PLATE 6
#define WSR_FAMILY_DOOR_TRAPDOOR 7
#define WSR_FAMILY_BUTTON 8
#define WSR_FAMILY_CAPTURED 9
#define WSR_FAMILY_MODEL_CUBOID 10
#define WSR_FAMILY_MODEL_ROD 11
#define WSR_FAMILY_MODEL_FENCE_GATE 12
#define WSR_FAMILY_MODEL_MISC 13
#define WSR_FAMILY_MODEL_TURTLE_EGG 14
#define WSR_FAMILY_FIRST_BOX WSR_FAMILY_LAYERED // families from here on are single-box shapes
#define WSR_FAMILY_FIRST_MODEL WSR_FAMILY_MODEL_CUBOID

#define WSR_MODEL(family, material, model) (uint(material) | (uint(family) << 16u) | (uint(model) << 24u))
// Captured-surface IDs must stay below 22050: records keep rawMat - 20002 in 11 bits.
const int wsrModelFirst = 21202;
const int wsrModelEnd = 21236;
const uint wsrModelTable[wsrModelEnd - wsrModelFirst] = uint[wsrModelEnd - wsrModelFirst](
    WSR_MODEL(WSR_FAMILY_CAPTURED, 5004, 0),            // 21202 sign
    WSR_MODEL(WSR_FAMILY_CAPTURED, 5028, 0),            // 21203 bell
    WSR_MODEL(WSR_FAMILY_CAPTURED, 5016, 0),            // 21204 white_bed
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10496, 0),       // 21205 torch
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10528, 0),       // 21206 soul_torch
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10984, 0),       // 21207 copper_torch
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10109, 1),       // 21208 heavy_core
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10881, 2),       // 21209 cake
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10152, 3),       // 21210 piston
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10532, 3),       // 21211 brown_mushroom_block
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10536, 3),       // 21212 red_mushroom_block
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10540, 3),       // 21213 mushroom_stem
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10569, 4),       // 21214 sniffer_egg
    WSR_MODEL(WSR_FAMILY_MODEL_ROD, 10500, 0),          // 21215 end_rod
    WSR_MODEL(WSR_FAMILY_MODEL_ROD, 10293, 1),          // 21216 lightning_rod
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10157, 0),   // 21217 oak_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10165, 0),   // 21218 spruce_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10173, 0),   // 21219 birch_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10181, 0),   // 21220 jungle_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10189, 0),   // 21221 acacia_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10197, 0),   // 21222 dark_oak_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10205, 0),   // 21223 mangrove_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10213, 0),   // 21224 crimson_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10221, 0),   // 21225 warped_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10757, 0),   // 21226 bamboo_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10761, 0),   // 21227 cherry_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_FENCE_GATE, 10929, 0),   // 21228 pale_oak_fence_gate
    WSR_MODEL(WSR_FAMILY_MODEL_MISC, 10037, 0),         // 21229 anvil
    WSR_MODEL(WSR_FAMILY_MODEL_MISC, 10556, 1),         // 21230 end_portal_frame
    WSR_MODEL(WSR_FAMILY_MODEL_MISC, 10572, 2),         // 21231 dragon_egg
    WSR_MODEL(WSR_FAMILY_MODEL_TURTLE_EGG, 10569, 0),   // 21232 turtle_egg
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10175, 5),       // 21233 chiseled_bookshelf
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10153, 6),       // 21234 upward extended piston base
    WSR_MODEL(WSR_FAMILY_MODEL_CUBOID, 10927, 7)        // 21235 flat pale_moss_carpet
);

bool isReflectionCutoutCube(int mat) {
    return mat == 10293; // copper grate
}

bool isReflectionShapeId(int mat) {
    return mat >= 11264 && mat < wsrModelEnd && (mat < 19456 || mat >= 20002);
}

int getReflectionShapeFamily(int mat) {
    if (mat < 11264 || mat >= wsrModelEnd) return 0;
    if (mat < 19456) return ((mat - 11264) >> 10) + 1;
    if (mat >= wsrModelFirst) return int((wsrModelTable[mat - wsrModelFirst] >> 16u) & 255u);
    return mat >= 20002 ? WSR_FAMILY_CAPTURED : WSR_FAMILY_NONE;
}

int getReflectionMaterial(int mat) {
    if (mat < 11264 || mat >= wsrModelEnd) return mat;
    if (mat < 19456) return 10000 + ((mat - 11264) & 1023);
    if (mat >= wsrModelFirst) return int(wsrModelTable[mat - wsrModelFirst] & 65535u);
    return mat >= 20002 ? mat - 10002 : mat;
}

int getReflectionShapeModel(int mat) {
    if (mat >= wsrModelFirst && mat < wsrModelEnd) return int(wsrModelTable[mat - wsrModelFirst] >> 24u);
    return 0;
}
