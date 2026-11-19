#include "/lib/voxelization/reflectionVoxelVolume.glsl"

vec3 PlayerToSceneVoxel(vec3 playerPos) {
    vec3 position = playerPos + cameraPositionBestFract + 0.5 * vec3(sceneVoxelVolumeSize);
    #if WORLD_SPACE_SHAPES > 0
        position += vec3(cameraPositionBestInt - GetReflectionVolumeOrigin() - sceneVoxelVolumeSize / 2);
    #endif
    return position;
}

vec3 PlayerToPreviousSceneVoxel(vec3 previousPlayerPos) {
    return previousPlayerPos + previousCameraPositionBestFract + 0.5 * vec3(sceneVoxelVolumeSize);
}

float GetReflectionVolumeFade(vec3 playerPos) {
    vec3 cameraEdgeDistance = 0.5 * vec3(sceneVoxelVolumeSize) - abs(playerPos);
    float volumeFade = 0.9 * sqrt3(minOf(smoothstep(0.0, 32.0, cameraEdgeDistance))) + 0.1;
    #if WORLD_SPACE_SHAPES > 0
        vec3 cameraGridOffset = vec3((cameraPositionBestInt + originSnapBias) & (sceneVoxelCoarseCellSize - 1))
                    + cameraPositionBestFract - vec3(originSnapBias);
        vec3 cacheEdgeDistance = cameraEdgeDistance - abs(cameraGridOffset);
        float halfHeight = 0.5 * float(sceneVoxelVolumeSize.y);
        float lowerFadeInset = 4.0 * smoothstep(2.0, 4.0, cameraGridOffset.y);
        float upperFadeInset = 4.0 * (1.0 - smoothstep(0.0, 2.0, cameraGridOffset.y));
        float cameraVoxelY = halfHeight + cameraGridOffset.y;
        cacheEdgeDistance.y = min(cameraVoxelY + playerPos.y - lowerFadeInset,
            float(sceneVoxelVolumeSize.y) - upperFadeInset - cameraVoxelY - playerPos.y);
        volumeFade = min(volumeFade, smoothstep(0.0, 8.0, minOf(cacheEdgeDistance)));
    #endif
    return volumeFade;
}

bool CheckInsideSceneVoxelVolume(vec3 voxelPos) {
    return all(greaterThanEqual(voxelPos, vec3(0.0)))
        && all(lessThan(voxelPos, vec3(sceneVoxelVolumeSize)));
}

bool CheckInsideLodVoxelVolume(vec3 voxelPos) {
    return all(greaterThanEqual(voxelPos, vec3(0.0)))
        && all(lessThan(voxelPos, vec3(sceneVoxelLodVolumeSize)));
}

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_SCATTER
    void StoreReflectionCoarseOccupancy(ivec3 cell) {
        imageStore(wsr_coarse_img, GetSceneVoxelCoarseStoragePosition(cell / sceneVoxelCoarseCellSize), uvec4(1u, 0u, 0u, 0u));
    }
#endif

#if defined SHADOW && defined VERTEX_SHADER
    vec3 ModelToScenePos(vec3 modelPos) {
        vec3 viewPos = mat3(gl_ModelViewMatrix) * modelPos + gl_ModelViewMatrix[3].xyz;
        return mat3(shadowModelViewInverse) * viewPos + shadowModelViewInverse[3].xyz;
    }

    vec3 GetBlockCenterModelPos() {
        return gl_Vertex.xyz + at_midBlock.xyz / 64.0;
    }
#endif

#include "/lib/voxelization/reflectionVoxelData.glsl"

#if defined SHADOW && defined VERTEX_SHADER && WORLD_SPACE_SHAPES > 0
    // Only captured shapes outside the selected region need neighboring tiles.
    bool IsReflectionCaptureHalo(ivec3 cell) {
        ivec3 origin = GetReflectionVolumeOrigin();
        int originYOffset = PositiveModulo(origin.y, 16);
        ivec3 phase = ivec3(0, originYOffset, 0);
        ivec3 first = (max(cell - 3, ivec3(0)) + phase) / 16;
        ivec3 last = (min(cell + 3, sceneVoxelVolumeSize - 1) + phase) / 16;
        // The halo spans at most two tiles on each axis. Hash the first once;
        // the eight possible neighbors are additive offsets in the same hash.
        ivec3 span = last - first;
        ivec3 originTiles = ivec3(origin.x / 16, (origin.y - originYOffset) / 16, origin.z / 16);
        int firstRegion = HashTileToRegion(first + originTiles);
        uint region = uint(PositiveModulo(int(shapeDataSSBO.selectedRegion) - firstRegion, reflectionActiveRegionCount));
        uint x = uint(span.x), y = uint(7 * span.y), z = uint(11 * span.z);
        const uint regions = uint(reflectionActiveRegionCount);
        return region == 0u || region == x % regions || region == y % regions || region == z % regions
            || region == (x + y) % regions || region == (x + z) % regions
            || region == (y + z) % regions || region == (x + y + z) % regions;
    }
