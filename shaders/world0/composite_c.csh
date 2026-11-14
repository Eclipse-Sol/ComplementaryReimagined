#version 430 compatibility

#define COMPUTE_SHADER
#define FRAGMENT_SHADER
#define WSR_ATLAS_BAKE
#define COMPOSITE
#define OVERWORLD
#define gl_FragCoord vec4(wsrAtlasBakePixel+vec2(0.5),0.0,1.0)
#define dFdx(value) ((value)*0.0)
#define dFdy(value) ((value)*0.0)
vec2 wsrAtlasBakePixel = vec2(0.0);
#include "/program/composite.glsl"
