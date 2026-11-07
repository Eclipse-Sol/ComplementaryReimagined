// Jitter offset from Chocapic13
vec2 jitterOffsets[8] = vec2[8](
    vec2( 0.125,-0.375),
    vec2(-0.125, 0.375),
    vec2( 0.625, 0.125),
    vec2( 0.375,-0.625),
    vec2(-0.625, 0.625),
    vec2(-0.875,-0.125),
    vec2( 0.375,-0.875),
    vec2( 0.875, 0.875)
);

vec2 TAAJitter(vec2 coord, float w, int frameIndex) {
    #if TAA_JITTER > 0
        vec2 offset = jitterOffsets[frameIndex] * (w / vec2(viewWidth, viewHeight));
        #if TAA_JITTER == 1
            offset *= 0.125;
        #elif TAA_JITTER == 2
            offset *= 0.33;
        #endif
        return coord + offset;
    #else
        return coord;
    #endif
}

vec2 TAAJitter(vec2 coord, float w) {
    return TAAJitter(coord, w, int(framemod8));
}
