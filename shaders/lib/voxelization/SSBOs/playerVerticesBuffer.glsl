#extension GL_ARB_shader_storage_buffer_object : enable

#ifdef WSR_PLAYER_EQUIPMENT
    #include "/lib/voxelization/playerEquipmentSettings.glsl"
    struct playerEquipmentTriangle {
        vec4 barycentricU;
        vec4 barycentricV;
        uvec4 tileUVs;
        uvec4 vertexColors;
    };
#endif

layout(std430, binding = 3) SSBO_QUALIFIER buffer playerVerticesBuffer {
	vec3 vertexPositions[216];
    vec2 vertexData[216];
	ivec3 headMin, headMax;
	ivec3 torsoMin, torsoMax;
	ivec3 leftLegMin, leftLegMax;
	ivec3 rightLegMin, rightLegMax;
	ivec3 leftHandMin, leftHandMax;
	ivec3 rightHandMin, rightHandMax;
    #ifdef WSR_PLAYER_EQUIPMENT
        uint equipmentPadding;
        uint equipmentCount;
        uint equipmentOverflow;
        ivec4 equipmentGroupMin[PLAYER_EQUIPMENT_GROUP_COUNT];
        ivec4 equipmentGroupMax[PLAYER_EQUIPMENT_GROUP_COUNT];
        vec4 equipmentPlanes[PLAYER_EQUIPMENT_CAPACITY];
        playerEquipmentTriangle equipmentTriangles[PLAYER_EQUIPMENT_CAPACITY];
        ivec4 equipmentMin, equipmentMax;
        ivec4 playerMin, playerMax;
    #endif
} playerVerticesSSBO;
