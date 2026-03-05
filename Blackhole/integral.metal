//
//  integral.metal
//  Blackhole
//
//  Created by 김령교 on 2/20/26.
//

#include <metal_stdlib>
using namespace metal;

#define M_PI 3.14159265358979323846f

#define BH_INCLUDE_GR_MATH 1
#include "Metal/gr_math.metal"
#undef BH_INCLUDE_GR_MATH

#define BH_INCLUDE_DISK_MODELS 1
#include "Metal/disk_models.metal"
#undef BH_INCLUDE_DISK_MODELS

#define BH_INCLUDE_VOLUME_RT 1
#include "Metal/volume_rt.metal"
#undef BH_INCLUDE_VOLUME_RT

#define BH_INCLUDE_SPECTRUM_VISIBLE 1
#include "Metal/spectrum_visible.metal"
#undef BH_INCLUDE_SPECTRUM_VISIBLE

#define BH_INCLUDE_POST_COMPOSE 1
#include "Metal/post_compose.metal"
#undef BH_INCLUDE_POST_COMPOSE
