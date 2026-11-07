#include "/lib/voxelization/reflectionFaceGeometry.glsl"

// shapeSurface.shading.w flags
const uint shapeFaceMask = 0x07000000u;
const uint shapeFlagSecondary = 1u << 27u;
const uint shapeFlagResolved = 1u << 28u;
const uint shapeFlagOctants = 1u << 29u;
const uint shapeFlagTiltedFlip = 1u << 29u;
const uint shapeFlagPlane = 1u << 30u;
const uint shapeFlagCompactLink = 1u << 31u;
const uint shapeKindMask = 0x78000000u;
const uint shapeKindBounds = 0x68000000u;

uint getShapeFaceCode(uint flags) {
    return (flags >> 24u) & 7u;
}

float getShapeCodeSign(uint code) {
    return (code & 1u) != 0u ? 1.0 : -1.0;
}

bool isShapeTiltedBasis(uint codeU, uint codeV) {
    return codeU >= 6u && codeU < 10u && (codeV & ~1u) == 2u;
}

bool isShapeAxisBasis(uint codeU, uint codeV, uint normalAxis) {
    return ((1u << (codeU >> 1u)) | (1u << (codeV >> 1u)) | (1u << normalAxis)) == 7u;
}

vec2 getShapeRawUV(uint packedUV) {
    return vec2(packedUV >> 16u, packedUV & 65535u);
}

bool isShapeBoundsRecord(uint flags) {
    return (flags & shapeKindMask) == shapeKindBounds;
}

const uint shapeFlagsMask = 0xff000000u;
const uint shapeVoxelIndexMask = 0xffffffu;
const uint shapeMappingSegmentEndpoint = 0x80000000u;

bool isShapeSecondaryPlane(uint flags) {
    return (flags & (shapeFlagSecondary | shapeFlagPlane)) == (shapeFlagSecondary | shapeFlagPlane);
}

bool isShapeResolvedPrimary(uint flags) {
    return (flags & (shapeFlagSecondary | shapeFlagResolved)) == shapeFlagResolved;
}

bool isShapeResolvedCuboid(uint flags) {
    return (flags & (shapeFlagResolved | shapeFlagPlane)) == shapeFlagResolved;
}

bool isShapeResolvedPlane(uint flags) {
    return (flags & (shapeFlagSecondary | shapeFlagResolved | shapeFlagPlane)) == (shapeFlagResolved | shapeFlagPlane);
}

bool isShapeUnresolvedSecondaryPlane(uint flags) {
    return (flags & (shapeFlagSecondary | shapeFlagResolved | shapeFlagPlane)) == (shapeFlagSecondary | shapeFlagPlane);
}

