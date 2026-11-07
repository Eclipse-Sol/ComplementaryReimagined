#include "/lib/voxelization/reflectionVoxelVolume.glsl"

vec3 playerToSceneVoxel(vec3 playerPos) {
    return playerPos + cameraPositionBestFract + 0.5 * vec3(sceneVoxelVolumeSize);
}

vec3 playerToPreviousSceneVoxel(vec3 previousPlayerPos) {
    return previousPlayerPos + previousCameraPositionBestFract + 0.5 * vec3(sceneVoxelVolumeSize);
}

bool CheckInsideSceneVoxelVolume(vec3 voxelPos) {
    voxelPos /= vec3(sceneVoxelVolumeSize);
    return clamp01(voxelPos) == voxelPos;
}

bool CheckInsideLodVoxelVolume(vec3 voxelPos) {
    voxelPos /= vec3(sceneVoxelVolumeSize / 4);
    return clamp01(voxelPos) == voxelPos;
}

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_SCATTER
    void StoreReflectionCoarseOccupancy(ivec3 cell) {
        ivec3 lower = max(cell - 1, ivec3(0)) / 16;
        ivec3 upper = min(cell + 1, sceneVoxelVolumeSize - 1) / 16;
        for (int z = lower.z; z <= upper.z; z++)
            for (int y = lower.y; y <= upper.y; y++)
                for (int x = lower.x; x <= upper.x; x++)
                    imageStore(wsr_coarse_img, ivec3(x, y, z), uvec4(1u, 0u, 0u, 0u));
    }
#endif

#if defined SHADOW && defined VERTEX_SHADER
    bool isReflectionTerrainStage() {
        return renderStage == MC_RENDER_STAGE_TERRAIN_SOLID
            || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
            || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED;
    }

    vec3 modelToScenePos(vec3 modelPos) {
        vec3 viewPos = mat3(gl_ModelViewMatrix) * modelPos + gl_ModelViewMatrix[3].xyz;
        return mat3(shadowModelViewInverse) * viewPos + shadowModelViewInverse[3].xyz;
    }

    vec3 getBlockCenterModelPos() {
        return gl_Vertex.xyz + at_midBlock.xyz / 64.0;
    }
#endif

#include "/lib/voxelization/reflectionVoxelData.glsl"

#if WORLD_SPACE_SHAPES > 0
    #include "/lib/voxelization/reflectionShapeData.glsl"
#endif

