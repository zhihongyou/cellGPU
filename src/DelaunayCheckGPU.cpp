using namespace std;
#define dbl float
#define EPSILON 1e-12
#define ENABLE_CUDA

#include <cmath>
#include <algorithm>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <iostream>
#include <iomanip>
#include <fstream>
#include <sstream>
#include <vector>
#include <sys/time.h>

//#include "cuda.h"
#include "cuda_runtime.h"
#include "vector_types.h"
#include "vector_functions.h"

#include "gpubox.h"
#include "gpuarray.h"
#include "gpucell.cuh"
#include "gpucell.h"

#include "DelaunayCheckGPU.cuh"
#include "DelaunayCheckGPU.h"


void DelaunayTest::testTriangulation(vector<float> &points,
                        GPUArray<int> &circumcenters,
                        dbl cellsize,
                        gpubox &box,
                        GPUArray<bool> &reTriangulate)
    {
    int Np = points.size()/2;
    cellListGPU clgpu(cellsize,points,box);
    clgpu.computeGPU();

    //if(true)
    //{
    //get particle data
    ArrayHandle<float2> d_pt(clgpu.particles,access_location::device,access_mode::read);

    //get cell list arrays...
    ArrayHandle<unsigned int> d_cell_sizes(clgpu.cell_sizes,access_location::device,access_mode::read);
    ArrayHandle<int> d_idx(clgpu.idxs,access_location::device,access_mode::read);

//    ArrayHandle<bool> d_retri(reTriangulate,access_location::device,access_mode::overwrite);
    ArrayHandle<int> d_ccs(circumcenters,access_location::device,access_mode::read);
    bool run;


    bool temp[Np];
    for (int nn = 0; nn < Np; ++nn) temp[nn]=false;

    bool *bt=temp;

    run=gpu_test_circumcircles(bt,//temp.data(),//d_retri.data,
                            d_ccs.data,
                            d_pt.data,
                            d_cell_sizes.data,
                            d_idx.data,
                            Np,
                            clgpu.getXsize(),
                            clgpu.getYsize(),
                            clgpu.getBoxsize(),
                            box,
                            clgpu.cell_indexer,
                            clgpu.cell_list_indexer
                            );
    //};
    //ArrayHandle<bool> h_retri(reTriangulate,access_location::host,access_mode::read);
    //for (int nn = 0; nn < Np; ++nn)
    //   cout << nn <<"  asd  " << h_retri.data[nn] << endl;
    for (int nn = 0; nn < Np; ++nn)
       cout << nn <<"  asd  " << temp[nn] << endl;


    };

