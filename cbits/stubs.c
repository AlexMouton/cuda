/*
 * Extra bits for CUDA binding
 */

#include "cbits/stubs.h"


cudaError_t
cudaConfigureCallSimple(int gx, int gy, int bx, int by, int bz, size_t sharedMem, cudaStream_t stream)
{
    dim3 gridDim  = {gx,gy,1};
    dim3 blockDim = {bx,by,bz};

    return cudaConfigureCall(gridDim, blockDim, sharedMem, stream);
}

const char*
cudaGetErrorStringWrapper(cudaError_t error)
{
    return cudaGetErrorString(error);
}

CUresult
cuTexRefSetAddress2DSimple(CUtexref tex, CUarray_format fmt, int chn, CUdeviceptr dptr, int width, int height, int pitch)
{
    CUDA_ARRAY_DESCRIPTOR desc;
    desc.Format      = fmt;
    desc.NumChannels = chn;
    desc.Width       = width;
    desc.Height      = height;

    return cuTexRefSetAddress2D(tex, &desc, dptr, pitch);
}

