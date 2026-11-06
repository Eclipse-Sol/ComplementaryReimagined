#include "/lib/voxelization/reflectionShapeGeometry.glsl"
#include "/lib/voxelization/SSBOs/shapeHeadBuffer.glsl"
#include "/lib/voxelization/SSBOs/shapeAOBuffer.glsl"

vec3 getShapeAnchor(uint encoded) {
    uvec3 p = uvec3(encoded & 1023u, (encoded >> 10u) & 1023u, (encoded >> 20u) & 1023u);
    return vec3(p + uvec3(equal(p, uvec3(1023u)))) / 1024.0;
}

ivec3 getShapeVoxelPosition(uint index) {
    return ivec3(
        index % uint(sceneVoxelVolumeSize.x),
        (index / uint(sceneVoxelVolumeSize.x)) % uint(sceneVoxelVolumeSize.y),
        index / uint(sceneVoxelVolumeSize.x * sceneVoxelVolumeSize.y)
    );
}

vec3 getShapeSurfaceAnchor(shapeSurface surface) {
    if ((surface.shading.w & shapeFlagPlane) == 0u) return getShapeAnchor(surface.mapping.y);
    uvec3 p = uvec3(surface.mapping.y & 4095u, (surface.mapping.y >> 12u) & 4095u,
                    (surface.mapping.y >> 24u) | (((surface.shading.y >> 11u) & 15u) << 8u));
    return vec3(p) / 2048.0 - 0.5;
}

uint getShapeCompactNext(uint flags, uint mappingX) {
    return ((flags & shapeFlagCompactLink) != 0u ? flags : mappingX) & shapeHeadPointerMask;
}

uint getShapeNext(shapeSurface surface) {
    #ifdef SHAPE_BUILD
        return surface.mapping.x & shapeHeadPointerMask;
    #else
        return getShapeCompactNext(surface.shading.w, surface.mapping.x);
    #endif
}

vec2 getShapePlaneSize(shapeSurface surface) {
    uint mapping = surface.mapping.z, high = surface.mapping.x >> 21u;
    return vec2(((mapping >> 14u) & 511u) | ((high & 3u) << 9u),
                (mapping >> 23u) | (((high >> 2u) & 3u) << 9u)) / 1024.0;
}

vec2 getShapePlaneCornerSign(uint basis) {
    return 1.0 - 2.0 * vec2((basis >> 12u) & 1u, (basis >> 13u) & 1u);
}

vec2 getShapeCuboidSize(uint mapping) {
    uvec2 size = uvec2((mapping >> 8u) & 1023u, (mapping >> 18u) & 1023u);
    return vec2(size + uvec2(equal(size, uvec2(1023u)))) / 1024.0;
}

uint getShapeState(ivec3 p) {
    uint data = blockDataSSBO.data[getCellWordIndex(getSceneVoxelIndex(p))].w;
    return (data & 0xfffff000u) == getReflectionFrameStamp() ? data & 4095u : 0u;
}

#include "/lib/voxelization/reflectionSurfaceData.glsl"

