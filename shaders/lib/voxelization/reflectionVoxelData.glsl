#extension GL_ARB_gpu_shader5 : enable
#extension GL_ARB_shading_language_packing : enable

#include "/lib/voxelization/reflectionTextureMapping.glsl"
#include "/lib/voxelization/reflectionFaceGeometry.glsl"

struct faceData {
	vec3 glColor;
	vec2 lightmap;
	vec3 textureBounds;

};

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_BUILD
	#define SSBO_QUALIFIER
#else
	#define SSBO_QUALIFIER readonly
#endif

#if WORLD_SPACE_PLAYER_REF == 1
	#include "/lib/voxelization/SSBOs/playerVerticesBuffer.glsl"
#endif

#include "/lib/voxelization/SSBOs/blockDataBuffer.glsl"

// Opposite sides of a boundary belong to different blocks
int getFaceIndex(ivec3 voxelPos, vec3 normal) {
	return 6 * getSceneVoxelIndex(voxelPos) + getReflectionFaceIndex(normal);
}

uvec3 packFaceData(faceData data) {
	uvec3 uv = uvec3(clamp(round(data.textureBounds * 65536.0), 0.0, 65535.0));
	uvec2 lightmap = uvec2(clamp(data.lightmap * 4096.0, 0.0, 4095.0));
	return uvec3((uv.x << 16u) | uv.y,
				 uv.z | (lightmap.x << 16u) | ((lightmap.y & 15u) << 28u),
				 packUnorm4x8(vec4(data.glColor, 0.0)) | ((lightmap.y >> 4u) << 24u));
}

vec2 unpackFaceLightmap(uvec3 data) {
	return vec2((data.y >> 16u) & 4095u, (data.y >> 28u) | ((data.z >> 24u) << 4u)) / 4096.0;
}

uvec3 packReflectionFaceData(faceData face, uint orientation) {
    uvec3 data = packFaceData(face);
    data.y = (data.y & 0xf000ffffu) | (((data.y >> 19u) & 511u) << 16u) | (orientation << 25u);
    return data;
}

faceData unpackReflectionFaceData(uvec3 data, out uint orientation) {
    orientation = (data.y >> 25u) & 7u;
    vec2 lightmap = vec2((data.y >> 16u) & 511u, (data.y >> 28u) | ((data.z >> 24u) << 4u)) / vec2(512.0, 4096.0);
    return faceData(unpackUnorm4x8(data.z).xyz, lightmap,
                    vec3(data.x >> 16u, data.x & 65535u, data.y & 65535u) / 65536.0);
}

uvec3 readReflectionFace(int face) {
    if (!reflectionStorageAvailable()) return uvec3(0u);
    #if defined SHADOW && defined VERTEX_SHADER
        uint reference = atomicAdd(blockDataSSBO.faceRefs[face], 0u);
    #else
        uint reference = blockDataSSBO.faceRefs[face];
    #endif
    uint pointer = reference & reflectionFacePointerMask;
    if (pointer == 0u || pointer > reflectionFaceCapacity) return uvec3(0u);
    uint epoch = blockDataSSBO.faceEpoch;
    uint stamp = reference & reflectionFaceEpochMask;
    uint recordEpoch = epoch;
    if (stamp != ((epoch << 21u) & reflectionFaceEpochMask)) {
        #if defined SHADOW && defined VERTEX_SHADER
            recordEpoch = epoch - 1u;
            if (stamp != ((recordEpoch << 21u) & reflectionFaceEpochMask)) return uvec3(0u);
        #else
            return uvec3(0u);
        #endif
    }
    #if defined SHADOW && defined VERTEX_SHADER
        memoryBarrier();
    #endif
    uint index = (recordEpoch & 1u) * reflectionFaceCapacity + pointer - 1u;
    uvec4 record = blockDataSSBO.faces[index];
    return record.w == recordEpoch ? record.xyz : uvec3(0u);
}

faceData getFaceData(ivec3 voxelPos, vec3 normal, out uint orientation) {
    faceData face = unpackReflectionFaceData(readReflectionFace(getFaceIndex(voxelPos, normal)), orientation);
    orientation ^= getDefaultReflectionFaceOrientation(normal);
    return face;
}

faceData getFaceData(ivec3 voxelPos, vec3 normal) {
    uint orientation;
    return getFaceData(voxelPos, normal, orientation);
}

int getCellWordIndex(int voxelIndex) {
	return lavaCornerCount + voxelIndex;
}

int getLavaTopIndex(ivec3 voxelPos) {
	return getFaceIndex(voxelPos, vec3(0.0, 1.0, 0.0));
}

faceData getLavaFaceData(ivec3 voxelPos, out mat2 textureRotation) {
	uvec3 data = readReflectionFace(getLavaTopIndex(voxelPos));
	uint origin = data.x;
	uint bits = data.y;
	float angle = float((bits >> 16u) & 255u) * (6.28318530718 / 256.0);
	vec2 rotation = vec2(cos(angle), sin(angle));
	textureRotation = mat2(rotation, vec2(-rotation.y, rotation.x));
	return faceData(vec3(1.0),
					vec2((bits >> 24u) & 15u, bits >> 28u) / 15.0,
					vec3(origin >> 16u, origin & 65535u, bits & 65535u) / 65536.0);
}

int getLavaCornerIndex(ivec3 corner) {
	return corner.x + (sceneVoxelVolumeSize.x + 1) * (corner.y + sceneVoxelVolumeSize.y * corner.z);
}

