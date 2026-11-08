#define SSBO_QUALIFIER

#include "/lib/voxelization/SSBOs/playerVerticesBuffer.glsl"

void clearSSBOs() {
    if (gl_FragCoord.x + gl_FragCoord.y < 1.5) {
        playerVerticesSSBO.headMin = ivec3(1e6);
        playerVerticesSSBO.headMax = ivec3(-1e6);
        playerVerticesSSBO.torsoMin = ivec3(1e6);
        playerVerticesSSBO.torsoMax = ivec3(-1e6);
        playerVerticesSSBO.leftLegMin = ivec3(1e6);
        playerVerticesSSBO.leftLegMax = ivec3(-1e6);
        playerVerticesSSBO.rightLegMin = ivec3(1e6);
        playerVerticesSSBO.rightLegMax = ivec3(-1e6);
        playerVerticesSSBO.leftHandMin = ivec3(1e6);
        playerVerticesSSBO.leftHandMax = ivec3(-1e6);
        playerVerticesSSBO.rightHandMin = ivec3(1e6);
        playerVerticesSSBO.rightHandMax = ivec3(-1e6);
        #ifdef WSR_PLAYER_EQUIPMENT
            playerVerticesSSBO.equipmentCount = 0u;
            playerVerticesSSBO.equipmentOverflow = 0u;
            playerVerticesSSBO.playerMin = ivec4(1000000);
            playerVerticesSSBO.playerMax = ivec4(-1000000);
            playerVerticesSSBO.equipmentMin = ivec4(1000000);
            playerVerticesSSBO.equipmentMax = ivec4(-1000000);
            for (int group = 0; group < PLAYER_EQUIPMENT_GROUP_COUNT; group++) {
                playerVerticesSSBO.equipmentGroupMin[group] = ivec4(1000000);
                playerVerticesSSBO.equipmentGroupMax[group] = ivec4(-1000000);
            }
        #endif
    }
}
