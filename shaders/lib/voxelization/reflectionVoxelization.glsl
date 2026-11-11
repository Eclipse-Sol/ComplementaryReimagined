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
    bool IsReflectionTerrainStage() {
        return renderStage == MC_RENDER_STAGE_TERRAIN_SOLID
            || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
            || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED;
    }

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
    void UpdateLavaHeightMap() {
        if (!ReflectionStorageAvailable()) return;
        #if WORLD_SPACE_SHAPES > 0
            if (blockDataSSBO.lavaRefreshFrame != uint(frameCounter + 1)) return;
        #endif
        vec3 center = PlayerToSceneVoxel(ModelToScenePos(GetBlockCenterModelPos()));
        if (any(lessThan(center, vec3(0.0))) || any(greaterThanEqual(center, vec3(sceneVoxelVolumeSize)))) return;

        if (at_midBlock.y / 64.0 > 0.49) return;
        vec3 vertex = PlayerToSceneVoxel(ModelToScenePos(gl_Vertex.xyz));
        ivec3 corner = ivec3(round(vertex.x), floor(center.y), round(vertex.z));
        float height = clamp(vertex.y - floor(center.y), 0.0, 1.0);
        StoreLavaCorner(corner, height);
    }

    void UpdateSceneVoxelMap(int rawMat, vec3 normal, vec3 position) {
        if (!ReflectionStorageAvailable()) return;
        int mat = GetReflectionMaterial(rawMat);

        vec3 scenePos = ModelToScenePos(GetBlockCenterModelPos());
        vec3 voxelPos = PlayerToSceneVoxel(scenePos);

        bool topOverlay = mat == 10669 || mat == 10845 || mat == 10925 || mat == 10953; // Wool Carpets, Moss Carpet, Snow Layers < 8
        if (topOverlay) {
            if (normal.y <= 0.5) return;
            voxelPos.y -= 1.0;
        }
        if (CheckInsideSceneVoxelVolume(voxelPos)) {
            #if WORLD_SPACE_SHAPES > 0
                if (!IsReflectionCellSelected(ivec3(voxelPos))) return;
            #endif
            bool doSolidBlockCheck = !topOverlay;
            bool storeToAllFaces = false;
            bool storeToAllFacesExceptTop = false;
            uint matM = mat > 10 ? uint(mat) : 1u;
            vec2 textureRad = abs(texCoord - mc_midTexCoord.xy);
            vec2 origin = mc_midTexCoord.xy - textureRad;
            float lavaTextureRotation = 0.0;

            if (mat == 10132) { // Grass Block Regular
                if (texture2D(tex, mc_midTexCoord.xy).a < 0.5) return; // Grass Block Side Overlay
            }

            if (mat == 10009 || mat == 10011 || IsReflectionCutoutCube(rawMat)) { // Leaves and cutout cubes
                doSolidBlockCheck = false;
            }

            if (mat == 10113) { // Mangrove roots
                // Block is super slow in WSR, remove internal quads!
                vec3 local = PlayerToSceneVoxel(position) - floor(voxelPos);
                if (dot(local - 0.5, normal) < 0.49) return;
                doSolidBlockCheck = false;
            }

            if (mat == 10129 // Farmland:Dry
                || mat == 10137 // Farmland:Wet
                || mat == 10493 // Dirt Path
            ) {
                doSolidBlockCheck = false;
                textureRad *= 0.5;
                origin.y += 2.0 / atlasSize.y;
            }

            if (mat == 10068) { // Lava
                vec3 vertexPos = PlayerToSceneVoxel(ModelToScenePos(gl_Vertex.xyz));
                if (abs(normal.y) > 0.1) {
                    normal = vec3(0.0, sign(normal.y), 0.0);
                    // Flow rotates the top UVs...
                    textureRad.x = length(textureRad * vec2(atlasSize)) * 0.70710678 / atlasSize.x;
                    textureRad.y = textureRad.x * atlasSize.x / atlasSize.y;
                    origin = mc_midTexCoord.xy - textureRad;
                    if (normal.y > 0.0) {
                        vec2 corner = 0.5 - (vertexPos.xz - floor(voxelPos.xz));
                        vec2 uvCorner = (texCoord - mc_midTexCoord.xy) * vec2(atlasSize);
                        lavaTextureRotation = atan(corner.x * uvCorner.y - corner.y * uvCorner.x, dot(corner, uvCorner));
                    }
                } else {
                    float height = vertexPos.y - floor(voxelPos.y);
                    origin.y = texCoord.y - 2.0 * textureRad.x * atlasSize.x / atlasSize.y * (1.0 - height);
                }
            }

            // Half blocks that we want to display as full blocks in reflections
            if (mat == 10035 // Stone Bricks, Mossy Stone Bricks
                || abs(mat - 10095) <= 12 && mat % 4 == 3 // Stone, Smooth Stone, Granite, Diorite, Andesite, Bricks, Mud Bricks
                || mat == 10155 // Cobblestone, Mossy Cobblestone
                || abs(mat - 10191) <= 32 && mat % 8 == 7 // Oak, Spruce, Birch, Jungle, Acacia, DarkOak, Mangrove, Crimson, Warped
                || mat == 10111 // Cobbled Deepslate
                || mat == 10115 // Polished Deepslate, Deepslate Bricks, Deepslate Tiles
                || mat == 10243 // Sandstone
                || mat == 10247 // Red Sandstone
                || mat == 10295 // Copper
                || mat == 10367 // Quartz
                || mat == 10379 // Purpur
                || mat == 10381 // Powder Snow
                || mat == 10419 // Nether Bricks
                || mat == 10423 // Red Nether Bricks
                || mat == 10431 // End Stone Bricks
                || mat == 10443 // Prismarine, Prismarine Bricks
                || mat == 10447 // Dark Prismarine
                || mat == 10483 // Blackstone
                || mat == 10715 // Tuff
                || mat == 10759 // Bamboo, Bamboo Mosaic
                || mat == 10763 // Cherry
                || mat == 10931 // Pale Oak
            ) {
                if (textureRad.y < 5.0 / atlasSize.y) {
                    // Discarding if textureRad is too small to fix (somewhat rare) flickering on stairs
                    if (textureRad.x < 5.0 / atlasSize.x) return;

                    // Half textureRad for stairs and slabs to not overshoot their textures
                    textureRad *= 0.5;

                    // P.S: Don't ask me how any of these checks make sense because I have absolutely no idea either
                }

                doSolidBlockCheck = false;
                if (normal.y < 0.5) storeToAllFacesExceptTop = true; // Not overriding top face or else carpets look broken on top of slabs
            }


            if (mat == 10072 // Fire
                || mat == 10076 // Soul Fire
                || mat == 10332 // Amethyst Clusters
                || mat == 10544 // Glow Lichen
            ) {
                doSolidBlockCheck = false;
                storeToAllFaces = true;
            }

            if (mat == 10652 || mat == 10656) { // Campfire:Lit, Soul Campfire:Lit
                if (abs(abs(normal.x) - 0.5) < 0.25) {
                    doSolidBlockCheck = false;
                    storeToAllFaces = true;
                } else return;
            }

            // Blocks to remove from reflections
            if (mat == 10056 // Lava Cauldron
                || mat == 10404 // Sea Pickle
                || mat == 10496 // Torch
                || mat == 10500 // End Rod
                || mat == 10508 // Chorus Flower:Alive
                || mat == 10512 // Chorus Flower:Dead
                || mat == 10528 // Soul Torch
                || mat == 10556 // End Portal Frame:Active
                || mat == 10572 // Dragon Egg
                || mat == 10604 || mat == 10605 // Redstone Torch
                || mat == 10632 // Cave Vines
                || mat == 10644 // Powered Repeater, Powered Comparator
                || mat == 10776 // Crimson Fungus, Warped Fungus
                || mat == 10780 // Potted Crimson Fungus, Potted Warped Fungus
                || mat == 10836 // Brewing Stand
                || mat == 10884 // Weeping Vines
                || mat == 10972 // Firefly Bush
                || mat == 10976 // Open Eyeblossom
                || mat == 10980 // Potted Open Eyeblossom
                || abs(mat - 10562) <= 2 // Lantern & Soul Lantern
                || abs(mat - 10599) <= 3 // Redstone Wire
                || abs(mat - 10701) <= 3 // Non-Solid Sculk Stuff
                || abs(mat - 10786) <= 2 // Calibrated Sculk Sensor
                || abs(mat - 10911) <= 11 // Lit Candles & Candle Cakes
                || mat == 10984 // Copper Torch
                || mat == 10988 // Copper Lantern
            ) {
                return;
            }

            if (doSolidBlockCheck) {
                if (
                    mat % 2 == 1 // Non-solids
                    || abs(mat - 5000) <= 4999 // Block entities that we treat as non-solid
                )
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
                              storeToAllFaces, storeToAllFacesExceptTop, scenePos);
            }
        }
    }

    #if WORLD_SPACE_PLAYER_REF == 1
        #include "/lib/voxelization/playerVoxelization.glsl"
    #endif
#endif
