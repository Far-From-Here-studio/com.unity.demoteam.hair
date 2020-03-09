#ifndef __HAIRSIMCOMPUTE_CONSTRAINTS__
#define __HAIRSIMCOMPUTE_CONSTRAINTS__

#include "HairSimComputeSolverBoundaries.hlsl"

// Constraints between particles with infinite mass may exhibit division by zero.
// Ideally, the application should not evaluate such constraints, as checking for
// division by zero incurs an additional cost. For generic applications where the
// mass of the particles is not known in advance, one can enable division by zero
// checks by defining CONSTRAINTS_GUARD_DIVISION_BY_ZERO before including.
//
// E.g.:
//   #define CONSTRAINTS_GUARD_DIVISION_BY_ZERO
//   #include "HairSimComputeSlverConstraints.hlsl"

#ifdef CONSTRAINTS_GUARD_DIVISION_BY_ZERO
#define GUARD(x) if (x)
#else
#define GUARD(x)
#endif

//--------------------
// constraint solvers

void SolveCollisionConstraint(
	const float3 p,
	inout float3 d)
{
	//  - - -- -- ----+
	//                |
	//             d  |
	//           .---.|
	//          p----->
	//                |
	//                :
	//                .

	float4 contact = BoundaryContact(p);
	d += contact.xyz * contact.w;
}

void SolveCollisionFrictionConstraint(
	const float friction,
	const float3 x0,
	const float3 p,
	inout float3 d)
{
	// Unified Particle Physics for Real-Time Applications
	// https://mmacklin.com/uppfrta_preprint.pdf

	/*
	
	                      x
						 /
						/
					   /
		  --------p'--/-----------
				  |  / 
				  | /
				  |/
				  ' p
				 
	*/

	BoundaryContactInfo contact = BoundaryContactTagged(p);
	d += contact.normal * contact.depth;

	if (contact.depth < 0.0)
	{
		//const float4x4 M_prev = mul(_BoundaryMatrixPrev[contact.index], _BoundaryMatrixInv[contact.index]);
		const float4x4 M_prev = _BoundaryMatrixW2PrevW[contact.index];

		float3 x_star = p + contact.normal * contact.depth;
		float3 x_delta = (x_star - x0) - (x_star - mul(M_prev, float4(x_star, 1.0)).xyz);
		float3 x_delta_tan = x_delta - dot(x_delta, contact.normal) * contact.normal;

		float norm2_delta_tan = dot(x_delta_tan, x_delta_tan);

		const float muS = friction;// for now just using the same constant here
		const float muK = friction;// ...

		if (norm2_delta_tan < muS * muS * contact.depth * contact.depth)
			d -= x_delta_tan;
		else
			d -= x_delta_tan * min(-muK * contact.depth * rsqrt(norm2_delta_tan), 1);
	}
}

void SolveDistanceConstraint(
	const float distance, const float stiffness,
	const float w0, const float w1,
	const float3 p0, const float3 p1,
	inout float3 d0, inout float3 d1)
{
	//      d0                      d1
	//    .----.                  .----.
	// p0 ------><--------------><------ p1
	//           \______________/
	//               distance

	float3 r = p1 - p0;
	float rd_inv = rsqrt(dot(r, r));

	float delta = 1.0 - (distance * rd_inv);
	float W_inv = (delta * stiffness) / (w0 + w1);

	GUARD(W_inv > 0.0)
	{
		d0 += (w0 * W_inv) * r;
		d1 -= (w1 * W_inv) * r;
	}
}

void SolveDistanceMinConstraint(
	const float distanceMin, const float stiffness,
	const float w0, const float w1,
	const float3 p0, const float3 p1,
	inout float3 d0, inout float3 d1)
{
	float3 r = p1 - p0;
	float rd_inv = rsqrt(dot(r, r));

	// if (rd < distanceMin)
	// { ... 1.0 - distanceMin / rd }
	//
	// =>
	// { ... 1.0 - max(1.0, distanceMin / rd) }

	float delta = 1.0 - max(1.0, distanceMin * rd_inv);
	float W_inv = (delta * stiffness) / (w0 + w1);

	GUARD(W_inv > 0.0)
	{
		d0 += (w0 * W_inv) * r;
		d1 -= (w1 * W_inv) * r;
	}
}

void SolveDistanceMaxConstraint(
	const float distanceMax, const float stiffness,
	const float w0, const float w1,
	const float3 p0, const float3 p1,
	inout float3 d0, inout float3 d1)
{
	float3 r = p1 - p0;
	float rd_inv = rsqrt(dot(r, r));

	// if (rd > distanceMax)
	// { ... 1.0 - distanceMax / rd }
	//
	// =>
	// { ... 1.0 - min(1.0, distanceMax / rd) }

	float delta = 1.0 - min(1.0, distanceMax * rd_inv);
	float W_inv = (delta * stiffness) / (w0 + w1);

	GUARD(W_inv > 0.0)
	{
		d0 += (w0 * W_inv) * r;
		d1 -= (w1 * W_inv) * r;
	}
}

