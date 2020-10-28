#ifndef __HAIRSIMVERTEX_HLSL__
#define __HAIRSIMVERTEX_HLSL__

#include "HairSimData.hlsl"
#include "HairSimDebugDrawUtility.hlsl"

void HairSimVertex_float(in float3 inPositionOS, in float2 inUV, out float3 outPositionOS, out float3 outDebugColor)
{
	const int strandParticleIndex = (int)inUV.x;
	const int strandIndex = (int)inUV.y;

#if HAIRSIMVERTEX_ENABLE_POSITION
	outPositionOS = TransformWorldToObject(GetCameraRelativePositionWS(_ParticlePosition[strandParticleIndex].xyz));
#else
	outPositionOS = inPositionOS;
#endif

	outDebugColor = ColorCycle(strandIndex, _StrandCount);
}

#endif//__HAIRSIMVERTEX_HLSL__