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
        #ifdef WSR_PLAYER_EQUIPMENT
            // Iris 26.x patches this ID to per-vertex iris_Entity.z, not
            // a batched draw uniform.
            if (currentRenderedItemId > 0) return;
        #endif

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