void SolveDistanceLRAConstraint(const float distanceMax, const float3 p0, const float3 p1, inout float3 d1)
{
	//                        d1
	//                      .----.
	// p0 #----------------<------ p1
	//    \_______________/
	//       distanceMax

	float3 r = p1 - p0;
	float rd_inv = rsqrt(dot(r, r));

	r *= 1.0 - min(1.0, distanceMax * rd_inv);

	d1 -= r;
}

void SolveDistanceFTLConstraint(const float distance, const float3 p0, const float3 p1, inout float3 d1)
{
	// Fast Simulation of Inextensible Hair and Fur
	// https://matthias-research.github.io/pages/publications/FTLHairFur.pdf
	//
	//                       d1
	//                     .----.
	// p0 #--------------><------ p1
	//    \______________/
	//        distance

	float3 r = p1 - p0;
	float rd_inv = rsqrt(dot(r, r));

	r *= 1.0 - (distance * rd_inv);

	d1 -= r;
}

void SolveTriangleBendingConstraint(
	const float radius, const float stiffness,
	const float w0, const float w1, const float w2,
	const float3 p0, const float3 p1, const float3 p2,
	inout float3 d0, inout float3 d1, inout float3 d2)
{
	// A Triangle Bending Constraint Model for Position-Based Dynamics
	// http://image.diku.dk/kenny/download/kelager.niebe.ea10.pdf
	//
	//                     p1
	//                 . � : ` .
	//            . �      :      ` .
	// :     . �           c           ` .    :
	// p0 � - - - - - - - - - - - - - - - - ` p2

	float3 c = (p0 + p1 + p2) / 3.0;
	float3 r = p1 - c;
	float rd_inv = rsqrt(dot(r, r));

	float delta = 1.0 - radius * rd_inv;
	float W_inv = (2.0 * delta * stiffness) / (w0 + 2.0 * w1 + w2);

	GUARD(W_inv > 0.0)
	{
		d0 += (w0 * W_inv) * r;
		d1 -= (w1 * W_inv * 2.0) * r;
		d2 += (w2 * W_inv) * r;
	}
}

void SolveTriangleBendingMinConstraint(
	const float radiusMin, const float stiffness,
	const float w0, const float w1, const float w2,
	const float3 p0, const float3 p1, const float3 p2,
	inout float3 d0, inout float3 d1, inout float3 d2)
{
	float3 c = (p0 + p1 + p2) / 3.0;
	float3 r = p1 - c;
	float rd_inv = rsqrt(dot(r, r));

	// if (rd > radiusMin)
	// { ... 1.0 - radiusMin / rd }
	//
	// =>
	// { ... 1.0 - max(1.0, radiusMin / rd) }

	float delta = 1.0 - max(1.0, radiusMin * rd_inv);
	float W_inv = (2.0 * delta * stiffness) / (w0 + 2.0 * w1 + w2);

	GUARD(W_inv > 0.0)
	{
		d0 += (w0 * W_inv) * r;
		d1 -= (w1 * W_inv * 2.0) * r;
		d2 += (w2 * W_inv) * r;
	}
}

void SolveTriangleBendingMaxConstraint(
	const float radiusMax, const float stiffness,
	const float w0, const float w1, const float w2,
	const float3 p0, const float3 p1, const float3 p2,
	inout float3 d0, inout float3 d1, inout float3 d2)
{
	float3 c = (p0 + p1 + p2) / 3.0;
	float3 r = p1 - c;
	float rd_inv = rsqrt(dot(r, r));

	// if (rd > radiusMax)
	// { ... 1.0 - radiusMax / rd }
	//
	// =>
	// { ... 1.0 - min(1.0, radiusMax / rd) }

	float delta = 1.0 - min(1.0, radiusMax * rd_inv);
	float W_inv = (2.0 * delta * stiffness) / (w0 + 2.0 * w1 + w2);

	GUARD(W_inv > 0.0)
	{
		d0 += (w0 * W_inv) * r;
		d1 -= (w1 * W_inv * 2.0) * r;
		d2 += (w2 * W_inv) * r;
	}
}

//--------------------------------------------------
// constraint shortcuts: weight in fourth component
void SolveDistanceConstraint(
	const float distance, const float stiffness,
	const float4 p0, const float4 p1,
	inout float3 d0, inout float3 d1)
{
	SolveDistanceConstraint(distance, stiffness, p0.w, p1.w, p0.xyz, p1.xyz, d0, d1);
}

void SolveDistanceMinConstraint(
	const float distanceMin, const float stiffness,
	const float4 p0, const float4 p1,
	inout float3 d0, inout float3 d1)
{
	SolveDistanceMinConstraint(distanceMin, stiffness, p0.w, p1.w, p0.xyz, p1.xyz, d0, d1);
}

void SolveDistanceMaxConstraint(
	const float distanceMax, const float stiffness,
	const float4 p0, const float4 p1,
	inout float3 d0, inout float3 d1)
{
	SolveDistanceMaxConstraint(distanceMax, stiffness, p0.w, p1.w, p0.xyz, p1.xyz, d0, d1);
}

