#version 430 compatibility

#define COMPUTE_SHADER
#define FRAGMENT_SHADER
#define WSR_TRACE_PREPASS
#define WSR_LDS_GRADIENTS
#define gl_FragCoord vec4(vec2(gl_GlobalInvocationID.xy)+vec2(0.5),0.0,1.0)
#define END
#define COMPOSITE

#include "/program/composite.glsl"
