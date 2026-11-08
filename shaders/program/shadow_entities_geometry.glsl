#include "/lib/common.glsl"

layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

in vec2 playerShadowTexCoord[];
in vec4 playerShadowPosition[];
flat in int playerShadowVertexID[];
flat in vec4 playerShadowColor[];
flat in int playerShadowMaterial[];

out vec2 texCoord;
out vec4 position;
flat out vec4 glColor;
flat out int mat;

#ifdef CONNECTED_GLASS_EFFECT
    in vec2 playerShadowSignMidCoordPos[];
    flat in vec2 playerShadowAbsMidCoordPos[];
    out vec2 signMidCoordPos;
    flat out vec2 absMidCoordPos;
#endif

#ifdef WSR_PLAYER_EQUIPMENT
    #define SSBO_QUALIFIER
    #include "/lib/voxelization/SSBOs/playerVerticesBuffer.glsl"
    #include "/lib/voxelization/playerEquipmentCapture.glsl"
#endif

void main() {
    #ifdef WSR_PLAYER_EQUIPMENT
        capturePlayerEquipment();
    #endif

    for (int i = 0; i < 3; i++) {
        gl_Position = gl_in[i].gl_Position;
        texCoord = playerShadowTexCoord[i];
        position = playerShadowPosition[i];
        glColor = playerShadowColor[i];
        mat = playerShadowMaterial[i];
        #ifdef CONNECTED_GLASS_EFFECT
            signMidCoordPos = playerShadowSignMidCoordPos[i];
            absMidCoordPos = playerShadowAbsMidCoordPos[i];
        #endif
        EmitVertex();
    }
    EndPrimitive();
}
