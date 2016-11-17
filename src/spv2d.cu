#ifndef __SPV2D_CU__
#define __SPV2D_CU__

#define NVCC
#define ENABLE_CUDA
#define EPSILON 1e-12

#include <cuda_runtime.h>
#include "curand_kernel.h"
#include "gpucell.cuh"
#include "spv2d.cuh"


#include "indexer.h"
#include "gpubox.h"
#include "cu_functions.h"
#include <iostream>
#include <stdio.h>

/*
__global__ void init_curand_kernel(unsigned long seed, curandState *state)
    {
    unsigned int idx = blockIdx.x*blockDim.x + threadIdx.x;
    curand_init(seed,idx,0,&state[idx]);
    return;
    };
*/

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


#endif