#endif

#if WORLD_SPACE_SHAPES > 0
    #include "/lib/voxelization/reflectionShapeData.glsl"
#endif

#if defined SHADOW && defined VERTEX_SHADER
    #if WORLD_SPACE_SMOOTH_LIGHTING > 0
    void AppendReflectionCornerLighting(ivec3 cell, vec3 normal) {
        if (maxOf(abs(normal)) < 0.999) return;
        uint index = atomicAdd(blockDataSSBO.cornerCaptureCount, 1u);
        if (index >= reflectionCornerCaptureCapacity) return;
        uint word = uint(reflectionCornerCaptureBase) + 2u * index;
        blockDataSSBO.words[word] = uint(GetSceneVoxelIndex(cell)) | (uint(GetReflectionFaceIndex(normal)) << 24u);
        blockDataSSBO.words[word + 1u] = GetCapturedReflectionCornerLighting(normal);
    }
    #endif

    void UpdateLavaHeightMap() {
        if (!ReflectionStorageAvailable()) return;
        vec3 center = PlayerToSceneVoxel(ModelToScenePos(GetBlockCenterModelPos()));
        if (any(lessThan(center, vec3(0.0))) || any(greaterThanEqual(center, vec3(sceneVoxelVolumeSize)))) return;
        #if WORLD_SPACE_SHAPES > 0
            if (!IsReflectionCellSelected(ivec3(center))) return;
        #endif

        if (at_midBlock.y / 64.0 > 0.49) return;
        vec3 vertex = PlayerToSceneVoxel(ModelToScenePos(gl_Vertex.xyz));
        ivec3 corner = ivec3(round(vertex.x), floor(center.y), round(vertex.z));
        float height = clamp(vertex.y - floor(center.y), 0.0, 1.0);
        StoreLavaCorner(corner, height);
    }

    void UpdateSceneVoxelMap(int rawMat, vec3 normal, vec3 position) {
        if (!ReflectionStorageAvailable()) return;
        bool primaryVertex = (gl_VertexID & 3) == 0;
        int mat = GetReflectionMaterial(rawMat);

        vec3 scenePos = ModelToScenePos(GetBlockCenterModelPos());
        vec3 voxelPos = PlayerToSceneVoxel(scenePos);

        bool topOverlay = mat == 10669 || mat == 10845 || mat == 10925 || mat == 10953; // Wool Carpets, Moss Carpet, Snow Layers < 8
        bool doSolidBlockCheck = !IsReflectionCutoutCube(rawMat);
        if (topOverlay) {
            #include "/lib/voxelization/specificVoxelHandling/carpetHandling.glsl"
        }
        if (CheckInsideSceneVoxelVolume(voxelPos)) {
            #if WORLD_SPACE_SHAPES > 0
                if (!IsReflectionCellSelected(ivec3(voxelPos))) return;
            #endif
            bool storeToAllFaces = false;
            bool storeToAllFacesExceptTop = false;
            uint matM = mat > 10 ? uint(mat) : 1u;
            vec2 textureRad = abs(texCoord - mc_midTexCoord.xy);
            vec2 origin = mc_midTexCoord.xy - textureRad;
            float lavaTextureRotation = 0.0;
            bool grassSide = IsReflectionGrassSide(rawMat, normal);

            #include "/lib/voxelization/voxelHandling.glsl"

            if (doSolidBlockCheck) {
                if (
                    mat % 2 == 1 // Non-solids
                    || abs(mat - 5000) <= 4999 // Block entities that we treat as non-solid
                )
                return;
            }

            if (!primaryVertex) {
                #if WORLD_SPACE_SMOOTH_LIGHTING > 0
                    AppendReflectionCornerLighting(ivec3(voxelPos), normalize(normal));
                #endif
                return;
            }

            imageStore(wsr_img, GetSceneVoxelStoragePosition(ivec3(voxelPos)), uvec4(matM, 0u, 0u, 0u));
            imageStore(wsr_lod_img, GetSceneVoxelLodStoragePosition(ivec3(voxelPos) / 4), uvec4(1u, 0u, 0u, 0u));
            StoreReflectionCoarseOccupancy(ivec3(voxelPos));
            if (mat == 10068 && normal.y > 0.99)
                StoreLavaFaceData(ivec3(voxelPos), origin, textureRad.x, lavaTextureRotation);
            else {
                uint orientation = storeToAllFaces || storeToAllFacesExceptTop ? 0u
                                 : mat == 10068 ? GetDefaultReflectionFaceOrientation(round(normal))
                                 : GetReflectionFaceOrientation(round(normal), at_tangent);
                StoreFaceData(ivec3(voxelPos), round(normal), origin, textureRad.x, orientation,
                              storeToAllFaces, storeToAllFacesExceptTop, scenePos, grassSide);
            }
        }
    }

    #if WORLD_SPACE_PLAYER_REF == 1
        #include "/lib/voxelization/playerVoxelization.glsl"
    #endif
#endif
