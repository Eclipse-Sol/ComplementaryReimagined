/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

//Common//
#include "/lib/common.glsl"

//////////Shadowcomp 1//////////Shadowcomp 1//////////Shadowcomp 1//////////
#ifdef SHADOWCOMP

layout (local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
#if COLORED_LIGHTING_INTERNAL > 0
	const ivec3 workGroups = ivec3(2048, 1, 1);
#else
	const ivec3 workGroups = ivec3(1, 1, 1);
#endif

#if COLORED_LIGHTING_INTERNAL > 0

//Includes//
#include "/lib/voxelization/lightVoxelization.glsl"
#include "/lib/voxelization/actState.glsl"

//Common Variables//
writeonly uniform image3D floodfill_img;
writeonly uniform image3D floodfill_img_copy;
#ifdef ACT_BRICK_FLAGS
	layout(r16ui) uniform uimage3D actBrick_img;

	shared uint actAnyLight;
	shared uint actAnyChanged;
	shared uint actFaceChanged[6];
	shared uint actVoxelCheck;
#endif

ivec3 previousStorageOffset; // last frame's camera block, see VoxelToLightStorage

//Common Functions//
vec4 GetLightSample(sampler3D lightSampler, ivec3 pos) {
	if (any(lessThan(pos, ivec3(0))) || any(greaterThanEqual(pos, voxelVolumeSize))) return vec4(0.0);
	return texelFetch(lightSampler, VoxelToLightStorage(pos, previousStorageOffset), 0);
}

vec4 GetLightCalculated(sampler3D lightSampler, ivec3 pos, ivec3 voxelVolumeSize, uint voxel) {
	vec4 light_px = GetLightSample(lightSampler, clamp(pos + ivec3( 1,  0,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_py = GetLightSample(lightSampler, clamp(pos + ivec3( 0,  1,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_pz = GetLightSample(lightSampler, clamp(pos + ivec3( 0,  0,  1), ivec3(0), voxelVolumeSize - 1));
	vec4 light_nx = GetLightSample(lightSampler, clamp(pos + ivec3(-1,  0,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_ny = GetLightSample(lightSampler, clamp(pos + ivec3( 0, -1,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_nz = GetLightSample(lightSampler, clamp(pos + ivec3( 0,  0, -1), ivec3(0), voxelVolumeSize - 1));

	vec4 light = light_px + light_py + light_pz + light_nx + light_ny + light_nz;
    light /= 6.42; // Slightly higher than 6 to prevent the light from travelling too far

	if (voxel >= 200u) {
		vec3 tint = specialTintColor[min(voxel - 200u, specialTintColor.length() - 1u)];
		light.rgb *= tint;
		light.a *= dot(tint, vec3(0.333333));
	}

	return light;
}

// Sign bit of red in a packed floodfill texel.
const uint floodfillSolidMarker = 0x8000u;

// Writes a voxel's floodfill light, skipping the store when the bits match what the target image already holds
vec4 StoreFloodfillLightIfChanged(bool writeCopyImage, ivec3 storagePos, vec4 light, bool solid, out bool changed) {
	// 1. We round the bits. bits.x holds red and green, bits.y holds blue and alpha
	uvec2 bits = uvec2(packHalf2x16(light.xy), packHalf2x16(light.zw));

	// 2. Only solid voxels with no light carry the marker
	bits.x &= ~floodfillSolidMarker;
	bool noLight = bits == uvec2(0u);
	if (solid && noLight) bits.x = floodfillSolidMarker;
	vec4 storedLight = vec4(unpackHalf2x16(bits.x), unpackHalf2x16(bits.y));

	// 3. Store only if the bits differ from what the target image holds
	vec4 oldLight = writeCopyImage ? texelFetch(floodfill_sampler_copy, storagePos, 0) : texelFetch(floodfill_sampler, storagePos, 0);
	uvec2 oldBits = uvec2(packHalf2x16(oldLight.xy), packHalf2x16(oldLight.zw));
	changed = bits != oldBits;
	if (changed) {
		if (writeCopyImage) imageStore(floodfill_img_copy, storagePos, storedLight);
		else imageStore(floodfill_img, storagePos, storedLight);
	}
	return storedLight;
}

//Program//
void main() {
	uint brickCount = min(actState[int(framemod2)], volumeBrickCount);
	ivec3 previousMinusCurrentCamera = previousCameraPositionBestInt - cameraPositionBestInt;
	ivec3 storageOffset = GetCurrentLightStorageOffset();
	previousStorageOffset = GetLightStorageOffset(GetHistoryCameraBlock(1));
	int destLayer = 1 - int(framemod2);

	for (uint brickIndex = gl_WorkGroupID.x; brickIndex < brickCount; brickIndex += gl_NumWorkGroups.x) {
		ivec3 storageBrick = UnpackBrick(actState[actBrickListStart + brickIndex]);
		ivec3 storagePos = storageBrick * 8 + ivec3(gl_LocalInvocationID);
		ivec3 pos = LightStorageToVoxel(storagePos, storageOffset); // camera-centred
		vec3 posM = vec3(pos) / vec3(voxelVolumeSize);
		ivec3 previousPos = pos - previousMinusCurrentCamera;

		uint rawData = GetVoxelVolumeRaw(pos);
		#ifdef ACT_BRICK_FLAGS
			if (gl_LocalInvocationIndex == 0u) {
				actAnyLight = 0u;
				actAnyChanged = 0u;
				actVoxelCheck = 0u;
				for (int i = 0; i < 6; i++) actFaceChanged[i] = 0u;
			}
			barrier();
		#endif

		{
			vec4 light = vec4(0.0);
			bool behindPlayer = false;
			#ifdef OPTIMIZATION_ACT_BEHIND_PLAYER
				ivec3 absPosFromCenter = abs(pos - voxelVolumeSize / 2);
				if (absPosFromCenter.x + absPosFromCenter.y + absPosFromCenter.z > 16) {
					behindPlayer = dot(normalize(posM - 0.5), GetFloodfillViewDirection()) < 0.0;
				}
			#endif

			if (behindPlayer) {
				#ifdef COLORED_LIGHT_FOG
					if (int(framemod2) == 0) light = GetLightSample(floodfill_sampler, previousPos);
					else light = GetLightSample(floodfill_sampler_copy, previousPos);
				#endif
			} else {
				uint voxel = rawData & 32767u;
				#ifdef HAS_COLORWHEEL
					uint isColorwheelGeometry = (rawData - voxel) >> 15u;
				#endif
				#ifdef COLORED_DYNAMIC_LIGHTING
					bool isItemLight = (voxel - ITEM_LIGHT_VOXEL_OFFSET) < 200u; // voxel >= ITEM_LIGHT_VOXEL_OFFSET && voxel < ITEM_LIGHT_VOXEL_OFFSET + 200u
					if (isItemLight) voxel -= ITEM_LIGHT_VOXEL_OFFSET;

					bool isEntityLight = (voxel - ENTITY_LIGHT_VOXEL_OFFSET) < 200u; // voxel >= ENTITY_LIGHT_VOXEL_OFFSET && voxel < ENTITY_LIGHT_VOXEL_OFFSET + 200u
					if (isEntityLight) voxel -= ENTITY_LIGHT_VOXEL_OFFSET;
				#endif

				if (voxel == 1u) { // Solid Blocks
					light = vec4(0.0);
				} else if (voxel == 0u || voxel >= 200u) { // Air, Non-solids, Translucents
					if (int(framemod2) == 0) {
						#ifdef OPTIMIZATION_ACT_HALF_RATE_SPREADING
							if (posM.z > 0.5) light = GetLightSample(floodfill_sampler, previousPos);
							else
						#endif
						light = GetLightCalculated(floodfill_sampler, previousPos, voxelVolumeSize, voxel);
					} else {
						#ifdef OPTIMIZATION_ACT_HALF_RATE_SPREADING
							if (posM.z < 0.5) light = GetLightSample(floodfill_sampler_copy, previousPos);
							else
						#endif
						light = GetLightCalculated(floodfill_sampler_copy, previousPos, voxelVolumeSize, voxel);
					}
				} else { // Light Sources
					vec4 color = GetSpecialBlocklightColor(int(voxel));

					#ifdef HAS_COLORWHEEL
						/* Create does not give any lightmap data to its geometry,
						so if the geometry is from colorwheel (detection done via bit mask),
						we force the alpha of light sources to be 1.0 for our floodfill light */
						if (isColorwheelGeometry == 1u) color.a = 1.0;
					#endif
					#ifdef COLORED_DYNAMIC_LIGHTING
						/* Dropped items or entities have no vanilla lightmap without a dynamic lighting mod.
						We need to calculate an approximate lightmap value (color.a) for every light */
						if (isItemLight || isEntityLight) {
							float approxLightIntensity = pow((dot(color.rgb, vec3(0.11))), 2.75);
							color.a = max(color.a, approxLightIntensity);
						}
					#endif

					light = max(light, vec4(pow2(color.rgb), color.a));
				}

				light = clamp(light, vec4(0.0), vec4(100000.0)); // Prevents a random NaN from consuming the volume
			}

			bool changed = true;
			bool solid = (rawData & 32767u) == 1u;
			#ifdef ACT_RETAIN_BEHIND_PLAYER
				if (behindPlayer) light = vec4(1.0);
				else
			#endif
			light = StoreFloodfillLightIfChanged(int(framemod2) == 0, storagePos, light, solid, changed);

			#ifdef ACT_BRICK_FLAGS
				if (any(notEqual(light, vec4(0.0)))) {
					actAnyLight = 1u;
					bool needsVoxelCheck = solid;
					#ifdef ACT_RETAIN_BEHIND_PLAYER
						needsVoxelCheck = needsVoxelCheck || behindPlayer;
					#endif
					if (needsVoxelCheck) atomicOr(actVoxelCheck, actCheckSolidVoxels);
				}
				if (changed) {
					ivec3 local = ivec3(gl_LocalInvocationID);
					actAnyChanged = 1u;
					for (int axis = 0; axis < 3; axis++) {
						if (local[axis] == 0) actFaceChanged[2 * axis] = 1u;
						if (local[axis] == 7) actFaceChanged[2 * axis + 1] = 1u;
					}
				}
			#endif
		}
		#ifdef ACT_BRICK_FLAGS
			barrier();

			if (gl_LocalInvocationIndex == 0u) {
				uint flags = (actAnyLight * actFlagAnyLight) | (actAnyChanged * actFlagAnyChange) | actVoxelCheck;
				for (int i = 0; i < 6; i++) flags |= actFaceChanged[i] << (actFlagFaceShift + uint(i));
				imageStore(actBrick_img, GetBrickFlagTexel(storageBrick, destLayer), uvec4(flags));
			}
		#endif
	}
}

#else
void main() {}
#endif

#endif