#if defined SHADOW && defined VERTEX_SHADER
    void storeShapeState(ivec3 p, uint bits) {
        mergeStampedWord(getCellWordIndex(getSceneVoxelIndex(p)), bits, false);
    }

    #ifdef MC_GL_ARB_shader_draw_parameters
        #extension GL_ARB_shader_draw_parameters : enable
    #endif
    // Sodium sub-allocates sections
    int getShapeQuadCorner() {
        #ifdef MC_GL_ARB_shader_draw_parameters
            return (gl_VertexID - gl_BaseVertexARB) & 3;
        #else
            return gl_VertexID & 3;
        #endif
    }

    void UpdateReflectionShape(int rawMat, vec4 terrainTangent) {
        int corner = getShapeQuadCorner();
        uint vertexAlpha = uint(round(clamp(glColor.a, 0.0, 1.0) * 255.0));
        // Resolve defaults missing corners to 255, so this corner needs no record.
        if ((corner & 1) != 0 && vertexAlpha == 255u) return;
        int family = getReflectionShapeFamily(rawMat);
        vec3 center = playerToSceneVoxel(modelToScenePos(getBlockCenterModelPos()));
        if (any(lessThan(center, vec3(0))) || any(greaterThanEqual(center, vec3(sceneVoxelVolumeSize)))) return;
        ivec3 cell = ivec3(center);
        int voxelIndex = getSceneVoxelIndex(cell);
        uint quadId = uint(gl_VertexID - corner) / 4u;
        bool captured = family == WSR_FAMILY_CAPTURED;
        uint uvCorner = uint(texCoord.x > mc_midTexCoord.x) | (uint(texCoord.y > mc_midTexCoord.y) << 1u);
        uint vertexAO = vertexAlpha | (uvCorner << 8u);
        if ((corner & 1) != 0) {
            uint index = atomicAdd(shapeDataSSBO.count, 1u);
            if (index >= shapeSurfaceCapacity) return;
            uint flags = uint(voxelIndex) | shapeFaceMask | shapeFlagSecondary
                       | (family == WSR_FAMILY_SLAB_STAIR ? shapeFlagOctants : 0u)
                       | (captured ? shapeFlagPlane : 0u);
            shapeDataSSBO.surfaces[index].shading = uvec4(0u, 0u, 0u, flags);
            shapeDataSSBO.surfaces[index].mapping = uvec4(
                pushShapeHead(voxelIndex, index + 1u), 0u, 0u, quadId
            );
            shapeAOSSBO.corners[index] = vertexAO;
            return;
        }
        vec3 local = playerToSceneVoxel(modelToScenePos(gl_Vertex.xyz)) - vec3(cell);
        uint bits = 0u;
        if (family >= WSR_FAMILY_FIRST_MODEL) {
            bits = computeModelTableShapeState(family, getReflectionShapeModel(rawMat), local);
        } else if (family == WSR_FAMILY_LAYERED || family == WSR_FAMILY_PRESSURE_PLATE) {
            bits = uint(round(clamp(local.y * 32.0, 0.0, 32.0)));
        } else if (family == WSR_FAMILY_DOOR_TRAPDOOR || family == WSR_FAMILY_BUTTON) {
            float depth = family == WSR_FAMILY_DOOR_TRAPDOOR ? 0.1875 : 0.125;
            for (int axis = 0; axis < 3; axis++) {
                if (local[axis] < depth + 0.002) bits |= 1u << uint(2 * axis);
                if (local[axis] > 1.0 - depth - 0.002) bits |= 1u << uint(2 * axis + 1);
                if (family == WSR_FAMILY_BUTTON) {
                    if (abs(abs(local[axis] - 0.5) - 0.1875) < 0.002) bits |= 1u << uint(axis + 6);
                    if (abs(abs(local[axis] - 0.5) - 0.375) < 0.002) bits |= 512u; // unpressed depth
                }
            }
        } else if (family != WSR_FAMILY_SLAB_STAIR && !captured) {
            for (int axis = 0; axis < 3; axis++) {
                if (family != WSR_FAMILY_CHORUS && axis == 1) continue;
                if (local[axis] < 0.002) bits |= 1u << uint(2 * axis);
                if (local[axis] > 0.998) bits |= 1u << uint(2 * axis + 1);
            }
            if (family == WSR_FAMILY_WALL) {
                if (local.y > 0.94 && abs(abs(local.x - 0.5) - 0.25) < 0.01
                    && abs(abs(local.z - 0.5) - 0.25) < 0.01) bits |= 64u; // wall post
                if (local.y > 0.94) bits |= ((bits & 3u) << 7u) | ((bits & 48u) << 5u); // tall wall arms
                if (abs(local.y - 0.8125) < 0.01) bits |= 4u; // older 13/16-high wall arms
            }
            if (family == WSR_FAMILY_CHORUS && getReflectionMaterial(rawMat) != 10505) bits |= 64u; // chorus flower
        }
        if (!captured && (bits != 0u || corner == 0)) storeShapeState(cell, bits);

        if (corner == 0) {
            imageStore(wsr_img, cell, uvec4(uint(rawMat) | (captured ? 32768u : 0u), 0u, 0u, 0u));
            imageStore(wsr_lod_img, cell / 4, uvec4(1u, 0u, 0u, 0u));
            StoreReflectionCoarseOccupancy(cell);
        }
        uint index = atomicAdd(shapeDataSSBO.count, 1u);
        if (index >= shapeSurfaceCapacity) return;
        shapeAOSSBO.corners[index] = vertexAO;
        mat3 normalToWorld = mat3(shadowModelViewInverse) * gl_NormalMatrix;
        vec3 normal = normalize(normalToWorld * gl_Normal);
        vec3 tangent = normalize(normalToWorld * getShapeTerrainTangent(gl_Normal, terrainTangent.xyz));
        vec3 bitangent = normalize(cross(tangent, normal)) * terrainTangent.w;
        uvec3 shading = packFaceData(faceData(glColor.rgb, lmCoord, vec3(texCoord, 0.0)));
        uvec3 anchor = uvec3(round(clamp(local * 1024.0, 0.0, 1023.0)));
        uint basis = uint(getShapeFaceIndex(tangent)) | (uint(getShapeFaceIndex(bitangent)) << 3u);
        basis |= uvCorner << 6u;
        uint secondaryFlag = corner == 2 ? shapeFlagSecondary : 0u;
        uint kindFlag = family == WSR_FAMILY_SLAB_STAIR ? shapeFlagOctants : 0u;
        if (captured) {
            anchor = uvec3(round(clamp((local + 0.5) * 2048.0, 0.0, 4095.0)));
            shading.y = (shading.y & 0xffff0000u) | uint(rawMat - 20002) | ((anchor.z >> 8u) << 11u);
            basis = uint(getShapePlaneCode(tangent)) | (uint(getShapePlaneCode(bitangent)) << 6u);
            basis |= uvCorner << 12u;
            kindFlag = shapeFlagPlane;
        }
        shapeDataSSBO.surfaces[index].shading = uvec4(
            shading, uint(voxelIndex) | (uint(getShapeFaceIndex(normal)) << 24u) | secondaryFlag | kindFlag
        );
        uint packedAnchor = captured
                          ? anchor.x | (anchor.y << 12u) | ((anchor.z & 255u) << 24u)
                          : anchor.x | (anchor.y << 10u) | (anchor.z << 20u);
        shapeDataSSBO.surfaces[index].mapping = uvec4(
            pushShapeHead(voxelIndex, index + 1u), packedAnchor, basis, quadId
        );
    }