uint computeModelTableShapeState(int family, int model, vec3 local) {
    if (family == WSR_FAMILY_MODEL_TURTLE_EGG) {
        vec2 p = local.xz * 16.0;
        uint bits = 0u;
        if (abs(local.y - 0.4375) < 0.002) {
            if (abs(p.x - 5.0) < 0.02) bits |= 1u;
            if (abs(p.x - 12.0) < 0.02) bits |= 2u;
            if (abs(p.x - 11.0) < 0.02) bits |= 4u;
            if (abs(p.x - 4.0) < 0.02) bits |= 8u;
        }
        if (abs(local.y - 0.3125) < 0.002) bits |= 16u;
        float radius = dot(p - 8.0, p - 8.0);
        if (abs(radius - 37.0) < 0.05 || abs(radius - 40.0) < 0.05) bits |= 32u;
        if (abs(radius - 5.0) < 0.05 || abs(radius - 29.0) < 0.05) bits |= 64u;
        return bits;
    }
    if (family == WSR_FAMILY_MODEL_CUBOID && model == 2) {
        return abs(local.x - 0.9375) > 0.002 ? uint(round(clamp((local.x - 0.0625) * 8.0, 0.0, 6.0))) : 0u;
    }
    vec3 distance = abs(local - 0.5);
    if (family == WSR_FAMILY_MODEL_ROD) {
        bvec3 wide = lessThan(abs(distance - 0.125), vec3(0.002));
        int axis = wide.y && wide.z ? 0
                 : (wide.x && wide.z ? 1
                 : (wide.x && wide.y ? 2 : -1));
        if (axis < 0) return 0u;
        bool positive = model == 0 ? local[axis] < 0.5 : local[axis] > 0.5;
        return 64u | uint(axis * 2 + int(positive));
    }
    if (family == WSR_FAMILY_MODEL_FENCE_GATE) {
        uint bits = 0u;
        if (distance.x > 0.49 && abs(distance.z - 0.0625) < 0.002) bits |= 64u;
        if (distance.z > 0.49 && abs(distance.x - 0.0625) < 0.002) bits |= 65u;
        if (abs(local.y - 0.125) < 0.002 || abs(local.y - 0.8125) < 0.002) bits |= 2u;
        if (distance.z > 0.374) {
            if (local.x > 0.625) bits |= 4u;
            if (local.x < 0.375) bits |= 8u;
        }
        if (distance.x > 0.374) {
            if (local.z > 0.625) bits |= 16u;
            if (local.z < 0.375) bits |= 32u;
        }
        return bits;
    }
    if (family == WSR_FAMILY_MODEL_MISC && model == 0) {
        if (distance.x > 0.49 && abs(distance.z - 0.3125) < 0.002) return 3u;
        if (distance.z > 0.49 && abs(distance.x - 0.3125) < 0.002) return 2u;
    }
    return 0u;
}

int getShapeFaceIndex(vec3 direction) {
    return getReflectionFaceIndex(direction);
}

vec3 getShapeFaceNormal(int axis) {
    vec3 result = vec3(0.0);
    result[axis / 2] = axis % 2 == 1 ? 1.0 : -1.0;
    return result;
}

int getShapePlaneCode(vec3 direction) {
    vec3 a = abs(direction);
    int zeroAxis = a.x < a.y && a.x < a.z ? 0 : (a.y < a.z ? 1 : 2);
    int u = (zeroAxis + 1) % 3, v = (zeroAxis + 2) % 3;
    if (min(a[u], a[v]) < 0.19509) return getShapeFaceIndex(direction);
    float ratio = a[u] / a[v];
    int angle = ratio > 1.496606 ? 0 : (ratio < 0.668179 ? 2 : 1);
    if (zeroAxis == 1 && angle == 1)
        return direction.x * direction.z > 0.0 ? (direction.x > 0.0 ? 6 : 7)
                                             : (direction.x > 0.0 ? 8 : 9);
    int kind = zeroAxis == 1 ? (angle == 0 ? 3 : 7) : ((zeroAxis << 1) | angle);
    return 32 | (kind << 2) | int(direction[u] < 0.0) | (int(direction[v] < 0.0) << 1);
}

vec3 getShapeDiagonalVector(int axis) {
    return vec3((axis & 1) == 0 ? 0.707106781 : -0.707106781, 0.0,
                (axis == 6 || axis == 9) ? 0.707106781 : -0.707106781);
}

vec3 getShapePlaneVector(int axis) {
    if (axis < 6) return getShapeFaceNormal(axis);
    if (axis < 10) return getShapeDiagonalVector(axis);
    int kind = (axis >> 2) & 7, angle = kind & 3;
    int zeroAxis = (kind & 4) >> 1;
    if (angle == 3) {
        zeroAxis = 1;
        angle = (kind >> 1) & 2;
    }
    const vec3 cosine = vec3(0.923879533, 0.707106781, 0.382683432);
    vec2 components = vec2(cosine[angle], cosine[2 - angle])
                    * vec2((axis & 1) == 0 ? 1.0 : -1.0, (axis & 2) == 0 ? 1.0 : -1.0);
    return zeroAxis == 0 ? vec3(0.0, components)
         : (zeroAxis == 1 ? vec3(components.y, 0.0, components.x) : vec3(components, 0.0));
}