void SolveTriangleBendingConstraint(
	const float radius, const float stiffness,
	const float4 p0, const float4 p1, const float4 p2,
	inout float3 d0, inout float3 d1, inout float3 d2)
{
	SolveTriangleBendingConstraint(radius, stiffness, p0.w, p1.w, p2.w, p0.xyz, p1.xyz, p2.xyz, d0, d1, d2);
}

void SolveTriangleBendingMinConstraint(
	const float radiusMin, const float stiffness,
	const float4 p0, const float4 p1, const float4 p2,
	inout float3 d0, inout float3 d1, inout float3 d2)
{
	SolveTriangleBendingMinConstraint(radiusMin, stiffness, p0.w, p1.w, p2.w, p0.xyz, p1.xyz, p2.xyz, d0, d1, d2);
}

void SolveTriangleBendingMaxConstraint(
	const float radiusMax, const float stiffness,
	const float4 p0, const float4 p1, const float4 p2,
	inout float3 d0, inout float3 d1, inout float3 d2)
{
	SolveTriangleBendingMaxConstraint(radiusMax, stiffness, p0.w, p1.w, p2.w, p0.xyz, p1.xyz, p2.xyz, d0, d1, d2);
}

//------------------------------------------------------------
// constraint shortcuts: apply directly to position variables

void ApplyCollisionConstraint(inout float3 p)
{
	float3 d = 0.0;
	SolveCollisionConstraint(p, d);
	p += d;
}

void ApplyCollisionFrictionConstraint(const float friction, const float3 x0, inout float3 p)
{
	float3 d = 0.0;
	SolveCollisionFrictionConstraint(friction, x0, p, d);
	p += d;
}

void ApplyDistanceConstraint(const float distance, const float stiffness, const float w0, const float w1, inout float3 p0, inout float3 p1)
{
	float3 d0 = 0.0;
	float3 d1 = 0.0;
	SolveDistanceConstraint(distance, stiffness, w0, w1, p0, p1, d0, d1);
	p0 += d0;
	p1 += d1;
}

void ApplyDistanceMinConstraint(const float distanceMin, const float stiffness, const float w0, const float w1, inout float3 p0, inout float3 p1)
{
	float3 d0 = 0.0;
	float3 d1 = 0.0;
	SolveDistanceMinConstraint(distanceMin, stiffness, w0, w1, p0, p1, d0, d1);
	p0 += d0;
	p1 += d1;
}

void ApplyDistanceMaxConstraint(const float distanceMax, const float stiffness, const float w0, const float w1, inout float3 p0, inout float3 p1)
{
	float3 d0 = 0.0;
	float3 d1 = 0.0;
	SolveDistanceMaxConstraint(distanceMax, stiffness, w0, w1, p0, p1, d0, d1);
	p0 += d0;
	p1 += d1;
}

void ApplyDistanceLRAConstraint(const float distanceMax, const float3 p0, inout float3 p1)
{
	float3 d1 = 0.0;
	SolveDistanceLRAConstraint(distanceMax, p0, p1, d1);
	p1 += d1;
}

void ApplyDistanceFTLConstraint(const float distance, const float3 p0, inout float3 p1)
{
	float3 d1 = 0.0;
	SolveDistanceFTLConstraint(distance, p0, p1, d1);
	p1 += d1;
}

void ApplyDistanceFTLConstraint(const float distance, const float3 p0, inout float3 p1, inout float3 d1)
{
	SolveDistanceFTLConstraint(distance, p0, p1, d1);
	p1 += d1;
}

void ApplyTriangleBendingConstraint(
	const float radius, const float stiffness,
	const float w0, const float w1, const float w2,
	inout float3 p0, inout float3 p1, inout float3 p2)
{
	float3 d0 = 0.0;
	float3 d1 = 0.0;
	float3 d2 = 0.0;
	SolveTriangleBendingConstraint(radius, stiffness, w0, w1, w2, p0, p1, p2, d0, d1, d2);
	p0 += d0;
	p1 += d1;
	p2 += d2;
}

void ApplyTriangleBendingMinConstraint(
	const float radiusMin, const float stiffness,
	const float w0, const float w1, const float w2,
	inout float3 p0, inout float3 p1, inout float3 p2)
{
	float3 d0 = 0.0;
	float3 d1 = 0.0;
	float3 d2 = 0.0;
	SolveTriangleBendingMinConstraint(radiusMin, stiffness, w0, w1, w2, p0, p1, p2, d0, d1, d2);
	p0 += d0;
	p1 += d1;
	p2 += d2;
}

void ApplyTriangleBendingMaxConstraint(
	const float radiusMax, const float stiffness,
	const float w0, const float w1, const float w2,
	inout float3 p0, inout float3 p1, inout float3 p2)
{
	float3 d0 = 0.0;
	float3 d1 = 0.0;
	float3 d2 = 0.0;
	SolveTriangleBendingMaxConstraint(radiusMax, stiffness, w0, w1, w2, p0, p1, p2, d0, d1, d2);
	p0 += d0;
	p1 += d1;
	p2 += d2;
}

#endif//__HAIRSIMCOMPUTE_CONSTRAINTS__
