if (blockEntityMat < 5028) {
    if (blockEntityMat < 5012) {
        if (blockEntityMat < 5004) {
            if (blockEntityMat == 5000) { //

            } else { // blockEntityMat < 5000

            }
        } else {
            if (blockEntityMat == 5004) { // Signs
                noSmoothLighting = true;

                if (glColor.r + glColor.g + glColor.b <= 2.99 || lmCoord.x > 0.999) { // Sign Text
                    #include "/lib/materials/specificMaterials/others/signText.glsl"
                }

                #ifdef COATED_TEXTURES
                    noiseFactor = 0.66;
                #endif
            } else /*if (blockEntityMat == 5008)*/ { // Chest
                noSmoothLighting = true;

                smoothnessG = pow2(color.g);

                #ifdef COATED_TEXTURES
                    noiseFactor = 0.66;
                #endif
            }
        }
    } else {
        if (blockEntityMat < 5020) {
            if (blockEntityMat == 5012) { // Ender Chest
                noSmoothLighting = true;

                float factor = min(pow2(color.g), 0.25);
                smoothnessG = factor * 2.0;

                if (color.g > color.r || color.b > color.g)
                    emission = pow2(factor) * 20.0;
                emission += 0.35;

                #ifdef COATED_TEXTURES
                    noiseFactor = 0.66;
                #endif
            } else /*if (blockEntityMat == 5016)*/ { // Shulker Box+, Head+, Bed+
                noSmoothLighting = true;
                #ifdef COATED_TEXTURES
                    noiseFactor = 0.2;
                #endif
            }
        } else {
            if (blockEntityMat == 5020) { // Conduit
                noSmoothLighting = true;
                lmCoordM.x = 0.9;

                if (color.b > color.r) { // Conduit:Wind, Conduit:Blue Pixels of The Eye
                    emission = color.r * 16.0;
                } else if (color.r > color.b * 2.5) { // Conduit:Red Pixels of The Eye
                    emission = 20.0;
                    color.rgb *= vec3(1.0, 0.25, 0.1);
                }
            } else /*if (blockEntityMat == 5024)*/ { // End Portal, End Gateway
                #ifdef SPECIAL_PORTAL_EFFECTS
                    #include "/lib/materials/specificMaterials/others/endPortalEffect.glsl"
                #endif
            }
        }
    }
} else {
    if (blockEntityMat < 5044) {
        if (blockEntityMat < 5036) {
            if (blockEntityMat == 5028) { // Bell
                if (color.r + color.g > color.b + 0.5) { // Bell:Golden Part
                    #include "/lib/materials/specificMaterials/terrain/goldBlock.glsl"
                } else {
                    #include "/lib/materials/specificMaterials/terrain/stone.glsl"
                }
            } else /*if (blockEntityMat == 5032)*/ { // Copper Chest+, Copper Golem+
                #include "/lib/materials/specificMaterials/terrain/copperBlock.glsl"
            }
        } else {
            if (blockEntityMat == 5036) { // Banner+
                noSmoothLighting = true;
                #ifdef COATED_TEXTURES
                    noiseFactor = 0.2;
                #endif
                noGeneratedNormals = true;
            } else /*if (blockEntityMat == 5040)*/ { //

            }
        }
    } else {
        if (blockEntityMat < 5052) {
            if (blockEntityMat == 5044) { //

            } else /*if (blockEntityMat == 5048)*/ { //

            }
        } else {
            if (blockEntityMat == 5052) { //

            } else if (blockEntityMat == 10548) { // Enchanting Table:Book
                smoothnessG = pow2(color.g) * 0.35;

                if (color.b < 0.0001 && color.r > color.g) {
                    emission = color.g * 3.5;
                }
            }
        }
    }
}