#endif

// Foliage is excluded because its planes overlap too much for tight bounds to help.
bool usesShapeListBounds(uint surfaceMaterialWord) {
    return (surfaceMaterialWord & 2047u) != 5u;
}

#ifdef SHAPE_SCATTER
    bool isShapeSegmentEndpoint(shapeSurface surface) {
        return isShapeUnresolvedSecondaryPlane(surface.shading.w) && usesShapeListBounds(surface.shading.y)
            && (surface.mapping.x & shapeMappingSegmentEndpoint) != 0u;
    }

    bool isShapeListStop(shapeSurface surface) {
        return isShapeResolvedPrimary(surface.shading.w)
            || isShapeBoundsRecord(surface.shading.w)
            || isShapeSegmentEndpoint(surface);
    }

    uint skipToShapeListStop(uint pointer, int limit) {
        for (int skip = 0; skip < limit && pointer > 0u && pointer <= shapeSurfaceCapacity; skip++) {
            shapeSurface candidate = shapeDataSSBO.surfaces[pointer - 1u];
            if (isShapeListStop(candidate)) break;
            pointer = getShapeNext(candidate);
        }
        return pointer;
    }

    bool accumulatePlaneBounds(shapeSurface surface, vec3 owner, inout vec3 lower, inout vec3 upper) {
        if ((surface.shading.w & shapeFlagPlane) == 0u) return false;
        vec3 u = getShapePlaneVector(int(surface.mapping.z & 63u));
        vec3 v = getShapePlaneVector(int((surface.mapping.z >> 6u) & 63u));
        if (abs(dot(u, v)) > 1e-6) return false;
        vec2 size = getShapePlaneSize(surface);
        vec2 signs = getShapePlaneCornerSign(surface.mapping.z);
        vec3 edgeU = u * size.x * signs.x, edgeV = v * size.y * signs.y;
        vec3 anchor = getShapeSurfaceAnchor(surface) + owner;
        lower = min(lower, anchor + min(edgeU, vec3(0.0)) + min(edgeV, vec3(0.0)));
        upper = max(upper, anchor + max(edgeU, vec3(0.0)) + max(edgeV, vec3(0.0)));
        return true;
    }

    uint accumulateListBounds(inout uint pointer, vec3 owner, int maxScan, uint maxPlanes, out vec3 lower, out vec3 upper) {
        lower = vec3(1e30);
        upper = vec3(-1e30);
        uint planes = 0u;
        for (int scan = 0; scan < maxScan && pointer > 0u && pointer <= shapeSurfaceCapacity; scan++) {
            shapeSurface item = shapeDataSSBO.surfaces[pointer - 1u];
            pointer = getShapeNext(item);
            if (!isShapeResolvedPrimary(item.shading.w)) continue;
            if (!accumulatePlaneBounds(item, owner, lower, upper)) return 0u;
            if (++planes == maxPlanes) break;
        }
        return planes;
    }

    void storeShapeBounds(uint index, vec3 lower, vec3 upper, uint link) {
        shapeDataSSBO.surfaces[index].shading = uvec4(floatBitsToUint(lower - vec3(0.001)), shapeKindBounds | link);
        shapeDataSSBO.surfaces[index].mapping.yzw = floatBitsToUint(upper + vec3(0.001));
    }

    void BuildReflectionSegmentBounds(uint index, int voxelIndex) {
        uint pointer = getShapeNext(shapeDataSSBO.surfaces[index]);
        vec3 lower, upper;
        if (accumulateListBounds(pointer, vec3(getShapeVoxelPosition(uint(voxelIndex))), 128, 4u, lower, upper) == 0u) return;
        storeShapeBounds(index, lower, upper, pointer);
    }
