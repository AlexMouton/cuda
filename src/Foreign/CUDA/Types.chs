{-# LANGUAGE BangPatterns   #-}
{-# LANGUAGE CPP            #-}
{-# LANGUAGE EmptyDataDecls #-}
#ifdef USE_EMPTY_CASE
{-# LANGUAGE EmptyCase      #-}
#endif
--------------------------------------------------------------------------------
-- |
-- Module    : Foreign.CUDA.Types
-- Copyright : [2009..2017] Trevor L. McDonell
-- License   : BSD
--
-- Data types that are equivalent and can be shared freely between the CUDA
-- Runtime and Driver APIs.
--
--------------------------------------------------------------------------------

module Foreign.CUDA.Types (

  -- * Pointers
  DevicePtr(..), HostPtr(..),

  -- * Events
  Event(..), EventFlag(..), WaitFlag,

  -- * Streams
  Stream(..), StreamFlag(..), StreamPriority,
  defaultStream,

) where

-- system
import Foreign.Ptr
import Foreign.Storable

#include "cbits/stubs.h"
{# context lib="cuda" #}


--------------------------------------------------------------------------------
-- Data pointers
--------------------------------------------------------------------------------

-- |
-- A reference to data stored on the device.
--
newtype DevicePtr a = DevicePtr { useDevicePtr :: Ptr a }
  deriving (Eq,Ord)

instance Show (DevicePtr a) where
  showsPrec n (DevicePtr p) = showsPrec n p

instance Storable (DevicePtr a) where
  sizeOf _    = sizeOf    (undefined :: Ptr a)
  alignment _ = alignment (undefined :: Ptr a)
  peek p      = DevicePtr `fmap` peek (castPtr p)
  poke p v    = poke (castPtr p) (useDevicePtr v)


-- |
-- A reference to page-locked host memory.
--
-- A 'HostPtr' is just a plain 'Ptr', but the memory has been allocated by CUDA
-- into page locked memory. This means that the data can be copied to the GPU
-- via DMA (direct memory access). Note that the use of the system function
-- `mlock` is not sufficient here --- the CUDA version ensures that the
-- /physical/ address stays this same, not just the virtual address.
--
-- To copy data into a 'HostPtr' array, you may use for example 'withHostPtr'
-- together with 'Foreign.Marshal.Array.copyArray' or
-- 'Foreign.Marshal.Array.moveArray'.
--
newtype HostPtr a = HostPtr { useHostPtr :: Ptr a }
  deriving (Eq,Ord)

instance Show (HostPtr a) where
  showsPrec n (HostPtr p) = showsPrec n p

instance Storable (HostPtr a) where
  sizeOf _    = sizeOf    (undefined :: Ptr a)
  alignment _ = alignment (undefined :: Ptr a)
  peek p      = HostPtr `fmap` peek (castPtr p)
  poke p v    = poke (castPtr p) (useHostPtr v)


--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- |
-- Events are markers that can be inserted into the CUDA execution stream and
-- later queried.
--
newtype Event = Event { useEvent :: {# type CUevent #}}
  deriving (Eq, Show)

-- |
-- Event creation flags
--
{# enum CUevent_flags as EventFlag
    { underscoreToCase
    , CU_EVENT_DEFAULT as EventDefault
    }
    with prefix="CU_EVENT" deriving (Eq, Show, Bounded) #}

-- |
-- Possible option flags for waiting for events
--
data WaitFlag
instance Enum WaitFlag where
#ifdef USE_EMPTY_CASE
  toEnum   x = error ("WaitFlag.toEnum: Cannot match " ++ show x)
  fromEnum x = case x of {}
#endif


--------------------------------------------------------------------------------
-- Stream management
--------------------------------------------------------------------------------

-- |
-- A processing stream. All operations in a stream are synchronous and executed
-- in sequence, but operations in different non-default streams may happen
-- out-of-order or concurrently with one another.
--
-- Use 'Event's to synchronise operations between streams.
--
newtype Stream = Stream { useStream :: {# type CUstream #}}
  deriving (Eq, Show)


-- |
-- Priority of an execution stream. Work submitted to a higher priority
-- stream may preempt execution of work already executing in a lower
-- priority stream. Lower numbers represent higher priorities.
--
type StreamPriority = Int

-- |
-- Execution stream creation flags
--
#if CUDA_VERSION < 7500
data StreamFlag
instance Enum StreamFlag where
#ifdef USE_EMPTY_CASE
  toEnum   x = error ("StreamFlag.toEnum: Cannot match " ++ show x)
  fromEnum x = case x of {}
#endif
#else
{# enum CUstream_flags as StreamFlag
  { underscoreToCase
  , CU_STREAM_DEFAULT as StreamDefault
  }
  with prefix="CU_STREAM" deriving (Eq, Show, Bounded) #}
#endif


-- |
-- The main execution stream. No operations overlap with operations in the
-- default stream.
--
{-# INLINE defaultStream #-}
defaultStream :: Stream
defaultStream = Stream nullPtr

