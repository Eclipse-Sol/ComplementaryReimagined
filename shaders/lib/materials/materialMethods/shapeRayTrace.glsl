#include "/lib/materials/materialMethods/sharedShapeModels.glsl"

bool GetReflectionShapeBox(int family, int model, uint state, int part, out vec3 boxMin, out vec3 boxMax) {
    if (family >= WSR_FAMILY_FIRST_MODEL) return GetModelTableShapeBox(family, model, state, part, boxMin, boxMax);
    if (family >= WSR_FAMILY_FIRST_BOX) {
        if (family == WSR_FAMILY_LAYERED || family == WSR_FAMILY_PRESSURE_PLATE) {
            float height = float(state & 63u) / 32.0;
            float inset = family == WSR_FAMILY_PRESSURE_PLATE ? 0.0625 : 0.0;
            boxMin = vec3(inset, 0.0, inset);
            boxMax = vec3(1.0 - inset, height, 1.0 - inset);
            return height > 0.0;
        }
        if (family == WSR_FAMILY_DOOR_TRAPDOOR) {
            boxMin = vec3(0.0);
            boxMax = vec3(1.0);
            for (int axis = 0; axis < 3; axis++) {
                uint edges = (state >> uint(2 * axis)) & 3u;
                if (edges == 1u) {
                    boxMax[axis] = 0.1875;
                    return true;
                }
                if (edges == 2u) {
                    boxMin[axis] = 0.8125;
                    return true;
                }
            }
            return false;
        }
        if (family == WSR_FAMILY_BUTTON) {
            vec3 halfSize = vec3(0.125);
            for (int axis = 0; axis < 3; axis++)
                if ((state & (1u << uint(axis + 6))) != 0u) halfSize[axis] = 0.1875;
            boxMin = 0.5 - halfSize;
            boxMax = 0.5 + halfSize;
            float depth = (state & 512u) != 0u ? 0.125 : 0.06375;
            for (int axis = 0; axis < 3; axis++) {
                uint edges = (state >> uint(2 * axis)) & 3u;
                if (edges == 1u) {
                    boxMin[axis] = 0.0;
                    boxMax[axis] = depth;
                    return true;
                }
                if (edges == 2u) {
                    boxMin[axis] = 1.0 - depth;
                    boxMax[axis] = 1.0;
                    return true;
                }
            }
        }
        return false;
    }
    if (family == WSR_FAMILY_SLAB_STAIR) {
        uint front = state & 15u, back = (state >> 4u) & 15u;
        bool joinZ = front == back;
        if (joinZ && part >= 2) return false;
        uint row = part < 2 ? front : back;
        bool joinX = (row & 5u) == ((row >> 1u) & 5u);
        if (joinX && (part & 1) != 0) return false;
        uint column = (row >> uint(part & 1)) & 5u;
        if (column == 0u) return false;
        boxMin = vec3(0.5 * float(part & 1), (column & 1u) != 0u ? 0.0 : 0.5, 0.5 * float(part >> 1));
        boxMax = vec3(boxMin.x + (joinX ? 1.0 : 0.5), (column & 4u) != 0u ? 1.0 : 0.5,
                      boxMin.z + (joinZ ? 1.0 : 0.5));
        return true;
    }
    if (family == WSR_FAMILY_FENCE) {
        if (part == 0) {
            boxMin = vec3(0.375, 0.0, 0.375);
            boxMax = vec3(0.625, 1.0, 0.625);
            return true;
        }
        int connection = (part - 1) / 2;
        int axis = connection < 2 ? 0 : 2;
        int face = connection < 2 ? connection : connection + 2;
        if ((state & (1u << uint(face))) == 0u) return false;
        float bottom = (part - 1) % 2 == 0 ? 0.375 : 0.75;
        boxMin = vec3(0.4375, bottom, 0.4375);
        boxMax = vec3(0.5625, bottom + 0.1875, 0.5625);
        boxMin[axis] = connection % 2 == 0 ? 0.0 : 0.625;
        boxMax[axis] = boxMin[axis] + 0.375;
        return true;
    }
    if (family == WSR_FAMILY_WALL) {
        if (part == 0) {
            boxMin = vec3(0.25, 0.0, 0.25);
            boxMax = vec3(0.75, 1.0, 0.75);
            return (state & 64u) != 0u;
        }
        int connection = part - 1;
        int axis = connection < 2 ? 0 : 2;
        int face = connection < 2 ? connection : connection + 2;
        if ((state & (1u << uint(face))) == 0u) return false;
        float height = (state & 4u) != 0u ? 0.8125 : 0.875;
        if ((state & (1u << uint(connection + 7))) != 0u) height = 1.0;
        boxMin = vec3(0.3125, 0.0, 0.3125);
        boxMax = vec3(0.6875, height, 0.6875);
        boxMin[axis] = connection % 2 == 0 ? 0.0 : 0.5;
        boxMax[axis] = boxMin[axis] + 0.5;
        return true;
    }
    if (family == WSR_FAMILY_CHORUS) {
        if ((state & 64u) != 0u) {
            if (part > 5) return false;
            boxMin = vec3(0.125);
            boxMax = vec3(0.875);
            if (part == 0) boxMin.y = 0.0;
            else if (part == 1) {
                boxMin.y = 0.875;
                boxMax.y = 1.0;
            } else {
                int axis = part < 4 ? 0 : 2;
                boxMin[axis] = part % 2 == 0 ? 0.0 : 0.875;
                boxMax[axis] = boxMin[axis] + 0.125;
            }
            return true;
        }
        boxMin = vec3(0.25);
        boxMax = vec3(0.75);
        if (part == 0) return true;
        int face = part - 1;
        if ((state & (1u << uint(face))) == 0u) return false;
        boxMin[face / 2] = face % 2 == 0 ? 0.0 : 0.75;
        boxMax[face / 2] = boxMin[face / 2] + 0.25;
        return true;
    }
    return false;
}