#endif

#if defined SHAPE_BUILD
    void getShapePlaneCellRange(vec3 anchor, vec3 edgeU, vec3 edgeV, out ivec3 first, out ivec3 last) {
        first = min(ivec3(floor(anchor + min(edgeU, vec3(0.0)) + min(edgeV, vec3(0.0)) + 0.0001)), ivec3(0));
        last = max(ivec3(floor(anchor + max(edgeU, vec3(0.0)) + max(edgeV, vec3(0.0)) - 0.0001)), ivec3(0));
    }

    #ifdef SHAPE_RESOLVE
        bool isShapeQuadPartner(shapeSurface other, shapeSurface surface) {
            return other.shading.w == (surface.shading.w | shapeFlagSecondary) && other.mapping.w == surface.mapping.w;
        }

        void mergeShapeCornerAO(uint value, inout uint quadAO, inout uint foundCorners) {
            uint corner = (value >> 8u) & 3u;
            quadAO = (quadAO & ~(255u << (corner * 8u))) | ((value & 255u) << (corner * 8u));
            foundCorners |= 1u << corner;
        }
    #endif

    void BuildReflectionShapeSurface(uint index) {
        #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && WORLD_SPACE_SHAPES > 0
            int voxelIndex = int(shapeDataSSBO.surfaces[index].shading.w & shapeVoxelIndexMask);
            int head = voxelIndex;
            #ifdef SHAPE_SCATTER
                shapeSurface surface = shapeDataSSBO.surfaces[index];
                if (isShapeBoundsRecord(surface.shading.w)) return;
                if (isShapeSegmentEndpoint(surface)) {
                    BuildReflectionSegmentBounds(index, voxelIndex);
                    return;
                }
                if (!isShapeResolvedPrimary(surface.shading.w)) {
                    if (readShapeHead(head) == index + 1u) {
                        if (isShapeSecondaryPlane(surface.shading.w) && usesShapeListBounds(surface.shading.y)) {
                            uint pointer = getShapeNext(surface);
                            vec3 lower, upper;
                            uint planes = accumulateListBounds(
                                pointer, vec3(getShapeVoxelPosition(uint(voxelIndex))), 256, 256u, lower, upper
                            );
                            if (pointer == 0u && planes >= 8u) {
                                storeShapeBounds(index, lower, upper, 0u);
                                return;
                            }
                        }
                        uint first = skipToShapeListStop(getShapeNext(surface), 1024);
                        atomicCompSwap(shapeHeadSSBO.heads[head], getShapeHeadEpochBits() | (index + 1u), getShapeHeadEpochBits() | first);
                    }
                    return;
                }
                uint next = getShapeNext(surface), compactNext = skipToShapeListStop(next, 256);
                // Shortcuts go in shading.w: other scatter workers are still walking mapping.x.
                if (compactNext != next)
                    shapeDataSSBO.surfaces[index].shading.w = (surface.shading.w & shapeFlagsMask) | compactNext | shapeFlagCompactLink;
                if ((surface.shading.w & shapeFlagPlane) == 0u) return;
                uint neighbors = (surface.mapping.x >> 25u) & 63u;
                if (neighbors == 0u) return;
                ivec3 owner = getShapeVoxelPosition(surface.shading.w & shapeVoxelIndexMask);
                ivec3 first, last;
                if (neighbors != 63u) {
                    first = -ivec3(neighbors & 1u, (neighbors >> 2u) & 1u, (neighbors >> 4u) & 1u);
                    last = ivec3((neighbors >> 1u) & 1u, (neighbors >> 3u) & 1u, (neighbors >> 5u) & 1u);
                } else {
                    vec3 anchor = getShapeSurfaceAnchor(surface);
                    vec2 size = getShapePlaneSize(surface);
                    vec2 cornerSign = getShapePlaneCornerSign(surface.mapping.z);
                    vec3 edgeU = getShapePlaneVector(int(surface.mapping.z & 63u)) * size.x * cornerSign.x;
                    vec3 edgeV = getShapePlaneVector(int((surface.mapping.z >> 6u) & 63u)) * size.y * cornerSign.y;
                    getShapePlaneCellRange(anchor, edgeU, edgeV, first, last);
                }
                for (int z = first.z; z <= last.z; z++)
                    for (int y = first.y; y <= last.y; y++)
                        for (int x = first.x; x <= last.x; x++) {
                            ivec3 cell = owner + ivec3(x, y, z);
                            if (all(equal(cell, owner)) || any(lessThan(cell, ivec3(0)))
                                || any(greaterThanEqual(cell, sceneVoxelVolumeSize))) continue;
                            uint copyIndex = atomicAdd(shapeDataSSBO.count, 1u);
                            if (copyIndex >= shapeSurfaceCapacity) continue;

                            int targetHead = getSceneVoxelIndex(cell);
                            surface.mapping.x = (surface.mapping.x & ~shapeHeadPointerMask) | pushShapeHead(targetHead, copyIndex + 1u);
                            shapeDataSSBO.surfaces[copyIndex] = surface;
                            shapeAOSSBO.corners[copyIndex] = shapeAOSSBO.corners[index];
                            uint mat = imageLoad(wsr_img, cell).r;
                            imageStore(wsr_img, cell, uvec4(mat | 32768u, 0u, 0u, 0u));
                            imageStore(wsr_lod_img, cell / 4, uvec4(1u, 0u, 0u, 0u));
                            StoreReflectionCoarseOccupancy(cell);
                        }
            #elif defined SHAPE_RESOLVE
                shapeSurface surface = shapeDataSSBO.surfaces[index];
                if ((surface.shading.w & shapeFlagSecondary) != 0u) {
                    if (getShapeFaceCode(surface.shading.w) < 6u
                        && (surface.shading.w & shapeFlagPlane) != 0u
                        && usesShapeListBounds(surface.shading.y)
                        && (surface.mapping.w & 3u) == 0u)
                        shapeDataSSBO.surfaces[index].mapping.x |= shapeMappingSegmentEndpoint;
                    return;
                }
                bool plane = (surface.shading.w & shapeFlagPlane) != 0u;
                uint quadAO = 0xffffffffu, foundCorners = 0u;
                mergeShapeCornerAO(shapeAOSSBO.corners[index], quadAO, foundCorners);
                uint aoOnlyFlags = (surface.shading.w & ~shapeFaceMask) | shapeFaceMask | shapeFlagSecondary;
                uint aoNext = readShapeHead(head);
                for (int scan = 0; scan < 1024 && aoNext > 0u && aoNext <= shapeSurfaceCapacity; scan++) {
                    uint otherIndex = aoNext - 1u;
                    shapeSurface item = shapeDataSSBO.surfaces[otherIndex];
                    aoNext = getShapeNext(item);
                    if (item.mapping.w != surface.mapping.w ||
                        (item.shading.w != (surface.shading.w | shapeFlagSecondary) && item.shading.w != aoOnlyFlags)) continue;
                    mergeShapeCornerAO(shapeAOSSBO.corners[otherIndex], quadAO, foundCorners);
                    if (foundCorners == 15u) break;
                }
                shapeAOSSBO.corners[index] = quadAO;
                if (!plane) {
                    uint nextFace = getShapeNext(surface);
                    for (int i = 0; i < 256 && nextFace > 0u && nextFace <= shapeSurfaceCapacity; i++) {
                        shapeSurface other = shapeDataSSBO.surfaces[nextFace - 1u];
                        if ((other.shading.w & (shapeFaceMask | shapeFlagSecondary)) == (surface.shading.w & shapeFaceMask)) break;
                        nextFace = getShapeNext(other);
                        if (i == 255) nextFace = 0u;
                    }
                    surface.mapping.z |= ((nextFace >> 16u) & 15u) << 28u;
                    shapeDataSSBO.surfaces[index].shading.y = (surface.shading.y & 0xffff0000u) | (nextFace & 65535u);
                    shapeDataSSBO.surfaces[index].mapping.z = surface.mapping.z;
                    shapeDataSSBO.surfaces[index].mapping.y = surface.mapping.y | ((nextFace >> 20u) << 30u);
                }
                uint next = 0u;
                if (index + 1u < min(shapeDataSSBO.count, shapeSurfaceCapacity)) {
                    if (isShapeQuadPartner(shapeDataSSBO.surfaces[index + 1u], surface)) next = index + 2u;
                }
                if (next == 0u && index > 0u) {
                    if (isShapeQuadPartner(shapeDataSSBO.surfaces[index - 1u], surface)) next = index;
                }
                if (next == 0u) next = readShapeHead(head);
                for (int i = 0; i < 256 && next > 0u && next <= shapeSurfaceCapacity; i++) {
                    shapeSurface other = shapeDataSSBO.surfaces[next - 1u];
                    if (isShapeQuadPartner(other, surface)) {
                        vec3 anchor = getShapeSurfaceAnchor(surface);
                        vec3 opposite = getShapeSurfaceAnchor(other);
                        vec3 delta = opposite - anchor;
                        vec3 axisU = plane ? vec3(0.0) : getShapeFaceNormal(int(surface.mapping.z & 7u));
                        vec3 axisV = plane ? vec3(0.0) : getShapeFaceNormal(int((surface.mapping.z >> 3u) & 7u));
                        vec2 uv = getShapeRawUV(surface.shading.x);
                        vec2 otherUV = getShapeRawUV(other.shading.x);
                        if (plane) {
                            axisU = getShapePlaneVector(int(surface.mapping.z & 63u));
                            vec3 capturedV = getShapePlaneVector(int((surface.mapping.z >> 6u) & 63u));
                            if (abs(axisU.y) < 0.001 && abs(capturedV.y) > 0.999
                                && abs(delta.y) > 0.002 && min(abs(delta.x), abs(delta.z)) > 0.002
                                && abs(abs(delta.x) - abs(delta.z)) < 0.004)
                                axisU = getShapePlaneVector(getShapePlaneCode(normalize(vec3(delta.x, 0.0, delta.z)) * sign(otherUV.x - uv.x)));
                            vec3 remainder = delta - axisU * dot(delta, axisU);
                            if (dot(remainder, remainder) < 1e-8 || min(abs(otherUV.x - uv.x), abs(otherUV.y - uv.y)) < 0.5) return;
                            axisV = getShapePlaneVector(getShapePlaneCode(normalize(remainder) * sign(otherUV.y - uv.y)));
                        }
                        if (dot(delta, axisU) * (otherUV.x - uv.x) < 0.0) axisU = -axisU;
                        if (dot(delta, axisV) * (otherUV.y - uv.y) < 0.0) axisV = -axisV;
                        vec2 extent = abs(vec2(dot(delta, axisU), dot(delta, axisV)));
                        if (min(extent.x, extent.y) < 0.0001) return;
                        vec2 scale = abs(otherUV - uv) / (65536.0 * extent);
                        uvec2 size = uvec2(round(min(extent * 1024.0, vec2(plane ? 2047.0 : 1023.0))));
                        if (plane) {
                            vec2 cornerSign = getShapePlaneCornerSign(surface.mapping.z);
                            vec3 edgeU = axisU * (float(size.x) / 1024.0) * cornerSign.x;
                            vec3 edgeV = axisV * (float(size.y) / 1024.0) * cornerSign.y;
                            ivec3 first, last;
                            getShapePlaneCellRange(anchor, edgeU, edgeV, first, last);
                            uint neighbors = 63u;
                            if (all(greaterThanEqual(first, ivec3(-1))) && all(lessThanEqual(last, ivec3(1))))
                                neighbors = uint(first.x < 0) | (uint(last.x > 0) << 1u)
                                          | (uint(first.y < 0) << 2u) | (uint(last.y > 0) << 3u)
                                          | (uint(first.z < 0) << 4u) | (uint(last.z > 0) << 5u);
                            shapeDataSSBO.surfaces[index].mapping.x = getShapeNext(surface)
                                | ((size.x >> 9u) << 21u) | ((size.y >> 9u) << 23u) | (neighbors << 25u);
                            uint codeU = uint(getShapePlaneCode(axisU)), codeV = uint(getShapePlaneCode(axisV));
                            shapeDataSSBO.surfaces[index].mapping.z = (surface.mapping.z & 12288u)
                                | codeU | (codeV << 6u)
                                | ((size.x & 511u) << 14u) | ((size.y & 511u) << 23u);
                            // shapeFlagTiltedFlip records that the crossed normal points away from the stored face
                            if (isShapeTiltedBasis(codeU, codeV)) {
                                uint face = getShapeFaceCode(surface.shading.w);
                                vec3 planeNormal = cross(axisU, axisV);
                                if (planeNormal[face >> 1u] * getShapeCodeSign(face) < 0.0)
                                    shapeDataSSBO.surfaces[index].shading.w |= shapeFlagTiltedFlip;
                            }
                        } else
                            shapeDataSSBO.surfaces[index].mapping.z = (surface.mapping.z & ~63u)
                                | uint(getShapeFaceIndex(axisU)) | (uint(getShapeFaceIndex(axisV)) << 3u)
                                | (size.x << 8u) | (size.y << 18u);
                        shapeDataSSBO.surfaces[index].mapping.w = packHalf2x16(scale);
                        shapeDataSSBO.surfaces[index].shading.w |= shapeFlagResolved;
                        uint bits = 2048u;
                        if (!plane && (surface.shading.w & shapeFlagOctants) != 0u) {
                            vec3 normal = getShapeFaceNormal(int(getShapeFaceCode(surface.shading.w)));
                            vec3 inset = 0.002 * (1.0 - abs(normal));
                            vec3 lo = min(anchor, opposite) + inset - 0.002 * normal;
                            vec3 hi = max(anchor, opposite) - inset - 0.002 * normal;
                            uvec3 first = uvec3(greaterThanEqual(lo, vec3(0.5)));
                            bvec3 spans = notEqual(first, uvec3(greaterThanEqual(hi, vec3(0.5))));
                            uint occupied = 1u << first.x;
                            if (spans.x) occupied |= occupied << 1u;
                            occupied <<= 2u * first.y;
                            if (spans.y) occupied |= occupied << 2u;
                            occupied <<= 4u * first.z;
                            if (spans.z) occupied |= occupied << 4u;
                            bits |= occupied;
                        }
                        if (!plane) atomicOr(blockDataSSBO.data[getCellWordIndex(voxelIndex)].w, bits);
                        return;
                    }
                    next = getShapeNext(other);
                }
            #endif
        #endif
    }
#endif
