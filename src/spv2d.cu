#ifndef __SPV2D_CU__
#define __SPV2D_CU__

#define NVCC
#define ENABLE_CUDA
#define EPSILON 1e-12
#define THRESHOLD 1e-8

#include <cuda_runtime.h>
#include "curand_kernel.h"
#include "gpucell.cuh"
#include "spv2d.cuh"

#include "indexer.h"
#include "gpubox.h"
#include "cu_functions.h"
#include <iostream>
#include <stdio.h>
#include "Matrix.h"

/*
__global__ void init_curand_kernel(unsigned long seed, curandState *state)
    {
    unsigned int idx = blockIdx.x*blockDim.x + threadIdx.x;
    curand_init(seed,idx,0,&state[idx]);
    return;
    };
*/


__global__ void gpu_force_sets_kernel(float2      *d_points,
                                          int     *d_nn,
                                          float2  *d_AP,
                                          float2  *d_APpref,
                                          int4    *d_delSets,
                                          int     *d_delOther,
                                          float2  *d_forceSets,
                                          float   KA,
                                          float   KP,
                                          int     computations,
                                          int     neighMax,
                                          Index2D n_idx,
                                          gpubox Box
                                        )
    {
    unsigned int tidx = blockDim.x * blockIdx.x + threadIdx.x;
    if (tidx >= computations)
        return;
    //which particle are we evaluating, and which neighbor
    int pidx = tidx / neighMax;
    int nn = tidx - pidx*neighMax;
    //how many neighbors does it have?
    int pNeighbors = d_nn[pidx];

    if(nn >=pNeighbors)
        return;
    //Great...access the four Delaunay neighbors and the relevant fifth point
    float2 pi   = d_points[pidx];

    int4 neighs = d_delSets[n_idx(nn,pidx)];
    float2 pnm2,rij, rik,pn2,pno;
//if(true)    printf("tidx:%i,   pidx:%i,   nm %i,  %i %i %i %i \n",tidx,pidx,neighMax,neighs.x,neighs.y,neighs.z,neighs.w);

    Box.minDist(d_points[neighs.x],pi,pnm2);
    Box.minDist(d_points[neighs.y],pi,rij);
    Box.minDist(d_points[neighs.z],pi,rik);
    Box.minDist(d_points[neighs.w],pi,pn2);
    Box.minDist(d_points[d_delOther[n_idx(nn,pidx)]],pi,pno);

    //first, compute the derivative of the main voro point w/r/t pidx's position
    //pnm1 is rij, pn1 is rik
    Matrix2x2 dhdr;
    Matrix2x2 Id;
    float2 rjk;
    rjk.x =rik.x-rij.x;
    rjk.y =rik.y-rij.y;
    float2 dbDdri,dgDdri,dDdriOD,z;
    float betaD = -dot(rik,rik)*dot(rij,rjk);
    float gammaD = dot(rij,rij)*dot(rik,rjk);
    float cp = rij.x*rjk.y - rij.y*rjk.x;
    float D = 2*cp*cp;
    z.x = betaD*rij.x+gammaD*rik.x;
    z.y = betaD*rij.y+gammaD*rik.y;

    dbDdri.x = 2*dot(rij,rjk)*rik.x+dot(rik,rik)*rjk.x;
    dbDdri.y = 2*dot(rij,rjk)*rik.y+dot(rik,rik)*rjk.y;

    dgDdri.x = -2*dot(rik,rjk)*rij.x-dot(rij,rij)*rjk.x;
    dgDdri.y = -2*dot(rik,rjk)*rij.y-dot(rij,rij)*rjk.y;

    dDdriOD.x = (-2.0*rjk.y)/cp;
    dDdriOD.y = (2.0*rjk.x)/cp;

    dhdr = Id+1.0/D*(dyad(rij,dbDdri)+dyad(rik,dgDdri)-(betaD+gammaD)*Id-dyad(z,dDdriOD));



    //finally, compute all of the forces
    float2 origin; origin.x = 0.0;origin.y=0.0;
    float2 vlast,vcur,vnext,vother;
    Circumcenter(origin,pn2,rij,vlast);
    Circumcenter(origin,rij,rik,vcur);
    Circumcenter(origin,rik,pn2,vnext);
    Circumcenter(rij,rik,pno,vother);


    float2 dEidv,dAidv,dPidv;
    float2 dEjdv,dAjdv,dPjdv;
    float2 dEkdv,dAkdv,dPkdv;
    float2 dlast, dnext;
    float  dlnorm,dnnorm;

    //self terms
    dAidv.x = 0.5*(vlast.y-vnext.y);
    dAidv.y = 0.5*(vnext.x-vlast.x);
    dlast.x = vlast.x-vcur.x;
    dlast.y=vlast.y-vcur.y;
    dlnorm = sqrt(dlast.x*dlast.x+dlast.y*dlast.y);
    dnext.x = vcur.x-vnext.x;
    dnext.y = vcur.y-vnext.y;
    dnnorm = sqrt(dnext.x*dnext.x+dnext.y*dnext.y);
    if(dnnorm < THRESHOLD)
        dnnorm = THRESHOLD;
    if(dlnorm < THRESHOLD)
        dlnorm = THRESHOLD;
    dPidv.x = dlast.x/dlnorm - dnext.x/dnnorm;
    dPidv.y = dlast.y/dlnorm - dnext.y/dnnorm;

    //other terms...k first...
    dAkdv.x = 0.5*(vnext.y-vother.y);
    dAkdv.y = 0.5*(vother.x-vnext.x);
    dlast.x = vnext.x-vcur.x;
    dlast.y=vnext.y-vcur.y;
    dlnorm = sqrt(dlast.x*dlast.x+dlast.y*dlast.y);
    dnext.x = vcur.x-vother.x;
    dnext.y = vcur.y-vother.y;
    dnnorm = sqrt(dnext.x*dnext.x+dnext.y*dnext.y);
    if(dnnorm < THRESHOLD)
        dnnorm = THRESHOLD;
    if(dlnorm < THRESHOLD)
        dlnorm = THRESHOLD;
    dPkdv.x = dlast.x/dlnorm - dnext.x/dnnorm;
    dPkdv.y = dlast.y/dlnorm - dnext.y/dnnorm;

    //...and then j
    dAjdv.x = 0.5*(vother.y-vlast.y);
    dAjdv.y = 0.5*(vlast.x-vother.x);
    dlast.x = vother.x-vcur.x;
    dlast.y=vother.y-vcur.y;
    dlnorm = sqrt(dlast.x*dlast.x+dlast.y*dlast.y);
    dnext.x = vcur.x-vlast.x;
    dnext.y = vcur.y-vlast.y;
    dnnorm = sqrt(dnext.x*dnext.x+dnext.y*dnext.y);
    if(dnnorm < THRESHOLD)
        dnnorm = THRESHOLD;
    if(dlnorm < THRESHOLD)
        dlnorm = THRESHOLD;
    dPjdv.x = dlast.x/dlnorm - dnext.x/dnnorm;
    dPjdv.y = dlast.y/dlnorm - dnext.y/dnnorm;


    return;
    };