float IntersectReflectionShapeBoxes(vec3 origin, vec3 rayDir, int family, int model, uint state, float maxDist, out vec3 normal) {
    if ((state & 2048u) == 0u) return -1.0;
    bvec3 parallel = lessThan(abs(rayDir), vec3(1e-8));
    vec3 inverseDir = 1.0 / mix(rayDir, vec3(1.0), parallel);
    vec3 enterNormal = -sign(rayDir);
    float nearest = maxDist + 1.0;
    float faceTolerance = family == WSR_FAMILY_MODEL_CUBOID && model >= 5 ? 0.0001 : 0.0;
    int partCount = family >= WSR_FAMILY_FIRST_MODEL ? GetModelTableShapePartCount(family, model)
                  : (family >= WSR_FAMILY_FIRST_BOX ? 1
                  : (family == WSR_FAMILY_SLAB_STAIR ? 4
                  : (family == WSR_FAMILY_WALL ? 5
                  : (family == WSR_FAMILY_CHORUS ? 7 : 9))));
    for (int part = 0; part < partCount; part++) {
        vec3 boxMin, boxMax;
        if (!GetReflectionShapeBox(family, model, state, part, boxMin, boxMax)) continue;
        if (any(bvec3(parallel.x && (origin.x < boxMin.x - faceTolerance || origin.x > boxMax.x + faceTolerance),
                      parallel.y && (origin.y < boxMin.y - faceTolerance || origin.y > boxMax.y + faceTolerance),
                      parallel.z && (origin.z < boxMin.z - faceTolerance || origin.z > boxMax.z + faceTolerance)))) continue;
        vec3 a = (boxMin - origin) * inverseDir;
        vec3 b = (boxMax - origin) * inverseDir;
        vec3 near = mix(min(a, b), vec3(-1e20), parallel);
        vec3 far = mix(max(a, b) + faceTolerance * abs(inverseDir), vec3(1e20), parallel);
        float nearDist = max(near.x, max(near.y, near.z));
        float farDist = min(far.x, min(far.y, far.z));
        // Rays starting inside pass through
        if (minOf(min(origin - boxMin, boxMax - origin)) > 0.001) continue;
        float distance = max(0.0, nearDist);
        if (farDist >= distance && distance <= maxDist && distance < nearest) {
            nearest = distance;
            int axis = near.x >= near.y && near.x >= near.z ? 0 : (near.y >= near.z ? 1 : 2);
            normal = vec3(0.0);
            normal[axis] = enterNormal[axis];
        }
    }
    return nearest <= maxDist ? nearest : -1.0;
}

