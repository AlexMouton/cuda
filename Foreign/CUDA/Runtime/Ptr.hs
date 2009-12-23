--------------------------------------------------------------------------------
-- |
-- Module    : Foreign.CUDA.Runtime.Ptr
-- Copyright : (c) 2009 Trevor L. McDonell
-- License   : BSD
--
-- References to objects stored on the CUDA devices
--
--------------------------------------------------------------------------------

module Foreign.CUDA.Runtime.Ptr
  where

-- System
import Foreign.Ptr
import Foreign.Storable


--------------------------------------------------------------------------------
-- Device Pointer
--------------------------------------------------------------------------------

-- |
-- A reference to data stored on the device
--
data DevicePtr a = DevicePtr { useDevicePtr :: Ptr a }
  deriving (Eq,Ord)

instance Show (DevicePtr a) where
  showsPrec n (DevicePtr p) rs = showsPrec n p rs

instance Storable (DevicePtr a) where
  sizeOf _    = sizeOf    (undefined :: Ptr a)
  alignment _ = alignment (undefined :: Ptr a)
  peek p      = DevicePtr `fmap` peek (castPtr p)
  poke p v    = poke (castPtr p) (useDevicePtr v)


-- |
-- Look at the contents of device memory. This takes an IO action that will be
-- applied to that pointer, the result of which is returned. It would be silly
-- to return the pointer from the action.
--
withDevicePtr :: DevicePtr a -> (Ptr a -> IO b) -> IO b
withDevicePtr p f = f (useDevicePtr p)


-- |
-- The constant 'nullDevPtr' contains the distinguished memory location that is
-- not associated with a valid memory location
--
nullDevPtr :: DevicePtr a
nullDevPtr =  DevicePtr nullPtr

-- |
-- Cast a device pointer from one type to another
--
castDevPtr :: DevicePtr a -> DevicePtr b
castDevPtr (DevicePtr p) = DevicePtr (castPtr p)

-- |
-- Advance the pointer address by the given offset in bytes.
--
plusDevPtr :: DevicePtr a -> Int -> DevicePtr a
plusDevPtr (DevicePtr p) d = DevicePtr (p `plusPtr` d)

-- |
-- Given an alignment constraint, align the device pointer to the next highest
-- address satisfying the constraint
--
alignDevPtr :: DevicePtr a -> Int -> DevicePtr a
alignDevPtr (DevicePtr p) i = DevicePtr (p `alignPtr` i)

-- |
-- Compute the difference between the second and first argument. This fulfils
-- the relation
--
-- > p2 == p1 `plusDevPtr` (p2 `minusDevPtr` p1)
--
minusDevPtr :: DevicePtr a -> DevicePtr a -> Int
minusDevPtr (DevicePtr a) (DevicePtr b) = a `minusPtr` b


--------------------------------------------------------------------------------
-- Host Pointer
--------------------------------------------------------------------------------

-- |
-- A reference to page-locked host memory
--
data HostPtr a = HostPtr { useHostPtr :: Ptr a }
  deriving (Eq,Ord)

instance Show (HostPtr a) where
  showsPrec n (HostPtr p) rs = showsPrec n p rs

instance Storable (HostPtr a) where
  sizeOf _    = sizeOf    (undefined :: Ptr a)
  alignment _ = alignment (undefined :: Ptr a)
  peek p      = HostPtr `fmap` peek (castPtr p)
  poke p v    = poke (castPtr p) (useHostPtr v)


-- |
-- Apply an IO action to the memory reference living inside the host pointer
-- object. All uses of the pointer should be inside the 'withHostPtr' bracket.
--
withHostPtr :: HostPtr a -> (Ptr a -> IO b) -> IO b
withHostPtr p f = f (useHostPtr p)


-- |
-- The constant 'nullHostPtr' contains the distinguished memory location that is
-- not associated with a valid memory location
--
nullHostPtr :: HostPtr a
nullHostPtr =  HostPtr nullPtr

-- |
-- Cast a host pointer from one type to another
--
castHostPtr :: HostPtr a -> HostPtr b
castHostPtr (HostPtr p) = HostPtr (castPtr p)

-- |
-- Advance the pointer address by the given offset in bytes
--
plusHostPtr :: HostPtr a -> Int -> HostPtr a
plusHostPtr (HostPtr p) d = HostPtr (p `plusPtr` d)

-- |
-- Given an alignment constraint, align the host pointer to the next highest
-- address satisfying the constraint
--
alignHostPtr :: HostPtr a -> Int -> HostPtr a
alignHostPtr (HostPtr p) i = HostPtr (p `alignPtr` i)

-- |
-- Compute the difference between the second and first argument
--
minusHostPtr :: HostPtr a -> HostPtr a -> Int
minusHostPtr (HostPtr a) (HostPtr b) = a `minusPtr` b