#if WORLD_SPACE_SHAPES > 0
	#include "/lib/voxelization/SSBOs/shapeDataBuffer.glsl"
#endif

uint getReflectionFrameStamp() {
	#if WORLD_SPACE_SHAPES > 0
		return (shapeDataSSBO.epoch + 1u) << 12u;
	#else
		return uint(frameCounter + 1) << 12u;
	#endif
}

float getLavaCornerHeight(ivec3 corner) {
	if (!reflectionStorageAvailable()) return 1.0;
	uint data = blockDataSSBO.metadata[getLavaCornerIndex(corner)];
	return (data & 0xfffff000u) == getReflectionFrameStamp() ? float(data & 4095u) / 4095.0 : 1.0;
}

#if defined SHADOW && defined VERTEX_SHADER
void mergeStampedWord(int index, uint payload, bool keepMax) {
	if (!reflectionStorageAvailable()) return;
	uint stamp = getReflectionFrameStamp();
	uint newData = stamp | payload;
	uint oldData = atomicAdd(blockDataSSBO.metadata[index], 0u);
	while (true) {
		uint updated = newData;
		if ((oldData & 0xfffff000u) == stamp) updated = keepMax ? max(oldData, newData) : oldData | newData;
		if (updated == oldData) break;
		uint previous = atomicCompSwap(blockDataSSBO.metadata[index], oldData, updated);
		if (previous == oldData) break;
		oldData = previous;
	}
}

void storeLavaCorner(ivec3 corner, float height) {
	mergeStampedWord(getLavaCornerIndex(corner), uint(round(height * 4095.0)), true);
}

uint captureReflectionFace(uvec3 data) {
    if (!reflectionStorageAvailable()) return 0u;
    uint slot = atomicAdd(blockDataSSBO.faceCount, 1u);
    if (slot >= reflectionFaceCapacity) {
        atomicOr(blockDataSSBO.faceOverflow, 1u);
        return 0u;
    }
    uint epoch = blockDataSSBO.faceEpoch;
    uint index = (epoch & 1u) * reflectionFaceCapacity + slot;
    blockDataSSBO.faces[index] = uvec4(data, epoch);
    memoryBarrier();
    return ((epoch << 21u) & reflectionFaceEpochMask) | (slot + 1u);
}

void publishReflectionFace(ivec3 voxelPos, vec3 normal, uint reference) {
    if (reference != 0u) atomicExchange(blockDataSSBO.faceRefs[getFaceIndex(voxelPos, normal)], reference);
}

void storeLavaFaceData(ivec3 voxelPos, vec2 origin, float textureRad, float textureRotation) {
    uvec3 uv = uvec3(clamp(round(vec3(origin, textureRad) * 65536.0), 0.0, 65535.0));
    uvec2 lightmap = uvec2(round(clamp(vec2(lmCoord.x * 0.99 + 0.001, lmCoord.y), 0.0, 1.0) * 15.0));
    uint angle = uint(round(fract(textureRotation / 6.28318530718) * 256.0)) & 255u;
    uvec3 data = uvec3((uv.x << 16u) | uv.y,
                     uv.z | (angle << 16u) | (lightmap.x << 24u) | (lightmap.y << 28u), 0u);
    publishReflectionFace(voxelPos, vec3(0.0, 1.0, 0.0), captureReflectionFace(data));
}

void storeReflectionFace(ivec3 voxelPos, vec3 normal, uvec3 data) {
    publishReflectionFace(voxelPos, normal, captureReflectionFace(data));
}

void storeFaceData(ivec3 voxelPos, vec3 normal, vec2 origin, float textureRad, uint orientation, bool storeToAllFaces, bool storeToAllFacesExceptTop, vec3 playerPos) {
	vec2 lmCoordM = lmCoord;

	if (storeToAllFaces || storeToAllFacesExceptTop) {
		vec3 playerPosPrevious = playerPos - previousCameraPosition + cameraPosition;
		vec3 voxelPosPrevious = playerToPreviousSceneVoxel(playerPosPrevious);
		if (CheckInsideSceneVoxelVolume(voxelPosPrevious)) {
			faceData oldFaceData = getFaceData(ivec3(voxelPosPrevious), normal);
			#if WORLD_SPACE_SHAPES > 0
				// block crossings would fade held light faster while moving
				float lightBlend = isReflectionPeriodicRefresh() ? 1.0 - pow(0.99, float(WSR_REFRESH_INTERVAL)) : 0.0;
			#else
				const float lightBlend = 0.01;
			#endif
			lmCoordM = mix(max(lmCoord, oldFaceData.lightmap), lmCoord, lightBlend);
		}
	}

	uvec3 newData = packReflectionFaceData(faceData(glColor.rgb, vec2(lmCoordM.x * 0.99 + 0.001, lmCoordM.y), vec3(origin, textureRad)), orientation);
	uint reference = captureReflectionFace(newData);

	if (storeToAllFaces || storeToAllFacesExceptTop) {
		vec3 faceOffsets[6] = vec3[6](
			vec3( 0.0,  1.0,  0.0),
			vec3( 0.0,  0.0,  1.0),
			vec3( 1.0,  0.0,  0.0),
			vec3( 0.0,  0.0, -1.0),
			vec3( 0.0, -1.0,  0.0),
			vec3(-1.0,  0.0,  0.0)
		);

		int start = 0 + int(storeToAllFacesExceptTop);
		for(int i = start; i < 6; i++) {
			publishReflectionFace(voxelPos, faceOffsets[i], reference);
		}
	} else {
		publishReflectionFace(voxelPos, normal, reference);
	}
}
#endif
