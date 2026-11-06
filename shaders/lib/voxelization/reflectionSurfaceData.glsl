uint getShapeSurfaceHead(ivec3 cell) {
    return readShapeHead(getSceneVoxelIndex(cell));
}

ivec3 getShapeSurfaceOwner(shapeSurface surface, ivec3 cell) {
    if ((surface.shading.w & shapeFlagCompactLink) != 0u) return cell;
    return getShapeVoxelPosition(surface.shading.w & shapeVoxelIndexMask);
}

void getShapePlaneBasis(uint flags, uint codeU, uint codeV, out vec3 axisU, out vec3 axisV, out vec3 normal) {
    if (isShapeTiltedBasis(codeU, codeV)) {
        axisU = getShapeDiagonalVector(int(codeU));
        axisV = vec3(0.0, getShapeCodeSign(codeV), 0.0);
        normal = vec3(-axisU.z * axisV.y, 0.0, axisU.x * axisV.y);
        if ((flags & shapeFlagTiltedFlip) != 0u) normal = -normal;
    } else {
        uint face = getShapeFaceCode(flags);
        axisU = getShapePlaneVector(int(codeU));
        axisV = getShapePlaneVector(int(codeV));
        normal = normalize(cross(axisU, axisV));
        if (normal[face >> 1u] * getShapeCodeSign(face) < 0.0) normal = -normal;
    }
}

bool reflectionSurfaceHasAlpha(shapeSurface surface, vec2 offset, vec3 u, vec3 v, vec3 normal,
                               vec3 rayDir, float denominator, float distance, sampler2D atlas,
                               vec3 positionGradX, vec3 positionGradY, vec3 gradientStepX, vec3 gradientStepY) {
    vec2 anchorUV = getShapeRawUV(surface.shading.x) / 65536.0;
    vec2 scale = unpackHalf2x16(surface.mapping.w);
    vec2 uv = anchorUV + scale * offset;
    vec3 gradX = positionGradX + max(0.0, distance) * gradientStepX;
    vec3 gradY = positionGradY + max(0.0, distance) * gradientStepY;
    vec3 faceRayDir = rayDir / min(denominator, -1e-6);
    gradX -= faceRayDir * dot(normal, gradX);
    gradY -= faceRayDir * dot(normal, gradY);
    vec2 texGradX = scale * vec2(dot(gradX, u), dot(gradX, v));
    vec2 texGradY = scale * vec2(dot(gradY, u), dot(gradY, v));
    return textureGrad(atlas, uv, texGradX, texGradY).a > 0.5;
}
