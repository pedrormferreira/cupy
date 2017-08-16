import os
import warnings

from cupy import cuda

from cupy.cuda cimport function
from cupy.cuda cimport runtime


cdef struct _CArray:
    void* data
    Py_ssize_t size
    Py_ssize_t shape_and_strides[MAX_NDIM * 2]


cdef class CArray(CPointer):

    cdef:
        _CArray val

    def __init__(self, ndarray arr):
        cdef Py_ssize_t i
        cdef int ndim = arr._shape.size()
        self.val.data = <void*>arr.data.ptr
        self.val.size = arr.size
        for i in range(ndim):
            self.val.shape_and_strides[i] = arr._shape[i]
            self.val.shape_and_strides[i + ndim] = arr._strides[i]
        self.ptr = <void*>&self.val


cdef struct _CIndexer:
    Py_ssize_t size
    Py_ssize_t shape_and_index[MAX_NDIM * 2]


cdef class CIndexer(CPointer):
    cdef:
        _CIndexer val

    def __init__(self, Py_ssize_t size, tuple shape):
        self.val.size = size
        cdef Py_ssize_t i
        for i in range(len(shape)):
            self.val.shape_and_index[i] = shape[i]
        self.ptr = <void*>&self.val


cdef class Indexer:
    def __init__(self, tuple shape):
        cdef Py_ssize_t size = 1
        for s in shape:
            size *= s
        self.shape = shape
        self.size = size

    @property
    def ndim(self):
        return len(self.shape)

    cdef CPointer get_pointer(self):
        return CIndexer(self.size, self.shape)


cdef list _cupy_header_list = [
    'cupy/carray.cuh',
]
cdef str _cupy_header = ''.join(
    ['#include <%s>\n' % i for i in _cupy_header_list])

cdef str _header_path_cache = None
cdef str _header_source = None


cpdef str _get_header_dir_path():
    global _header_path_cache
    if _header_path_cache is None:
        # Cython cannot use __file__ in global scope
        _header_path_cache = os.path.abspath(
            os.path.join(os.path.dirname(__file__), 'include'))
    return _header_path_cache


cpdef str _get_header_source():
    global _header_source
    if _header_source is None:
        source = []
        base_path = _get_header_dir_path()
        for file_path in _cupy_header_list:
            header_path = os.path.join(base_path, file_path)
            with open(header_path) as header_file:
                source.append(header_file.read())
        _header_source = '\n'.join(source)
    return _header_source


cpdef function.Module compile_with_cache(
        str source, tuple options=(), arch=None, cachd_dir=None):
    source = _cupy_header + source
    extra_source = _get_header_source()
    options += ('-I%s' % _get_header_dir_path(),)

    # The variable _cuda_runtime_version is declared in cupy/core/core.pyx,
    # but it might not have been set appropriately before coming here.
    global _cuda_runtime_version
    if _cuda_runtime_version is None:
        _cuda_runtime_version = runtime.runtimeGetVersion()

    if _cuda_runtime_version >= 9000:
        cuda_path = os.getenv('CUDA_PATH', None)
        if cuda_path is None:
            warnings.warn('Please set the CUDA path ' +
                          'to environment variable `CUDA_PATH`')
        else:
            path = os.path.join(cuda_path, 'include')
            options += ('-I ' + path,)

    return cuda.compile_with_cache(source, options, arch, cachd_dir,
                                   extra_source)