uint SelectShapeRecord(vec3 local, vec3 normal, reflectionCellHandle cellRef) {
    uint head = GetShapeRecordHead(cellRef);
    uint selected = shapeRecordCapacity;
    float bestScore = -1e10;
    uint tieBreak = 0xffffffffu;
    int wantedFace = GetReflectionFaceIndex(normal);
    int normalAxis = wantedFace >> 1;
    bool matchingFaces = false;
    uint candidate = head;
    uint wantedFlags = shapeFlagResolved | (uint(wantedFace) << 24u);
    for (int i = 0; i < 128 && candidate > 0u && candidate <= shapeRecordCapacity; i++) {
        if ((shapeDataSSBO.records[candidate - 1u].shading.w & (shapeFlagPlane | shapeFlagResolved | shapeFaceMask)) == wantedFlags) {
            head = candidate;
            matchingFaces = true;
            break;
        }
        candidate = GetNextShapeRecord(shapeDataSSBO.records[candidate - 1u]);
    }
    for (int i = 0; i < 128 && head > 0u && head <= shapeRecordCapacity; i++) {
        uint index = head - 1u;
        uvec4 mapping = shapeDataSSBO.records[index].mapping;
        uint flags = shapeDataSSBO.records[index].shading.w;
        uint link = shapeDataSSBO.records[index].shading.y;
        head = matchingFaces
             ? (link & 65535u) | ((mapping.z >> 28u) << 16u) | (((mapping.y >> 30u) & 1u) << 20u)
             : GetCompactNextShapeRecord(flags, mapping.x);
        if (!IsShapeResolvedCuboid(flags)) continue;
        vec3 delta = local - GetShapeAnchor(mapping.y);
        uint codeU = mapping.z & 7u, codeV = (mapping.z >> 3u) & 7u;
        vec2 offset = vec2(delta[codeU >> 1u] * GetShapeCodeSign(codeU), delta[codeV >> 1u] * GetShapeCodeSign(codeV));
        offset *= 1.0 - 2.0 * vec2((mapping.z >> 6u) & 1u, (mapping.z >> 7u) & 1u);
        vec2 size = GetShapeCuboidSize(mapping.z);
        vec2 outside = max(max(-offset, offset - size), vec2(0.0));
        float score = (matchingFaces ? 8.0 : 0.0) - 4.0 * abs(delta[normalAxis]) - outside.x - outside.y;
        if (score > bestScore + 0.0001 || abs(score - bestScore) <= 0.0001 && shapeDataSSBO.records[index].shading.x < tieBreak) {
            bestScore = score;
            selected = index;
            tieBreak = shapeDataSSBO.records[index].shading.x;
        }
    }
    return selected;
}

