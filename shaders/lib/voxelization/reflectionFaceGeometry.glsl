#ifndef REFLECTION_FACE_GEOMETRY_INCLUDED
#define REFLECTION_FACE_GEOMETRY_INCLUDED

int GetReflectionFaceIndex(vec3 direction) {
    vec3 a = abs(direction);
    int axis = a.x > a.y && a.x > a.z ? 0 : (a.y > a.z ? 1 : 2);
    return axis * 2 + int(direction[axis] > 0.0);
}

#endif
