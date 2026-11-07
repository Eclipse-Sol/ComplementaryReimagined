#extension GL_ARB_gpu_shader5 : enable
#extension GL_ARB_shading_language_packing : enable

#include "/lib/voxelization/reflectionTextureMapping.glsl"

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

// Face index with no duplicates!
// Number of unique indecies 3abc + ab + bc + ca compared to 6abc,
// (where a, b, and c refer to sceneVoxelVolumeSize.x, y, and z)
int getFaceIndex(ivec3 voxelPos, vec3 normal) {
	const int offsetY = (sceneVoxelVolumeSize.x + 1) * sceneVoxelVolumeSize.y * sceneVoxelVolumeSize.z;
	const int offsetZ = (sceneVoxelVolumeSize.y + 1) * sceneVoxelVolumeSize.x * sceneVoxelVolumeSize.z + offsetY;

	if (abs(normal.x) > 0.99)
		return max(int(normal.x), 0) + voxelPos.x + voxelPos.y * (sceneVoxelVolumeSize.x + 1) +
							           			    voxelPos.z * (sceneVoxelVolumeSize.x + 1) * sceneVoxelVolumeSize.y;
	else if (abs(normal.y) > 0.99)
		return max(int(normal.y), 0) + voxelPos.y + voxelPos.x * (sceneVoxelVolumeSize.y + 1) +
									   				voxelPos.z * (sceneVoxelVolumeSize.y + 1) * sceneVoxelVolumeSize.x + offsetY;
	else
		return max(int(normal.z), 0) + voxelPos.z + voxelPos.x * (sceneVoxelVolumeSize.z + 1) +
									   				voxelPos.y * (sceneVoxelVolumeSize.z + 1) * sceneVoxelVolumeSize.x + offsetZ;
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

faceData getFaceData(ivec3 voxelPos, vec3 normal, out uint orientation) {
    faceData face = unpackReflectionFaceData(blockDataSSBO.data[getFaceIndex(voxelPos, normal)].xyz, orientation);
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
	return getCellWordIndex(getSceneVoxelIndex(voxelPos));
}

faceData getLavaFaceData(ivec3 voxelPos, out mat2 textureRotation) {
	int index = getLavaTopIndex(voxelPos);
	uint origin = blockDataSSBO.data[index].w;
	uint bits = blockDataSSBO.data[index + sceneVoxelCount].w;
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
	uint data = blockDataSSBO.data[getLavaCornerIndex(corner)].w;
	return (data & 0xfffff000u) == getReflectionFrameStamp() ? float(data & 4095u) / 4095.0 : 1.0;
}

#if defined SHADOW && defined VERTEX_SHADER
void mergeStampedWord(int index, uint payload, bool keepMax) {
	uint stamp = getReflectionFrameStamp();
	uint newData = stamp | payload;
	uint oldData = atomicAdd(blockDataSSBO.data[index].w, 0u);
	while (true) {
		uint updated = newData;
		if ((oldData & 0xfffff000u) == stamp) updated = keepMax ? max(oldData, newData) : oldData | newData;
		if (updated == oldData) break;
		uint previous = atomicCompSwap(blockDataSSBO.data[index].w, oldData, updated);
		if (previous == oldData) break;
		oldData = previous;
	}
}

void storeLavaCorner(ivec3 corner, float height) {
	mergeStampedWord(getLavaCornerIndex(corner), uint(round(height * 4095.0)), true);
}

void storeLavaFaceData(ivec3 voxelPos, vec2 origin, float textureRad, float textureRotation) {
	uvec3 uv = uvec3(clamp(round(vec3(origin, textureRad) * 65536.0), 0.0, 65535.0));
	uvec2 lightmap = uvec2(round(clamp(vec2(lmCoord.x * 0.99 + 0.001, lmCoord.y), 0.0, 1.0) * 15.0));
	uint angle = uint(round(fract(textureRotation / 6.28318530718) * 256.0)) & 255u;
	int index = getLavaTopIndex(voxelPos);
	blockDataSSBO.data[index].w = (uv.x << 16u) | uv.y;
	blockDataSSBO.data[index + sceneVoxelCount].w = uv.z | (angle << 16u) | (lightmap.x << 24u) | (lightmap.y << 28u);
}

void storeFaceData(ivec3 voxelPos, vec3 normal, vec2 origin, float textureRad, uint orientation, bool storeToAllFaces, bool storeToAllFacesExceptTop, vec3 playerPos) {
	vec2 lmCoordM = lmCoord;

	if (storeToAllFaces || storeToAllFacesExceptTop) {
		vec3 playerPosPrevious = playerPos - previousCameraPosition + cameraPosition;
		vec3 voxelPosPrevious = playerToPreviousSceneVoxel(playerPosPrevious);
		faceData oldFaceData = getFaceData(ivec3(voxelPosPrevious), normal);
		#if WORLD_SPACE_SHAPES > 0
			// block crossings would fade held light faster while moving
			float lightBlend = isReflectionPeriodicRefresh() ? 1.0 - pow(0.99, float(WSR_REFRESH_INTERVAL)) : 0.0;
		#else
			const float lightBlend = 0.01;
		#endif
		lmCoordM = mix(max(lmCoord, oldFaceData.lightmap), lmCoord, lightBlend);
	}

	uvec3 newData = packReflectionFaceData(faceData(glColor.rgb, vec2(lmCoordM.x * 0.99 + 0.001, lmCoordM.y), vec3(origin, textureRad)), orientation);

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
			if (texelFetch(wsr_sampler, ivec3(voxelPos + faceOffsets[i]), 0).r == 0u)
				blockDataSSBO.data[getFaceIndex(voxelPos, faceOffsets[i])].xyz = newData;
		}
	} else {
		blockDataSSBO.data[getFaceIndex(voxelPos, normal)].xyz = newData;
	}
}
#endif