__global__ void gpu_compute_geometry_kernel(float2 *d_points,
                                          float2 *d_AP,
                                          float2 *d_voro,
                                          int *d_nn,
                                          int *d_n,
                                          int N,
                                          Index2D n_idx,
                                          gpubox Box
                                        )
    {
    // read in the particle that belongs to this thread
    unsigned int idx = blockDim.x * blockIdx.x + threadIdx.x;
    if (idx >= N)
        return;

    float2 circumcenter, origin, nnextp, nlastp,pi,rij,rik,vlast,vnext,vfirst;
    origin.x=0.0;origin.y=0.0;
    int neigh = d_nn[idx];
    float Varea = 0.0;
    float Vperi= 0.0;

    pi = d_points[idx];
    nlastp = d_points[ d_n[n_idx(neigh-1,idx)] ];
    nnextp = d_points[ d_n[n_idx(0,idx)] ];
    Box.minDist(nlastp,pi,rij);
    Box.minDist(nnextp,pi,rik);
    Circumcenter(origin,rij,rik,circumcenter);
    vfirst = circumcenter;
    vlast = circumcenter;
    d_voro[n_idx(0,idx)] = vlast;

    for (int nn = 1; nn < neigh; ++nn)
        {
        rij = rik;
        int nid = d_n[n_idx(nn,idx)];
        nnextp = d_points[ nid ];
        Box.minDist(nnextp,pi,rik);
        Circumcenter(origin,rij,rik,circumcenter);
        vnext = circumcenter;
        d_voro[n_idx(nn,idx)] = circumcenter;

        Varea += TriangleArea(vlast,vnext);
        float dx = vlast.x - vnext.x;
        float dy = vlast.y - vnext.y;
        Vperi += sqrt(dx*dx+dy*dy);
        vlast=vnext;
        };
    Varea += TriangleArea(vlast,vfirst);
    float dx = vlast.x - vfirst.x;
    float dy = vlast.y - vfirst.y;
    Vperi += sqrt(dx*dx+dy*dy);

    d_AP[idx].x=Varea;
    d_AP[idx].y=Vperi;

    return;
    };



