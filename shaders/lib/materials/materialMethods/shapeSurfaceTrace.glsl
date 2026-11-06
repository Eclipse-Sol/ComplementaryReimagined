float intersectReflectionCapturedSurfaces(ivec3 cell, vec3 origin, vec3 rayDir, float maxDist, sampler2D atlas,
                                          vec3 positionGradX, vec3 positionGradY, vec3 gradientStepX, vec3 gradientStepY,
                                          out vec3 normal, out uint selected, out uint material) {
    selected = shapeSurfaceCapacity;
    material = 0u;
    uint next = getShapeSurfaceHead(cell);
    float nearest = maxDist + 1.0;
    uint tieBreak = 0xffffffffu, bestLight = 0u;
    for (int i = 0; i < 256 && next > 0u && next <= shapeSurfaceCapacity; i++) {
        uint index = next - 1u;
        shapeSurface surface = shapeDataSSBO.surfaces[index];
        next = getShapeNext(surface);
        if (isShapeBoundsRecord(surface.shading.w)) {
            vec3 lower = uintBitsToFloat(surface.shading.xyz), upper = uintBitsToFloat(surface.mapping.yzw);
            vec3 direction = mix(rayDir, vec3(1e-20), lessThan(abs(rayDir), vec3(1e-20)));
            vec3 t0 = (lower - origin) / direction, t1 = (upper - origin) / direction;
            vec3 nearT = min(t0, t1), farT = max(t0, t1);
            float entry = max(max(nearT.x, nearT.y), nearT.z);
            float exit = min(min(farT.x, farT.y), farT.z);
            if (exit < max(0.0, entry) || entry > maxDist + 0.001) next = surface.shading.w & shapeHeadPointerMask;
            i--;
            continue;
        }
        if (!isShapeResolvedPlane(surface.shading.w)) continue;
        uint basis = surface.mapping.z;
        uint codeU = basis & 63u, codeV = (basis >> 6u) & 63u;
        uint face = getShapeFaceCode(surface.shading.w), normalAxis = face >> 1u;
        if (isShapeAxisBasis(codeU, codeV, normalAxis)) {
            float normalSign = getShapeCodeSign(face);
            float denominator = rayDir[normalAxis] * normalSign;
            if (denominator >= -1e-7) continue;
            ivec3 owner = getShapeSurfaceOwner(surface, cell);
            vec3 anchor = getShapeSurfaceAnchor(surface) + vec3(owner);
            float plane = anchor[normalAxis];
            float distance = -((origin[normalAxis] - plane) * normalSign) / denominator;
            if (distance < -0.0001 || distance > maxDist || distance > nearest + 0.00001) continue;
            uint light = (surface.shading.y >> 16u) & 4095u;
            if (abs(distance - nearest) <= 0.00001 && (light < bestLight || light == bestLight && surface.shading.x >= tieBreak)) continue;
            uint uAxis = codeU >> 1u, vAxis = codeV >> 1u;
            vec2 signs = vec2(getShapeCodeSign(codeU), getShapeCodeSign(codeV));
            vec2 cornerSign = getShapePlaneCornerSign(basis);
            vec2 offset = ((vec2(origin[uAxis], origin[vAxis]) - vec2(anchor[uAxis], anchor[vAxis]))
                         + max(0.0, distance) * vec2(rayDir[uAxis], rayDir[vAxis])) * signs;
            vec2 size = getShapePlaneSize(surface);
            vec2 within = offset * cornerSign;
            if (any(lessThan(within, vec2(-0.0001))) || any(greaterThan(within, size + 0.0001))) continue;
            vec3 gx = positionGradX + max(0.0, distance) * gradientStepX;
            vec3 gy = positionGradY + max(0.0, distance) * gradientStepY;
            vec2 faceRay = vec2(rayDir[uAxis], rayDir[vAxis]) / min(denominator, -1e-6);
            vec2 scale = unpackHalf2x16(surface.mapping.w);
            vec2 uv = getShapeRawUV(surface.shading.x) / 65536.0 + scale * offset;
            vec2 dx = (vec2(gx[uAxis], gx[vAxis]) - faceRay * (gx[normalAxis] * normalSign)) * signs * scale;
            vec2 dy = (vec2(gy[uAxis], gy[vAxis]) - faceRay * (gy[normalAxis] * normalSign)) * signs * scale;
            if (textureGrad(atlas, uv, dx, dy).a <= 0.5) continue;
            nearest = max(0.0, distance);
            tieBreak = surface.shading.x;
            bestLight = light;
            normal = vec3(0.0);
            normal[normalAxis] = normalSign;
            selected = index;
            material = (surface.shading.y & 2047u) + 20002u;
            continue;
        }
        vec3 axisU, axisV, faceNormal;
        getShapePlaneBasis(surface.shading.w, codeU, codeV, axisU, axisV, faceNormal);
        float denominator = dot(faceNormal, rayDir);
        if (denominator >= -1e-7) continue;
        vec3 anchor = getShapeSurfaceAnchor(surface) + vec3(getShapeSurfaceOwner(surface, cell));
        vec3 fromAnchor = origin - anchor;
        float distance = -dot(fromAnchor, faceNormal) / denominator;
        if (distance < -0.0001 || distance > maxDist || distance > nearest + 0.00001) continue;
        uint light = (surface.shading.y >> 16u) & 4095u;
        if (abs(distance - nearest) <= 0.00001 && (light < bestLight || light == bestLight && surface.shading.x >= tieBreak)) continue;
        vec3 delta = fromAnchor + max(0.0, distance) * rayDir;
        vec2 offset = vec2(dot(delta, axisU), dot(delta, axisV));
        vec2 size = getShapePlaneSize(surface);
        vec2 cornerSign = getShapePlaneCornerSign(surface.mapping.z);
        vec2 within = offset * cornerSign;
        if (any(lessThan(within, vec2(-0.0001))) || any(greaterThan(within, size + 0.0001))) continue;
        if (!reflectionSurfaceHasAlpha(surface, offset, axisU, axisV, faceNormal, rayDir, denominator, distance, atlas,
                                       positionGradX, positionGradY, gradientStepX, gradientStepY)) continue;
        nearest = max(0.0, distance);
        tieBreak = surface.shading.x;
        bestLight = light;
        normal = faceNormal;
        selected = index;
        material = (surface.shading.y & 2047u) + 20002u;
    }
    return selected < shapeSurfaceCapacity ? nearest : -1.0;
}
