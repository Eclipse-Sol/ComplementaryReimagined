#if COLORED_LIGHTING < 512
    const ivec3 sceneVoxelVolumeSize = ivec3(COLORED_LIGHTING_INTERNAL, 64, COLORED_LIGHTING_INTERNAL);
#else
    const ivec3 sceneVoxelVolumeSize = ivec3(512, 64, 512);
#endif

#if WORLD_SPACE_SHAPES > 0
    const ivec3 sceneVoxelCoarseCellSize = ivec3(16, 4, 16);
    const ivec3 originSnapBias = ivec3(8, 0, 8);
#else
    const ivec3 sceneVoxelCoarseCellSize = ivec3(16);
    const ivec3 originSnapBias = ivec3(8);
#endif
const ivec3 sceneVoxelCoarseVolumeSize = sceneVoxelVolumeSize / sceneVoxelCoarseCellSize;
const ivec3 sceneVoxelLodVolumeSize = sceneVoxelVolumeSize / 4;
const int lavaCornerCount = (sceneVoxelVolumeSize.x + 1) * sceneVoxelVolumeSize.y * (sceneVoxelVolumeSize.z + 1);
const int sceneVoxelCount = sceneVoxelVolumeSize.x * sceneVoxelVolumeSize.y * sceneVoxelVolumeSize.z;
const int reflectionFaceCount = 6 * sceneVoxelCount;
#if COLORED_LIGHTING >= 384
    const uint reflectionFaceCapacity = 2097151u;
#elif COLORED_LIGHTING >= 256
    const uint reflectionFaceCapacity = 1048575u;
#elif COLORED_LIGHTING >= 192
    const uint reflectionFaceCapacity = 524287u;
#else
    const uint reflectionFaceCapacity = 262143u;
#endif
const uint reflectionFacePointerMask = 4194303u;
const uint reflectionFaceStampMask = 0xffc00000u;
#define WSR_MAX_REGIONS 20
const int reflectionActiveRegionCount = int(100.0 / WSR_REBUILD_PERCENT + 0.5);
const int reflectionMaxRegionCount = reflectionActiveRegionCount >= 1 && reflectionActiveRegionCount <= WSR_MAX_REGIONS ? WSR_MAX_REGIONS : -1;

uint GetReflectionRingIndex(uint start, uint offset, uint capacity) {
    return (start + offset) % capacity;
}

uint GetReflectionRingFreeCount(uint start, uint tail, uint capacity) {
    return capacity - 1u - ((start + capacity - tail) % capacity);
}

ivec3 PositiveModulo(ivec3 p, ivec3 size) {
    ivec3 remainder = abs(p) % size;
    ivec3 negative = ivec3(lessThan(p, ivec3(0)));
    return remainder * (1 - negative) + ((size - remainder) % size) * negative;
}

int PositiveModulo(int p, int size) {
    int remainder = abs(p) % size;
    return p < 0 ? (size - remainder) % size : remainder;
}

ivec3 GetReflectionVolumeOrigin() {
    ivec3 block = cameraPositionBestInt + originSnapBias;
    return block - PositiveModulo(block, sceneVoxelCoarseCellSize) - sceneVoxelVolumeSize / 2;
}

ivec3 GetSceneVoxelStoragePosition(ivec3 p) {
    #if WORLD_SPACE_SHAPES > 0
        return PositiveModulo(p + GetReflectionVolumeOrigin(), sceneVoxelVolumeSize);
    #else
        return p;
    #endif
}

ivec3 WrapReflectionStoragePosition(ivec3 p, ivec3 storageOrigin, ivec3 size) {
    p += storageOrigin;
    return p - ivec3(greaterThanEqual(p, size)) * size;
}

ivec3 GetSceneVoxelLodStoragePosition(ivec3 p) {
    #if WORLD_SPACE_SHAPES > 0
        return PositiveModulo(p + GetReflectionVolumeOrigin() / 4, sceneVoxelVolumeSize / 4);
    #else
        return p;
    #endif
}

ivec3 GetSceneVoxelCoarseStoragePosition(ivec3 p) {
    #if WORLD_SPACE_SHAPES > 0
        return PositiveModulo(p + GetReflectionVolumeOrigin() / sceneVoxelCoarseCellSize, sceneVoxelCoarseVolumeSize);
    #else
        return p;
    #endif
}

int HashTileToRegion(ivec3 worldTile) {
    return PositiveModulo(worldTile.x + 7 * worldTile.y + 11 * worldTile.z, reflectionActiveRegionCount);
}

bool IsReflectionLavaRefreshFrame(int frame) {
    return frame % reflectionActiveRegionCount == 0;
}

int GetPackedRegionTileOffset() {
    ivec3 origin = GetReflectionVolumeOrigin();
    int originYOffset = PositiveModulo(origin.y, 16);
    ivec3 tiles = ivec3(origin.x / 16, (origin.y - originYOffset) / 16, origin.z / 16);
    return (HashTileToRegion(tiles) << 4) | originYOffset;
}

int GetReflectionCellRegion(ivec3 p, int packedRegionOrigin) {
    ivec3 tile = ivec3(p.x / 16, (p.y + (packedRegionOrigin & 15)) / 16, p.z / 16);
    return HashTileToRegion(tile + ivec3(packedRegionOrigin >> 4, 0, 0));
}

int GetReflectionCellRegion(ivec3 p) {
    ivec3 origin = GetReflectionVolumeOrigin();
    int originYOffset = PositiveModulo(origin.y, 16);
    ivec3 tile = ivec3(p.x / 16 + origin.x / 16,
        (p.y + originYOffset) / 16 + (origin.y - originYOffset) / 16, p.z / 16 + origin.z / 16);
    return HashTileToRegion(tile);
}

struct reflectionCellHandle {
    int storageIndex;
    uint regionGeneration;
};

int GetSceneVoxelIndexFromStorage(ivec3 p) {
    return p.x + sceneVoxelVolumeSize.x * (p.y + sceneVoxelVolumeSize.y * p.z);
}

int GetSceneVoxelIndex(ivec3 p) {
    return GetSceneVoxelIndexFromStorage(GetSceneVoxelStoragePosition(p));
}

ivec3 GetSceneVoxelPosition(uint storageIndex, ivec3 storageOrigin) {
    ivec3 p = ivec3(storageIndex % uint(sceneVoxelVolumeSize.x),
        (storageIndex / uint(sceneVoxelVolumeSize.x)) % uint(sceneVoxelVolumeSize.y),
        storageIndex / uint(sceneVoxelVolumeSize.x * sceneVoxelVolumeSize.y));
    p -= storageOrigin;
    return p + ivec3(lessThan(p, ivec3(0))) * sceneVoxelVolumeSize;
}

ivec3 GetSceneVoxelPosition(uint storageIndex) {
    #if WORLD_SPACE_SHAPES > 0
        return GetSceneVoxelPosition(storageIndex, PositiveModulo(GetReflectionVolumeOrigin(), sceneVoxelVolumeSize));
    #else
        return GetSceneVoxelPosition(storageIndex, ivec3(0));
    #endif
}
