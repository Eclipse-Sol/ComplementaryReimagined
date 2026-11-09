#extension GL_ARB_shader_storage_buffer_object : enable
#extension GL_ARB_shader_image_load_store : enable

#ifndef CELESTIAL_BUFFER_QUALIFIER
    #define CELESTIAL_BUFFER_QUALIFIER readonly
#endif

layout(std430, binding = 1) CELESTIAL_BUFFER_QUALIFIER buffer celestialQuadBuffer {
    vec4 corners[8];
    vec2 texCoords[8];
    vec4 colors[2];
    int frames[2];
} celestialQuads;
