/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

//Common//
#include "/lib/common.glsl"

//////////Shadowcomp 1 Bricks//////////Shadowcomp 1 Bricks//////////Shadowcomp 1 Bricks//////////
#ifdef SHADOWCOMP

/* One thread per brick (8x8x8 texels). Builds the list of bricks the floodfill actually has to compute.
We skip a brick if we already know what it would produce:
- dark: no light in or around it, no light source inside, and its voxels haven't changed.
- settled: nothing it reads has changed since this image was last written 2 frames ago, so the floodfill would just
  write back what's already there. */

layout (local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
#if COLORED_LIGHTING_INTERNAL == 128
    const ivec3 workGroups = ivec3(4, 2, 4);
#elif COLORED_LIGHTING_INTERNAL == 192
    const ivec3 workGroups = ivec3(6, 3, 6);
#elif COLORED_LIGHTING_INTERNAL == 256
    const ivec3 workGroups = ivec3(8, 4, 8);
#elif COLORED_LIGHTING_INTERNAL == 384
    const ivec3 workGroups = ivec3(12, 6, 12);
#elif COLORED_LIGHTING_INTERNAL == 512
    const ivec3 workGroups = ivec3(16, 8, 16);
#elif COLORED_LIGHTING_INTERNAL == 768
    const ivec3 workGroups = ivec3(24, 8, 24);
#elif COLORED_LIGHTING_INTERNAL == 1024
    const ivec3 workGroups = ivec3(32, 8, 32);
#else
    const ivec3 workGroups = ivec3(1, 1, 1);
#endif

#if COLORED_LIGHTING_INTERNAL > 0

//Common Variables//
layout(r16ui) uniform uimage3D actBrick_img;
shared uint groupBrickCount;
shared uint groupBrickBase;
shared uint groupClearCount;
shared uint groupClearBase;

//Includes//
#include "/lib/voxelization/lightVoxelization.glsl"
#include "/lib/voxelization/actState.glsl"

//Common Functions//
ivec3 WrapBrick(ivec3 storageBrick) {
    return (storageBrick + brickGrid) % brickGrid;
}

uint LoadBrickFlags(ivec3 storageBrick, int layer) {
    return imageLoad(actBrick_img, GetBrickFlagTexel(storageBrick, layer)).r;
}

bool GetBrickVoxelOrigin(ivec3 storageBrick, ivec3 cameraBlock, out ivec3 lo) {
    lo = LightStorageToVoxel(storageBrick * 8, GetLightStorageOffset(cameraBlock));
    return all(lessThan(lo + 7, voxelVolumeSize));
}

bool IsBrickInterior(ivec3 storageBrick, ivec3 cameraBlock) {
    ivec3 lo;
    return GetBrickVoxelOrigin(storageBrick, cameraBlock, lo) && all(greaterThanEqual(lo, ivec3(1))) && all(lessThanEqual(lo + 7, voxelVolumeSize - 2));
}

// World block at the brick's first texel. After a long camera jump a texel can hold a different world block even
// when the brick is away from the volume's edges at both cameras.
ivec3 GetBrickWorldOrigin(ivec3 storageBrick, ivec3 cameraBlock) {
    return LightStorageToVoxel(storageBrick * 8, GetLightStorageOffset(cameraBlock)) + cameraBlock;
}

uint GetBrickCameraClass(ivec3 lo, vec3 viewDirection) {
    uint cameraClass = 0u;
    ivec3 hi = lo + 7;
    ivec3 centre = voxelVolumeSize / 2;
    ivec3 nearDist = max(max(lo - centre, centre - hi), ivec3(0));
    ivec3 farDist = max(abs(lo - centre), abs(hi - centre));
    bool allBeyond = nearDist.x + nearDist.y + nearDist.z > 16;
    bool allWithin = farDist.x + farDist.y + farDist.z <= 16;
    cameraClass |= allWithin ? 1u : (allBeyond ? 2u : 0u);

    int halfZ = voxelVolumeSize.z / 2;
    bool allCopy = int(framemod2) == 0 ? lo.z > halfZ : hi.z < halfZ;
    bool allSpread = int(framemod2) == 0 ? hi.z <= halfZ : lo.z >= halfZ;
    cameraClass |= allCopy ? 4u : (allSpread ? 8u : 0u);

    if (!allWithin) {
        bool allBehind = true, allFront = true;
        for (int i = 0; i < 8; i++) {
            vec3 posM = vec3(PickBoxCorner(lo, hi, i)) / vec3(voxelVolumeSize) - 0.5;
            float d = dot(posM, viewDirection);
            float margin = 1e-4 * length(posM);
            allBehind = allBehind && d < -margin;
            allFront = allFront && d > margin;
        }
        cameraClass |= allBehind ? 16u : (allFront ? 32u : 0u);
    }
    return cameraClass;
}

bool IsBrickAnchored(ivec3 storageBrick, ivec3 cameras[4]) {
    ivec3 origin = GetBrickWorldOrigin(storageBrick, cameras[0]);
    for (int i = 0; i < 4; i++) {
        if (!IsBrickInterior(storageBrick, cameras[i]) || any(notEqual(GetBrickWorldOrigin(storageBrick, cameras[i]), origin))) return false;
    }
    return true;
}

bool IsBrickCameraClassStable(ivec3 storageBrick, ivec3 cameraNow, ivec3 cameraAgo2, vec3 viewNow, vec3 viewAgo2) {
    ivec3 lo0, lo2;
    if (!GetBrickVoxelOrigin(storageBrick, cameraNow, lo0) || !GetBrickVoxelOrigin(storageBrick, cameraAgo2, lo2)) return false;
    uint cameraClassNow = GetBrickCameraClass(lo0, viewNow), cameraClassAgo2 = GetBrickCameraClass(lo2, viewAgo2);
    if (cameraClassNow != cameraClassAgo2) return false;
    bool distanceKnown = (cameraClassNow & 3u) != 0u;
    bool halfRateKnown = (cameraClassNow & 12u) != 0u;
    bool behindKnown = (cameraClassNow & 1u) != 0u || (cameraClassNow & 48u) != 0u;
    return distanceKnown && halfRateKnown && behindKnown;
}

//Program//
void main() {
    ivec3 storageBrick = ivec3(gl_GlobalInvocationID);
    int frameParity = int(framemod2);
    int sourceLayer = frameParity;
    int destLayer = 1 - frameParity;
    ivec3 cameraNow = GetFloodfillCameraBlock();
    ivec3 cameraAgo1 = GetHistoryCameraBlock(1);
    ivec3 cameraAgo2 = GetHistoryCameraBlock(2);
    ivec3 cameraAgo3 = GetHistoryCameraBlock(3);
    vec3 viewNow = GetFloodfillViewDirection();
    vec3 viewAgo2 = GetHistoryViewDirection(2);

    if (gl_LocalInvocationIndex == 0u) { groupBrickCount = 0u; groupClearCount = 0u; }
    if (all(equal(gl_GlobalInvocationID, uvec3(0u)))) {
        actState[1 - frameParity] = 0u;
        SetHistoryViewDirection(viewNow); // slot of 4 frames ago, nobody reads it now
        actState[actLastFrameWord] = uint(frameCounter) + 1u;
        actState[actLastFrameTimeWord] = floatBitsToUint(frameTimeCounter);
        actState[actClearCountWord + uint(1 - frameParity)] = 0u;
    }
    barrier();

    uint needsCompute = 1u;
    bool voxelsWritten = false;
    #ifdef ACT_BRICK_SKIP
        ivec3 lightSourceTexel = GetBrickFlagTexel(storageBrick, actLayerLightSource);
        needsCompute = imageLoad(actBrick_img, lightSourceTexel).r;
        imageStore(actBrick_img, lightSourceTexel, uvec4(0u));
        uint destFlags = LoadBrickFlags(storageBrick, destLayer);
        needsCompute |= destFlags & actFlagAnyLight;
        ivec3 currentLo;
        bool contiguous = GetBrickVoxelOrigin(storageBrick, cameraNow, currentLo);
        ivec3 cameraDelta = cameraNow - cameraAgo1;
        #ifdef ACT_RETAIN_BEHIND_PLAYER
            if (!contiguous && cameraNow != cameraAgo1) needsCompute = 1u;
            ivec3 previousLo = currentLo + cameraDelta;
            if (contiguous && (any(lessThan(previousLo, ivec3(-1))) || any(greaterThan(previousLo + 7, voxelVolumeSize)))) needsCompute = 1u;
        #else
            // A wrapped axis contains both volume endpoints. Clamping by up to one brick still
            // reads from the 3x3x3 source neighbourhood checked below.
            const int brickWidth = 8;
            ivec3 currentHi = currentLo + brickWidth - 1;
            ivec3 previousLo = currentLo * ivec3(lessThan(currentHi, voxelVolumeSize)) + cameraDelta;
            ivec3 previousHi = min(currentHi, voxelVolumeSize - 1) + cameraDelta;
            if (any(lessThan(previousLo, ivec3(-brickWidth))) ||
                any(greaterThan(previousHi, voxelVolumeSize - 1 + brickWidth))) needsCompute = 1u;
        #endif
        for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
            needsCompute |= LoadBrickFlags(WrapBrick(storageBrick + ivec3(x, y, z)), sourceLayer) & actFlagAnyLight;
        }
        uint sourceChanges = LoadBrickFlags(storageBrick, sourceLayer) & actFlagAnyChange;
        for (int axis = 0; axis < 3; axis++) {
            ivec3 axisStep = ivec3(axis == 0, axis == 1, axis == 2);
            uint below = LoadBrickFlags(WrapBrick(storageBrick - axisStep), sourceLayer);
            uint above = LoadBrickFlags(WrapBrick(storageBrick + axisStep), sourceLayer);
            sourceChanges |= (below >> (actFlagFaceShift + uint(2 * axis + 1))) & 1u; // its + face
            sourceChanges |= (above >> (actFlagFaceShift + uint(2 * axis))) & 1u;     // its - face
        }

        uint hashNow = GetBrickHashIndex(storageBrick, frameParity), hashLast = GetBrickHashIndex(storageBrick, 1 - frameParity);
        bool voxelsChanged = actState[hashNow] != actState[hashLast] || actState[hashNow + 1u] != actState[hashLast + 1u]
                          || (actState[hashNow + 2u] | actState[hashLast + 2u]) != 0u;
        voxelsWritten = (actState[hashNow] | actState[hashNow + 1u] | actState[hashNow + 2u]) != 0u;
        ClearBrickHash(storageBrick, 1 - frameParity);
        ivec3 stateTexel = GetBrickFlagTexel(storageBrick, actLayerState);
        bool voxelsChangedLastFrame = (imageLoad(actBrick_img, stateTexel).r & 1u) != 0u;
        imageStore(actBrick_img, stateTexel, uvec4(voxelsChanged ? 1u : 0u));

        uint historyLength = actState[actHistoryLengthWord];
        if (historyLength == 0u || voxelsChanged || voxelsChangedLastFrame) {
            // Even in darkness an edit can switch red between +0.0 and -0.0.
            needsCompute = 1u;
        } else if (needsCompute != 0u) {
            bool sameCamera = false;
            #ifndef ACT_RETAIN_BEHIND_PLAYER
                // Even a brick crossing the volume seam or view plane repeats its per-voxel
                // decisions when the camera blocks match and this parity has the same view.
                sameCamera = cameraNow == cameraAgo1 && cameraNow == cameraAgo2 && cameraNow == cameraAgo3 && viewNow == viewAgo2;
            #endif
            bool settled = historyLength >= 3u && sourceChanges == 0u && (sameCamera || (
                IsBrickAnchored(storageBrick, ivec3[4](cameraNow, cameraAgo1, cameraAgo2, cameraAgo3))
                && IsBrickCameraClassStable(storageBrick, cameraNow, cameraAgo2, viewNow, viewAgo2)));
            if (settled) needsCompute = 0u;
        }
        if (needsCompute == 0u) imageStore(actBrick_img, GetBrickFlagTexel(storageBrick, destLayer), uvec4(destFlags & (actFlagAnyLight | actCheckSolidVoxels)));
    #endif

    uint listSlot = 0u, clearSlot = 0u;
    if (needsCompute != 0u) listSlot = atomicAdd(groupBrickCount, 1u);
    if (voxelsWritten) clearSlot = atomicAdd(groupClearCount, 1u);
    barrier();
    if (gl_LocalInvocationIndex == 0u) {
        if (groupBrickCount > 0u) groupBrickBase = atomicAdd(actState[frameParity], groupBrickCount);
        if (groupClearCount > 0u) groupClearBase = atomicAdd(actState[actClearCountWord + uint(frameParity)], groupClearCount);
    }
    barrier();
    if (needsCompute != 0u) actState[actBrickListStart + groupBrickBase + listSlot] = PackBrick(storageBrick);
    if (voxelsWritten) actState[GetClearListIndex(groupClearBase + clearSlot)] = PackBrick(storageBrick);
}

#else
void main() {}
#endif

#endif
