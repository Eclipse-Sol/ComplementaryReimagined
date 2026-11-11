uint GetShapeRecordHead(reflectionCellHandle cell) {
    return ReadShapeHead(cell);
}

ivec3 GetShapeOwnerCell(shapeRecord surface, ivec3 cell, ivec3 storageOrigin) {
    if ((surface.shading.w & shapeFlagCompactLink) != 0u) return cell;
    ivec3 owner = GetSceneVoxelPosition(surface.shading.w & shapeVoxelIndexMask, storageOrigin);
    ivec3 delta = owner - cell;
    owner -= ivec3(greaterThan(delta, sceneVoxelVolumeSize / 2)) * sceneVoxelVolumeSize;
    owner += ivec3(lessThan(delta, -sceneVoxelVolumeSize / 2)) * sceneVoxelVolumeSize;
    return owner;
}

void GetShapePlaneBasis(uint flags, uint codeU, uint codeV, out vec3 axisU, out vec3 axisV, out vec3 normal) {
    if (IsShapeTiltedBasis(codeU, codeV)) {
        axisU = GetShapeDiagonalVector(int(codeU));
        axisV = vec3(0.0, GetShapeCodeSign(codeV), 0.0);
        normal = vec3(-axisU.z * axisV.y, 0.0, axisU.x * axisV.y);
        if ((flags & shapeFlagTiltedFlip) != 0u) normal = -normal;
    } else {
        uint face = GetShapeFaceCode(flags);
        axisU = GetShapePlaneVector(int(codeU));
        axisV = GetShapePlaneVector(int(codeV));
        normal = normalize(cross(axisU, axisV));
        if (normal[face >> 1u] * GetShapeCodeSign(face) < 0.0) normal = -normal;
    }
}

bool ReflectionSurfaceHasAlpha(shapeRecord surface, vec2 offset, vec3 u, vec3 v, vec3 normal,
                               vec3 rayDir, float denominator, float distance, sampler2D atlas,
                               vec3 positionGradX, vec3 positionGradY, vec3 gradientStepX, vec3 gradientStepY) {
    vec2 anchorUV = GetShapeRawUV(surface.shading.x) / 65536.0;
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
