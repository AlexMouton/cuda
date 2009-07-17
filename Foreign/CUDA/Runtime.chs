{-
 - Haskell bindings to the CUDA library
 -
 - This uses the higher-level "C for CUDA" interface and runtime API, which
 - itself is implemented with the lower-level driver API.
 -}

{-# LANGUAGE ForeignFunctionInterface #-}

module Foreign.CUDA.Runtime
  (
    --
    -- Device management
    --
    getDeviceCount, getDeviceProperties,

    --
    -- Memory management
    --
    cmalloc, cfree
  ) where

import Foreign.CUDA.Types
import Foreign.CUDA.Utils

import Foreign.CUDA.Internal.C2HS


#include <cuda_runtime_api.h>
{#context lib="cudart" prefix="cuda"#}

{# pointer *cudaDeviceProp as ^ foreign -> DeviceProperties nocode #}

--------------------------------------------------------------------------------
-- Device Management
--------------------------------------------------------------------------------

--
-- Returns the number of compute-capable devices
--
getDeviceCount :: IO (Either String Int)
getDeviceCount = resultIfSuccess =<< cudaGetDeviceCount

{# fun unsafe cudaGetDeviceCount
    { alloca- `Int' peekIntConv* } -> `Result' cToEnum #}

--
-- Return information about the selected compute device
--
getDeviceProperties   :: Int -> IO (Either String DeviceProperties)
getDeviceProperties n  = resultIfSuccess =<< cudaGetDeviceProperties n

{# fun unsafe cudaGetDeviceProperties
    { alloca- `DeviceProperties' peek*,
              `Int'                   } -> `Result' cToEnum #}

--------------------------------------------------------------------------------
-- Memory Management
--------------------------------------------------------------------------------

cmalloc       :: Integer -> IO (Either String DevicePtr)
cmalloc bytes  = resultIfSuccess =<< cudaMalloc bytes

{# fun unsafe cudaMalloc
    { alloca-  `DevicePtr' peek*,
      cIntConv `Integer'        } -> `Result' cToEnum #}


cfree     :: DevicePtr -> IO (Maybe String)
cfree dptr = nothingIfSuccess =<< cudaFree dptr

{# fun unsafe cudaFree
    { castPtr `DevicePtr' } -> `Result' cToEnum #}