__global__ void gpu_displace_and_rotate_kernel(float2 *d_points,
                                          float2 *d_force,
                                          float *d_directors,
                                          int N,
                                          float dt,
                                          float Dr,
                                          float v0,
                                          int seed,
//                                          curandState *states,
                                          gpubox Box
                                         )
    {
    // read in the particle that belongs to this thread
    unsigned int idx = blockDim.x * blockIdx.x + threadIdx.x;
    if (idx >= N)
        return;

    curandState_t randState;
    curand_init(seed,//seed first
                0,   // sequence -- only important for multiple cores
                0,   //offset. advance by sequence by 1 plus this value
                &randState);

    float dirx = cosf(d_directors[idx]);
    float diry = sinf(d_directors[idx]);
    //float angleDiff = curand_normal(&states[idx])*sqrt(2.0*dt*Dr);
    float angleDiff = curand_normal(&randState)*sqrt(2.0*dt*Dr);
    d_directors[idx] += angleDiff;

 //   float dx = dt*(v0*dirx + d_force[idx].x);
//if (idx == 0) printf("x-displacement = %e\n",dx);
    d_points[idx].x += dt*(v0*dirx + d_force[idx].x);
    d_points[idx].y += dt*(v0*diry + d_force[idx].y);
    Box.putInBoxReal(d_points[idx]);
    return;
    };


//////////////
//kernel callers
//



/*
bool gpu_init_curand(curandState *states,
                    unsigned long seed,
                    int N)
    {
    unsigned int block_size = 128;
    if (N < 128) block_size = 32;
    unsigned int nblocks  = N/block_size + 1;


    cudaMalloc((void **)&states,nblocks*block_size*sizeof(curandState) );
    init_curand_kernel<<<nblocks,block_size>>>(seed,states);
    return cudaSuccess;
    };
*/


bool gpu_compute_geometry(float2 *d_points,
                        float2   *d_AP,
                        float2   *d_voro,
                        int      *d_nn,
                        int      *d_n,
                        int      N,
                        Index2D  &n_idx,
                        gpubox &Box
                        )
    {
    cudaError_t code;
    unsigned int block_size = 128;
    if (N < 128) block_size = 32;
    unsigned int nblocks  = N/block_size + 1;

    gpu_compute_geometry_kernel<<<nblocks,block_size>>>(
                                                d_points,
                                                d_AP,
                                                d_voro,
                                                d_nn,
                                                d_n,
                                                N,
                                                n_idx,
                                                Box
                                                );

    code = cudaGetLastError();
    if(code!=cudaSuccess)
    printf("compute geometry GPUassert: %s \n", cudaGetErrorString(code));

    return cudaSuccess;
    };


bool gpu_displace_and_rotate(float2 *d_points,
                        float2 *d_force,
                        float  *d_directors,
                        int N,
                        float dt,
                        float Dr,
                        float v0,
                        int seed,
  //                      curandState *states,
                        gpubox &Box
                        )
    {
    cudaError_t code;
    unsigned int block_size = 128;
    if (N < 128) block_size = 32;
    unsigned int nblocks  = N/block_size + 1;

    gpu_displace_and_rotate_kernel<<<nblocks,block_size>>>(
                                                d_points,
                                                d_force,
                                                d_directors,
                                                N,
                                                dt,
                                                Dr,
                                                v0,
                                                seed,
    //                                            states,
                                                Box
                                                );
    code = cudaGetLastError();
    if(code!=cudaSuccess)
    printf("displaceAndRotate GPUassert: %s \n", cudaGetErrorString(code));

    return cudaSuccess;
    };

bool gpu_force_sets(float2 *d_points,
                    int    *d_nn,
                    float2 *d_AP,
                    float2 *d_APpref,
                    int4   *d_delSets,
                    int    *d_delOther,
                    float2 *d_forceSets,
                    float  KA,
                    float  KP,
                    int    N,
                    int    neighMax,
                    Index2D &n_idx,
                    gpubox &Box
                    )
    {
    cudaError_t code;

    int computations = N*neighMax;
    unsigned int block_size = 128;
    if (computations < 128) block_size = 32;
    unsigned int nblocks  = computations/block_size + 1;

    gpu_force_sets_kernel<<<nblocks,block_size>>>(
                                                d_points,
                                                d_nn,
                                                d_AP,
                                                d_APpref,
                                                d_delSets,
                                                d_delOther,
                                                d_forceSets,
                                                KA,
                                                KP,
                                                computations,
                                                neighMax,
                                                n_idx,
                                                Box
                                                );
    code = cudaGetLastError();
    if(code!=cudaSuccess)
    printf("forceSets GPUassert: %s \n", cudaGetErrorString(code));

    return cudaSuccess;
    };

#endif
