{-# LANGUAGE ForeignFunctionInterface #-}
--------------------------------------------------------------------------------
-- |
-- Module    : Foreign.CUDA.Driver.Marshal
-- Copyright : (c) [2009..2010] Trevor L. McDonell
-- License   : BSD
--
-- Memory management for low-level driver interface
--
--------------------------------------------------------------------------------

module Foreign.CUDA.Driver.Marshal
  (
    -- * Host Allocation
    AllocFlag(..), mallocHostArray, freeHost,

    -- * Device Allocation
    mallocArray, allocaArray, free,

    -- * Marshalling
    peekArray, peekArrayAsync, peekListArray,
    pokeArray, pokeArrayAsync, pokeListArray,
               copyArrayAsync,

    -- * Combined Allocation and Marshalling
    newListArray,  newListArrayLen,
    withListArray, withListArrayLen,

    -- * Utility
    memset, getDevicePtr,

    -- Internal
    useDeviceHandle, peekDeviceHandle
  )
  where

#include <cuda.h>
#include "cbits/stubs.h"
{# context lib="cuda" #}

-- Friends
import Foreign.CUDA.Ptr
import Foreign.CUDA.Driver.Error
import Foreign.CUDA.Driver.Stream               (Stream(..))
import Foreign.CUDA.Internal.C2HS

-- System
import Unsafe.Coerce
import Control.Applicative
import Control.Exception.Extensible

import Foreign.C
import Foreign.Ptr
import Foreign.Storable
import qualified Foreign.Marshal as F

#c
typedef enum CUmemhostalloc_option_enum {
    CU_MEMHOSTALLOC_OPTION_PORTABLE       = CU_MEMHOSTALLOC_PORTABLE,
    CU_MEMHOSTALLOC_OPTION_DEVICE_MAPPED  = CU_MEMHOSTALLOC_DEVICEMAP,
    CU_MEMHOSTALLOC_OPTION_WRITE_COMBINED = CU_MEMHOSTALLOC_WRITECOMBINED
} CUmemhostalloc_option;
#endc


--------------------------------------------------------------------------------
-- Host Allocation
--------------------------------------------------------------------------------

-- |
-- Options for host allocation
--
{# enum CUmemhostalloc_option as AllocFlag
    { underscoreToCase }
    with prefix="CU_MEMHOSTALLOC_OPTION" deriving (Eq, Show) #}

-- |
-- Allocate a section of linear memory on the host which is page-locked and
-- directly accessible from the device. The storage is sufficient to hold the
-- given number of elements of a storable type.
--
-- Note that since the amount of pageable memory is thusly reduced, overall
-- system performance may suffer. This is best used sparingly to allocate
-- staging areas for data exchange.
--
mallocHostArray :: Storable a => [AllocFlag] -> Int -> IO (HostPtr a)
mallocHostArray flags = doMalloc undefined
  where
    doMalloc :: Storable a' => a' -> Int -> IO (HostPtr a')
    doMalloc x n = resultIfOk =<< cuMemHostAlloc (n * sizeOf x) flags

{# fun unsafe cuMemHostAlloc
  { alloca'-        `HostPtr a'   peekHP*
  ,                 `Int'
  , combineBitMasks `[AllocFlag]'         } -> `Status' cToEnum #}
  where
    alloca'  = F.alloca
    peekHP p = (HostPtr . castPtr) `fmap` peek p


-- |
-- Free a section of page-locked host memory
--
freeHost :: HostPtr a -> IO ()
freeHost p = nothingIfOk =<< cuMemFreeHost p

{# fun unsafe cuMemFreeHost
  { useHP `HostPtr a' } -> `Status' cToEnum #}
  where
    useHP = castPtr . useHostPtr


--------------------------------------------------------------------------------
-- Device Allocation
--------------------------------------------------------------------------------

-- |
-- Allocate a section of linear memory on the device, and return a reference to
-- it. The memory is sufficient to hold the given number of elements of storable
-- type. It is suitably aligned for any type, and is not cleared.
--
mallocArray :: Storable a => Int -> IO (DevicePtr a)
mallocArray = doMalloc undefined
  where
    doMalloc :: Storable a' => a' -> Int -> IO (DevicePtr a')
    doMalloc x n = resultIfOk =<< cuMemAlloc (n * sizeOf x)

{# fun unsafe cuMemAlloc
  { alloca'- `DevicePtr a' peekDeviceHandle*
  ,          `Int'                           } -> `Status' cToEnum #}
  where
    alloca'  = F.alloca


-- |
-- Execute a computation on the device, passing a pointer to a temporarily
-- allocated block of memory sufficient to hold the given number of elements of
-- storable type. The memory is freed when the computation terminates (normally
-- or via an exception), so the pointer must not be used after this.
--
-- Note that kernel launches can be asynchronous, so you may want to add a
-- synchronisation point using 'sync' as part of the computation.
--
allocaArray :: Storable a => Int -> (DevicePtr a -> IO b) -> IO b
allocaArray n = bracket (mallocArray n) free


-- |
-- Release a section of device memory
--
free :: DevicePtr a -> IO ()
free dp = nothingIfOk =<< cuMemFree dp

{# fun unsafe cuMemFree
  { useDeviceHandle `DevicePtr a' } -> `Status' cToEnum #}


--------------------------------------------------------------------------------
-- Marshalling
--------------------------------------------------------------------------------

-- |
-- Copy a number of elements from the device to host memory. This is a
-- synchronous operation
--
peekArray :: Storable a => Int -> DevicePtr a -> Ptr a -> IO ()
peekArray n dptr hptr = doPeek undefined dptr
  where
    doPeek :: Storable a' => a' -> DevicePtr a' -> IO ()
    doPeek x _ = nothingIfOk =<< cuMemcpyDtoH hptr dptr (n * sizeOf x)

{# fun unsafe cuMemcpyDtoH
  { castPtr         `Ptr a'
  , useDeviceHandle `DevicePtr a'
  ,                 `Int'         } -> `Status' cToEnum #}


-- |
-- Copy memory from the device asynchronously, possibly associated with a
-- particular stream. The destination host memory must be page-locked.
--
peekArrayAsync :: Storable a => Int -> DevicePtr a -> HostPtr a -> Maybe Stream -> IO ()
peekArrayAsync n dptr hptr mst = doPeek undefined dptr
  where
    doPeek :: Storable a' => a' -> DevicePtr a' -> IO ()
    doPeek x _ =
      nothingIfOk =<< case mst of
        Nothing -> cuMemcpyDtoHAsync hptr dptr (n * sizeOf x) (Stream nullPtr)
        Just st -> cuMemcpyDtoHAsync hptr dptr (n * sizeOf x) st

{# fun unsafe cuMemcpyDtoHAsync
  { useHP           `HostPtr a'
  , useDeviceHandle `DevicePtr a'
  ,                 `Int'
  , useStream       `Stream'      } -> `Status' cToEnum #}
  where
    useHP = castPtr . useHostPtr


-- |
-- Copy a number of elements from the device into a new Haskell list. Note that
-- this requires two memory copies: firstly from the device into a heap
-- allocated array, and from there marshalled into a list.
--
peekListArray :: Storable a => Int -> DevicePtr a -> IO [a]
peekListArray n dptr =
  F.allocaArray n $ \p -> do
    peekArray   n dptr p
    F.peekArray n p


-- |
-- Copy a number of elements onto the device. This is a synchronous operation
--
pokeArray :: Storable a => Int -> Ptr a -> DevicePtr a -> IO ()
pokeArray n hptr dptr = doPoke undefined dptr
  where
    doPoke :: Storable a' => a' -> DevicePtr a' -> IO ()
    doPoke x _ = nothingIfOk =<< cuMemcpyHtoD dptr hptr (n * sizeOf x)

{# fun unsafe cuMemcpyHtoD
  { useDeviceHandle `DevicePtr a'
  , castPtr         `Ptr a'
  ,                 `Int'         } -> `Status' cToEnum #}


-- |
-- Copy memory onto the device asynchronously, possibly associated with a
-- particular stream. The source host memory must be page-locked.
--
pokeArrayAsync :: Storable a => Int -> HostPtr a -> DevicePtr a -> Maybe Stream -> IO ()
pokeArrayAsync n hptr dptr mst = dopoke undefined dptr
  where
    dopoke :: Storable a' => a' -> DevicePtr a' -> IO ()
    dopoke x _ =
      nothingIfOk =<< case mst of
        Nothing -> cuMemcpyHtoDAsync dptr hptr (n * sizeOf x) (Stream nullPtr)
        Just st -> cuMemcpyHtoDAsync dptr hptr (n * sizeOf x) st

{# fun unsafe cuMemcpyHtoDAsync
  { useDeviceHandle `DevicePtr a'
  , useHP           `HostPtr a'
  ,                 `Int'
  , useStream       `Stream'      } -> `Status' cToEnum #}
  where
    useHP = castPtr . useHostPtr


-- |
-- Write a list of storable elements into a device array. The device array must
-- be sufficiently large to hold the entire list. This requires two marshalling
-- operations.
--
pokeListArray :: Storable a => [a] -> DevicePtr a -> IO ()
pokeListArray xs dptr = F.withArrayLen xs $ \len p -> pokeArray len p dptr


-- |
-- Copy the given number of elements from the first device array (source) to the
-- second (destination). The copied areas may not overlap. This operation is
-- asynchronous with respect to the host, but will never overlap with kernel
-- execution.
--
copyArrayAsync :: Storable a => Int -> DevicePtr a -> DevicePtr a -> IO ()
copyArrayAsync n = docopy undefined
  where
    docopy :: Storable a' => a' -> DevicePtr a' -> DevicePtr a' -> IO ()
    docopy x src dst = nothingIfOk =<< cuMemcpyDtoD dst src (n * sizeOf x)

{# fun unsafe cuMemcpyDtoD
  { useDeviceHandle `DevicePtr a'
  , useDeviceHandle `DevicePtr a'
  ,                 `Int'         } -> `Status' cToEnum #}


--------------------------------------------------------------------------------
-- Combined Allocation and Marshalling
--------------------------------------------------------------------------------

-- |
-- Write a list of storable elements into a newly allocated device array,
-- returning the device pointer together with the number of elements that were
-- written. Note that this requires two memory copies: firstly from a Haskell
-- list to a heap allocated array, and from there onto the graphics device. The
-- memory should be 'free'd when no longer required.
--
newListArrayLen :: Storable a => [a] -> IO (DevicePtr a, Int)
newListArrayLen xs =
  F.withArrayLen xs                     $ \len p ->
  bracketOnError (mallocArray len) free $ \d_xs  -> do
    pokeArray len p d_xs
    return (d_xs, len)


-- |
-- Write a list of storable elements into a newly allocated device array. This
-- is 'newListArrayLen' composed with 'fst'.
--
newListArray :: Storable a => [a] -> IO (DevicePtr a)
newListArray xs = fst `fmap` newListArrayLen xs


-- |
-- Temporarily store a list of elements into a newly allocated device array. An
-- IO action is applied to to the array, the result of which is returned.
-- Similar to 'newListArray', this requires copying the data twice.
--
-- As with 'allocaArray', the memory is freed once the action completes, so you
-- should not return the pointer from the action, and be wary of asynchronous
-- kernel execution.
--
withListArray :: Storable a => [a] -> (DevicePtr a -> IO b) -> IO b
withListArray xs = withListArrayLen xs . const


-- |
-- A variant of 'withListArray' which also supplies the number of elements in
-- the array to the applied function
--
withListArrayLen :: Storable a => [a] -> (Int -> DevicePtr a -> IO b) -> IO b
withListArrayLen xs f =
  bracket (newListArrayLen xs) (free . fst) (uncurry . flip $ f)
--
-- XXX: Will this attempt to double-free the device array on error (together
-- with newListArrayLen)?
--


--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

-- |
-- Set a number of data elements to the specified value, which may be either 8-,
-- 16-, or 32-bits wide.
--
memset :: Storable a => DevicePtr a -> Int -> a -> IO ()
memset dptr n val = case sizeOf val of
    1 -> nothingIfOk =<< cuMemsetD8  dptr val n
    2 -> nothingIfOk =<< cuMemsetD16 dptr val n
    4 -> nothingIfOk =<< cuMemsetD32 dptr val n
    _ -> cudaError "can only memset 8-, 16-, and 32-bit values"

--
-- We use unsafe coerce below to reinterpret the bits of the value to memset as,
-- into the integer type required by the setting functions.
--
{# fun unsafe cuMemsetD8
  { useDeviceHandle `DevicePtr a'
  , unsafeCoerce    `a'
  ,                 `Int'         } -> `Status' cToEnum #}

{# fun unsafe cuMemsetD16
  { useDeviceHandle `DevicePtr a'
  , unsafeCoerce    `a'
  ,                 `Int'         } -> `Status' cToEnum #}

{# fun unsafe cuMemsetD32
  { useDeviceHandle `DevicePtr a'
  , unsafeCoerce    `a'
  ,                 `Int'         } -> `Status' cToEnum #}


-- |
-- Return the device pointer associated with a mapped, pinned host buffer, which
-- was allocated with the 'DeviceMapped' option by 'mallocHostArray'.
--
-- Currently, no options are supported and this must be empty.
--
getDevicePtr :: [AllocFlag] -> HostPtr a -> IO (DevicePtr a)
getDevicePtr flags hp = resultIfOk =<< cuMemHostGetDevicePointer hp flags

{# fun unsafe cuMemHostGetDevicePointer
  { alloca'-        `DevicePtr a' peekDeviceHandle*
  , useHP           `HostPtr a'
  , combineBitMasks `[AllocFlag]'                   } -> `Status' cToEnum #}
  where
    alloca'  = F.alloca
    useHP    = castPtr . useHostPtr


--------------------------------------------------------------------------------
-- Internal
--------------------------------------------------------------------------------

-- Lift an opaque handle to a typed DevicePtr representation. The driver
-- interface requires this special type for 'mallocArray' and the like, which is
-- a 32-bit value on all platforms.
--
-- Tesla architecture products (compute 1.x) support only a 32-bit address space
-- and expect pointers passed to kernels of this width, while the Fermi
-- architecture (compute 2.x) supports 64-bit wide pointers.
--
-- When interface with the driver functions, we require this special 32-bit
-- opaque type. When passing pointers to kernel functions, we must use the
-- native host pointer type. On 32-bit platforms, this distinction is
-- irrelevant. For Tesla devices executing on 64-bit host platforms, the runtime
-- will automatically squash pointers to 32-bits. Fermi architectures however
-- may use the entire bitwidth, so the 32-bit CUdeviceptr must be converted to
-- a 64-bit pointer by the application before passing to the kernel.
--
peekDeviceHandle :: Ptr {# type CUdeviceptr #} -> IO (DevicePtr a)
peekDeviceHandle p = DevicePtr . intPtrToPtr . fromIntegral <$> peek p

-- Use a device pointer as an opaque handle type
--
useDeviceHandle :: DevicePtr a -> {# type CUdeviceptr #}
useDeviceHandle = fromIntegral . ptrToIntPtr . useDevicePtr