#if defined SHADOW && defined VERTEX_SHADER
    void UpdateLavaHeightMap() {
        vec3 center = playerToSceneVoxel(modelToScenePos(getBlockCenterModelPos()));
        if (any(lessThan(center, vec3(0.0))) || any(greaterThanEqual(center, vec3(sceneVoxelVolumeSize)))) return;

        if (at_midBlock.y / 64.0 > 0.49) return;
        vec3 vertex = playerToSceneVoxel(modelToScenePos(gl_Vertex.xyz));
        ivec3 corner = ivec3(round(vertex.x), floor(center.y), round(vertex.z));
        float height = clamp(vertex.y - floor(center.y), 0.0, 1.0);
        storeLavaCorner(corner, height);
    }

    void UpdateSceneVoxelMap(int rawMat, vec3 normal, vec3 position) {
        int mat = getReflectionMaterial(rawMat);

        vec3 scenePos = modelToScenePos(getBlockCenterModelPos());
        vec3 voxelPos = playerToSceneVoxel(scenePos);

        if (CheckInsideSceneVoxelVolume(voxelPos)) {
            bool doSolidBlockCheck = true;
            bool storeToAllFaces = false;
            bool storeToAllFacesExceptTop = false;
            uint matM = mat > 10 ? uint(mat) : 1u;
            vec2 textureRad = abs(texCoord - mc_midTexCoord.xy);
            vec2 origin = mc_midTexCoord.xy - textureRad;
            float lavaTextureRotation = 0.0;

            if (mat == 10132) { // Grass Block Regular
                if (texture2D(tex, mc_midTexCoord.xy).a < 0.5) return; // Grass Block Side Overlay
            }

            if (mat == 10009 || mat == 10011 || isReflectionCutoutCube(rawMat)) { // Leaves and cutout cubes
                doSolidBlockCheck = false;
            }

            if (mat == 10113) { // Mangrove roots
                // Block is super slow in WSR, remove internal quads!
                vec3 local = playerToSceneVoxel(position) - floor(voxelPos);
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
                vec3 vertexPos = playerToSceneVoxel(modelToScenePos(gl_Vertex.xyz));
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

            if (mat == 10669 || mat == 10845 || mat == 10925 || mat == 10953) { // Wool Carpets, Moss Carpet, Snow Layers < 8
                if (normal.y > 0.5) {
                    voxelPos.y -= 1.0;
                    doSolidBlockCheck = false;
                } else return;
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

            imageStore(wsr_img, ivec3(voxelPos), uvec4(matM, 0u, 0u, 0u));
            imageStore(wsr_lod_img, ivec3(voxelPos) / 4, uvec4(1u, 0u, 0u, 0u));
            StoreReflectionCoarseOccupancy(ivec3(voxelPos));
            if (mat == 10068 && normal.y > 0.99)
                storeLavaFaceData(ivec3(voxelPos), origin, textureRad.x, lavaTextureRotation);
            else {
                uint orientation = storeToAllFaces || storeToAllFacesExceptTop ? 0u
                                 : mat == 10068 ? getDefaultReflectionFaceOrientation(round(normal))
                                 : getReflectionFaceOrientation(round(normal), at_tangent);
                storeFaceData(ivec3(voxelPos), round(normal), origin, textureRad.x, orientation, storeToAllFaces, storeToAllFacesExceptTop, scenePos);
            }
        }
    }

    #if WORLD_SPACE_PLAYER_REF == 1
        uniform writeonly image2D playerAtlas_img;

        #define updateAABB(aabb_min, aabb_max, pos) \
                      atomicMin(aabb_min.x, pos.x); \
                      atomicMin(aabb_min.y, pos.y); \
                      atomicMin(aabb_min.z, pos.z); \
                      atomicMax(aabb_max.x, pos.x); \
                      atomicMax(aabb_max.y, pos.y); \
                      atomicMax(aabb_max.z, pos.z);


        void UpdatePlayerVertexList(vec3 position) {
            int localVertexID = gl_VertexID % 288;
            // This fixes the whole system being broken on MC 26.2 and above due to the batching system.
            // Don't ask me how it even works, I don't know either. I just tried doing modulo by player vertex count

            if (entityId == 50017 && textureSize(tex, 0) == ivec2(64)) { // Current Player

                // The atlas takes 4 frames to fully generate, reload every 600 frames
                if (framemod600 > 5 && framemod600 <= 9 && localVertexID < 256) {
                    int i = localVertexID * 4 + int(framemod4) * 1024;
                    for (int j = 0; j < 4; j++) {
                        ivec2 coord = ivec2((i + j) % 64, (i + j) / 64);
                        imageStore(playerAtlas_img, coord, texelFetch(tex, coord, 0));
                    }
                }

                position -= 0.2 * playerLookVector;

                ivec3 aabbPos = ivec3(position * 1000.0);

                if (localVertexID < 48) { // Head
                    updateAABB(playerVerticesSSBO.headMin, playerVerticesSSBO.headMax, aabbPos);
                } else if (localVertexID < 96) { // Right Hand
                    updateAABB(playerVerticesSSBO.rightHandMin, playerVerticesSSBO.rightHandMax, aabbPos);
                } else if (localVertexID < 144) { // Left Leg
                    updateAABB(playerVerticesSSBO.leftLegMin, playerVerticesSSBO.leftLegMax, aabbPos);
                } else if (localVertexID < 192) { // Left Hand
                    updateAABB(playerVerticesSSBO.leftHandMin, playerVerticesSSBO.leftHandMax, aabbPos);
                } else if (localVertexID < 240) { // Right leg
                    updateAABB(playerVerticesSSBO.rightLegMin, playerVerticesSSBO.rightLegMax, aabbPos);
                } else { // Torso
                    updateAABB(playerVerticesSSBO.torsoMin, playerVerticesSSBO.torsoMax, aabbPos);
                }

                if (localVertexID % 4 != 3) {
                    int ssboIndex = localVertexID - localVertexID / 4;
                    playerVerticesSSBO.vertexPositions[ssboIndex] = position;
                    playerVerticesSSBO.vertexData[ssboIndex] = texCoord;
                }
            }
        }
    #endif
#endif
