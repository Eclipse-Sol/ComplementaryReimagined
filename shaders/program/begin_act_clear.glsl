/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

//Common//
#include "/lib/common.glsl"

//////////Begin 3 ACT Voxel Clear//////////Begin 3 ACT Voxel Clear//////////Begin 3 ACT Voxel Clear//////////

/* Clears the voxel map (voxel_img) only where last frame's shadow pass wrote */

#if COLORED_LIGHTING_INTERNAL > 0
    #define ACT_VOXEL_CLEAR

    layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
    const ivec3 workGroups = ivec3(4096, 1, 1);

    //Common Variables//
    layout(r32ui) writeonly uniform uimage3D voxel_img;
    writeonly uniform image3D floodfill_img;
    writeonly uniform image3D floodfill_img_copy;
    layout(r16ui) writeonly uniform uimage3D actBrick_img;

    //Includes//
    #include "/lib/voxelization/lightVoxelization.glsl"

    //Program//
    void main() {
        int lastFrameParity = 1 - int(framemod2);
        // Iris wraps frameCounter at 720720 and frameTimeCounter at one hour. Creating another dimension's
        // pipeline can reset both clocks, so check the elapsed frame time as well as the counter.
        float expectedTime = uintBitsToFloat(actState[actLastFrameTimeWord]) + frameTime;
        if (expectedTime >= 3600.0) expectedTime = 0.0;
        bool resetHistory = actState[actLastFrameWord] != (frameCounter == 0 ? 720720u : uint(frameCounter))
                         || abs(expectedTime - frameTimeCounter) > 0.001;
        if (all(equal(gl_GlobalInvocationID, uvec3(0u)))) {
            ivec3 cameraBlock = cameraPositionBestInt;
            #ifdef ACT_TRACK_CAMERA_DELTA
                if (!resetHistory) cameraBlock = GetHistoryCameraBlock(1) + (cameraPositionBestInt - previousCameraPositionBestInt);
            #endif
            SetHistoryCameraBlock(cameraBlock);
            actState[actHistoryLengthWord] = resetHistory ? 0u : min(actState[actHistoryLengthWord] + 1u, 3u);
            if (resetHistory) {
                for (uint slot = 0u; slot < 2u; slot++) {
                    actState[slot] = 0u;
                    actState[actClearCountWord + slot] = 0u;
                }
            }
        }
        #ifdef ACT_BRICK_SKIP
            bool clearAll = resetHistory;
        #else
            bool clearAll = true;
        #endif
        uint entries = clearAll ? volumeBrickCount : min(actState[actClearCountWord + uint(lastFrameParity)], volumeBrickCount);
        ivec3 storageOffset = clearAll ? ivec3(0) : GetLightStorageOffset(GetHistoryCameraBlock(1));

        for (uint entry = gl_WorkGroupID.x; entry < entries; entry += gl_NumWorkGroups.x) {
            ivec3 storageBrick = clearAll ? LinearIndexToBrick(entry) : UnpackBrick(actState[GetClearListIndex(entry)]);

            if (resetHistory && gl_LocalInvocationIndex == 0u) {
                for (int slot = 0; slot < 2; slot++) ClearBrickHash(storageBrick, slot);
                for (int layer = 0; layer < 4; layer++) imageStore(actBrick_img, GetBrickFlagTexel(storageBrick, layer), uvec4(0u));
            }
            for (int z = 0; z < 8; z++) {
                ivec3 storagePos = storageBrick * 8 + ivec3(gl_LocalInvocationID.xy, z);
                imageStore(voxel_img, LightStorageToVoxel(storagePos, storageOffset), uvec4(0u));
                if (resetHistory) {
                    imageStore(floodfill_img, storagePos, vec4(0.0));
                    imageStore(floodfill_img_copy, storagePos, vec4(0.0));
                }
            }
        }
    }
#else
    layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
    const ivec3 workGroups = ivec3(1, 1, 1);

    void main() {}
#endif
