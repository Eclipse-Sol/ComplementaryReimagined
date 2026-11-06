#if COLORED_LIGHTING < 512
    const ivec3 sceneVoxelVolumeSize = ivec3(COLORED_LIGHTING_INTERNAL, 64, COLORED_LIGHTING_INTERNAL);
#else
    const ivec3 sceneVoxelVolumeSize = ivec3(512, 64, 512);
#endif

const ivec3 sceneVoxelLodVolumeSize = sceneVoxelVolumeSize / 4;
const int lavaCornerCount = (sceneVoxelVolumeSize.x + 1) * sceneVoxelVolumeSize.y * (sceneVoxelVolumeSize.z + 1);
const int sceneVoxelCount = sceneVoxelVolumeSize.x * sceneVoxelVolumeSize.y * sceneVoxelVolumeSize.z;
#define WSR_REFRESH_INTERVAL 8

int getSceneVoxelIndex(ivec3 p) {
    return p.x + sceneVoxelVolumeSize.x * (p.y + sceneVoxelVolumeSize.y * p.z);
}

bool isReflectionPeriodicRefresh(int frame) {
    return (frame & (WSR_REFRESH_INTERVAL - 1)) == 0;
}

bool isReflectionPeriodicRefresh() {
    return isReflectionPeriodicRefresh(frameCounter);
}

bool isReflectionVoxelRefreshDue() {
    #if WORLD_SPACE_SHAPES > 0
        #if IRIS_VERSION >= 10800
            bool moved = cameraPositionInt != previousCameraPositionInt;
        #else
            bool moved = ivec3(floor(cameraPosition)) != ivec3(floor(previousCameraPosition));
        #endif
        return moved || isReflectionPeriodicRefresh();
    #else
        return true;
    #endif
}

#if WORLD_SPACE_SHAPES > 0
    const int reflectionMetadataCount = lavaCornerCount + sceneVoxelCount;
#else
    const int reflectionMetadataCount = lavaCornerCount;
#endif
