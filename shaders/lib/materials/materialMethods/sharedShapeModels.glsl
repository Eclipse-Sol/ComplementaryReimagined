#ifndef MODEL_TABLE_SHAPES
#define MODEL_TABLE_SHAPES

int getModelTableShapePartCount(int family, int model) {
    if (family == WSR_FAMILY_MODEL_CUBOID) return model <= 7 ? 1 : 0;
    if (family == WSR_FAMILY_MODEL_ROD) return model <= 1 ? 2 : 0;
    if (family == WSR_FAMILY_MODEL_FENCE_GATE) return model == 0 ? 8 : 0;
    if (family == WSR_FAMILY_MODEL_MISC)
        return model == 0 ? 4
             : (model == 1 ? 2
             : (model == 2 ? 6 : 0));
    if (family == WSR_FAMILY_MODEL_TURTLE_EGG) return model == 0 ? 4 : 0;
    return 0;
}

void rotateModelTableShapeY(int turn, inout vec3 lower, inout vec3 upper) {
    vec3 lo = lower, hi = upper;
    if (turn == 1) {
        lower.xz = vec2(16.0 - hi.z, lo.x);
        upper.xz = vec2(16.0 - lo.z, hi.x);
    }
    if (turn == 2) {
        lower.xz = 16.0 - hi.xz;
        upper.xz = 16.0 - lo.xz;
    }
    if (turn == 3) {
        lower.xz = vec2(lo.z, 16.0 - hi.x);
        upper.xz = vec2(hi.z, 16.0 - lo.x);
    }
}

bool getModelTableShapeBox(int family, int model, uint state, int part, out vec3 boxMin, out vec3 boxMax) {
    if (family == WSR_FAMILY_MODEL_CUBOID) {
        if (model == 0) {
            boxMin = vec3(7, 0, 7);
            boxMax = vec3(9, 10, 9);
        } else if (model == 1) {
            boxMin = vec3(4, 0, 4);
            boxMax = vec3(12, 8, 12);
        } else if (model == 2) {
            boxMin = vec3(1.0 + 2.0 * float(state & 7u), 0, 1);
            boxMax = vec3(15, 8, 15);
        } else if (model == 3) {
            boxMin = vec3(0);
            boxMax = vec3(16);
        } else if (model == 4) {
            boxMin = vec3(1, 0, 2);
            boxMax = vec3(15, 16, 14);
        } else {
            boxMin = vec3(0);
            boxMax = vec3(16, model == 6 ? 12 : (model == 7 ? 1 : 16), 16);
        }
    } else if (family == WSR_FAMILY_MODEL_ROD) {
        if ((state & 64u) == 0u) return false;
        int direction = int(state & 7u), axis = direction / 2;
        float lower, upper, radius;
        if (model == 0) {
            lower = part == 0 ? 0.0 : 1.0;
            upper = part == 0 ? 1.0 : 16.0;
        } else {
            lower = part == 0 ? 12.0 : 0.0;
            upper = part == 0 ? 16.0 : 12.0;
        }
        radius = part == 0 ? 2.0 : 1.0;
        boxMin = vec3(8.0 - radius);
        boxMax = vec3(8.0 + radius);
        boxMin[axis] = (direction & 1) != 0 ? lower : 16.0 - upper;
        boxMax[axis] = (direction & 1) != 0 ? upper : 16.0 - lower;
    } else if (family == WSR_FAMILY_MODEL_FENCE_GATE) {
        if ((state & 64u) == 0u) return false;
        bool swapAxes = (state & 1u) != 0u;
        uint opened = state & (swapAxes ? 12u : 48u);
        if (part < 2) {
            float x = part == 0 ? 0.0 : 14.0;
            boxMin = vec3(x, 5, 7);
            boxMax = vec3(x + 2.0, 16, 9);
        } else if (part < 4) {
            float x = opened != 0u ? (part == 2 ? 0.0 : 14.0)
                                  : (part == 2 ? 6.0 : 8.0);
            float z = opened != 0u ? 13.0 : 7.0;
            boxMin = vec3(x, 6, z);
            boxMax = vec3(x + 2.0, 15, z + 2.0);
        } else {
            int side = (part - 4) / 2;
            float y = (part & 1) == 0 ? 6.0 : 12.0;
            if (opened != 0u) {
                float x = side == 0 ? 0.0 : 14.0;
                boxMin = vec3(x, y, 9);
                boxMax = vec3(x + 2.0, y + 3.0, 13);
            } else {
                float x = side == 0 ? 2.0 : 10.0;
                boxMin = vec3(x, y, 7);
                boxMax = vec3(x + 4.0, y + 3.0, 9);
            }
        }
        if ((state & 2u) != 0u) {
            boxMin.y -= 3.0;
            boxMax.y -= 3.0;
        }
        if ((opened & (swapAxes ? 8u : 32u)) != 0u) {
            float lower = boxMin.z;
            boxMin.z = 16.0 - boxMax.z;
            boxMax.z = 16.0 - lower;
        }
        if (swapAxes) {
            boxMin = boxMin.zyx;
            boxMax = boxMax.zyx;
        }
    } else if (family == WSR_FAMILY_MODEL_MISC) {
        if (model == 0) {
            if ((state & 2u) == 0u) return false;
            const vec3 lower[4] = vec3[4](
                vec3(2, 0, 2), vec3(4, 4, 3), vec3(6, 5, 4), vec3(3, 10, 0)
            );
            const vec3 upper[4] = vec3[4](
                vec3(14, 4, 14), vec3(12, 5, 13), vec3(10, 10, 12), vec3(13, 16, 16)
            );
            boxMin = lower[part];
            boxMax = upper[part];
            if ((state & 1u) != 0u) {
                boxMin = boxMin.zyx;
                boxMax = boxMax.zyx;
            }
        } else if (model == 1) {
            boxMin = part == 0 ? vec3(0) : vec3(4, 13, 4);
            boxMax = part == 0 ? vec3(16, 13, 16) : vec3(12, 16, 12);
        } else {
            const vec3 lower[6] = vec3[6](
                vec3(6, 15, 6), vec3(5, 14, 5), vec3(4, 13, 4),
                vec3(3, 0, 3), vec3(2, 1, 2), vec3(1, 3, 1)
            );
            const vec3 upper[6] = vec3[6](
                vec3(10, 16, 10), vec3(11, 15, 11), vec3(12, 14, 12),
                vec3(13, 13, 13), vec3(14, 11, 14), vec3(15, 8, 15)
            );
            boxMin = lower[part];
            boxMax = upper[part];
        }
    } else if (family == WSR_FAMILY_MODEL_TURTLE_EGG) {
        if ((state & 15u) == 0u) return false;
        int count = (state & 64u) != 0u ? 4
                  : ((state & 32u) != 0u ? 3
                  : ((state & 16u) != 0u ? 2 : 1));
        if (part >= count) return false;
        const vec3 lower[4] = vec3[4](
            vec3(5, 0, 4), vec3(1, 0, 7), vec3(11, 0, 7), vec3(6, 0, 9)
        );
        const vec3 upper[4] = vec3[4](
            vec3(9, 7, 8), vec3(5, 5, 11), vec3(14, 4, 10), vec3(10, 4, 13)
        );
        boxMin = lower[part];
        boxMax = upper[part];
        int turn = (state & 2u) != 0u ? 1
                 : ((state & 4u) != 0u ? 2
                 : ((state & 8u) != 0u ? 3 : 0));
        rotateModelTableShapeY(turn, boxMin, boxMax);
    } else return false;
    boxMin *= 0.0625;
    boxMax *= 0.0625;
    return true;
}

#endif