bool UnpackShapeSurface(uint selected, vec3 local, vec2 atlasSize,
                               out faceData face, out vec2 localUV, out uint axes, out vec2 axisScale) {
    if (selected >= shapeRecordCapacity) return false;
    shapeRecord surface = shapeDataSSBO.records[selected];
    uvec3 data = surface.shading.xyz;
    vec2 anchorUV = GetShapeRawUV(data.x) / 65536.0;
    bool plane = (surface.shading.w & shapeFlagPlane) != 0u;
    vec3 anchor = GetShapeRecordAnchor(surface);
    vec3 axisU = plane ? GetShapePlaneVector(int(surface.mapping.z & 63u)) : GetShapeFaceNormal(int(surface.mapping.z & 7u));
    vec3 axisV = plane ? GetShapePlaneVector(int((surface.mapping.z >> 6u) & 63u)) : GetShapeFaceNormal(int((surface.mapping.z >> 3u) & 7u));
    vec2 scale = unpackHalf2x16(surface.mapping.w);
    if (min(scale.x, scale.y) < 1e-7) return false;
    float pixels = max(1.0, round(dot(scale * atlasSize, vec2(0.5))));
    vec2 tileScale = pixels / atlasSize;
    uint cornerShift = plane ? 12u : 6u;
    vec2 cornerSign = 2.0 * vec2((surface.mapping.z >> cornerShift) & 1u, (surface.mapping.z >> (cornerShift + 1u)) & 1u) - 1.0;
    vec2 tileOrigin = floor((anchorUV * atlasSize - 0.25 * cornerSign) / pixels) * tileScale;
    if (plane) {
        vec2 span = GetShapePlaneSize(surface) * scale;
        tileScale = vec2(max(1.0, max(span.x * atlasSize.x, span.y * atlasSize.y))) / atlasSize;
        tileOrigin = anchorUV - (0.5 + 0.5 * cornerSign) * span;
    }
    axisScale = scale / tileScale;
    axes = plane ? 4096u | (surface.mapping.z & 4095u) : surface.mapping.z & 63u;
    vec2 offset = vec2(dot(local - anchor, axisU), dot(local - anchor, axisV));
    if (!plane) offset = -cornerSign * clamp(-cornerSign * offset, vec2(0.0), GetShapeCuboidSize(surface.mapping.z));
    localUV = (anchorUV - tileOrigin) / tileScale + axisScale * offset;
    face = faceData(unpackUnorm4x8(data.z).xyz, UnpackFaceLightmap(data), vec3(tileOrigin, 0.5 * tileScale.x));
    return true;
}

float GetReflectionShapeAO(uint selected, vec3 local) {
    shapeRecord surface = shapeDataSSBO.records[selected];
    bool plane = (surface.shading.w & shapeFlagPlane) != 0u;
    vec3 axisU = plane ? GetShapePlaneVector(int(surface.mapping.z & 63u)) : GetShapeFaceNormal(int(surface.mapping.z & 7u));
    vec3 axisV = plane ? GetShapePlaneVector(int((surface.mapping.z >> 6u) & 63u)) : GetShapeFaceNormal(int((surface.mapping.z >> 3u) & 7u));
    uint shift = plane ? 12u : 6u;
    vec2 corner = vec2((surface.mapping.z >> shift) & 1u, (surface.mapping.z >> (shift + 1u)) & 1u);
    vec2 size = plane ? GetShapePlaneSize(surface) : GetShapeCuboidSize(surface.mapping.z);
    vec3 delta = local - GetShapeRecordAnchor(surface);
    vec2 uv = clamp(corner + vec2(dot(delta, axisU), dot(delta, axisV)) / max(size, vec2(0.0001)), 0.0, 1.0);
    vec4 ao = unpackUnorm4x8(shapeAOSSBO.corners[selected]); // 00,10,01,11
    if (corner.x == corner.y) {
        return uv.x >= uv.y ? ao.x + (ao.y - ao.x) * uv.x + (ao.w - ao.y) * uv.y
                           : ao.x + (ao.w - ao.z) * uv.x + (ao.z - ao.x) * uv.y;
    }
    return uv.x + uv.y <= 1.0 ? ao.x + (ao.y - ao.x) * uv.x + (ao.z - ao.x) * uv.y
                            : ao.w + (ao.z - ao.w) * (1.0 - uv.x) + (ao.y - ao.w) * (1.0 - uv.y);
}
