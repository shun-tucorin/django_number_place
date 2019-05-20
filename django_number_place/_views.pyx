# -*- coding: utf-8 -*-

cimport cython
from cpython.bytes \
    cimport PyBytes_AS_STRING
from cpython.int \
    cimport PyInt_AsSsize_t
from cpython.list \
    cimport PyList_Append, PyList_AsTuple
from cpython.number \
  cimport PyNumber_Int
from cpython.object \
  cimport Py_SIZE
from cpython.ref \
    cimport Py_INCREF
from cpython.set \
    cimport PySet_Add, PySet_Clear
from cpython.tuple \
    cimport PyTuple_GET_ITEM, PyTuple_New, PyTuple_SET_ITEM
from cpython.unicode \
    cimport PyUnicode_DecodeASCII
from libc.stdint \
    cimport uint16_t
from libc.string \
    cimport memcmp, memcpy

cdef extern from "<x86intrin.h>" nogil:
    int __builtin_popcount(unsigned int value)
    int __builtin_ffs(int value)


cdef enum:
    NUMBER_MASK     = 0x01ff
    NUMBER_ERROR    = 0x0200
    NUMBER_FIXED    = 0x0400
    NUMBER_SUBST    = 0x0800

    RESULT_CHANGED  = 0x1
    RESULT_FAILED   = 0x2

    MAX_SUBST       = 4


@cython.auto_pickle(False)
@cython.final
cdef class ItemNumbersIter:
    cdef Py_ssize_t index_0
    cdef Py_ssize_t mask_0

    def __getitem__(self, key):
        cdef Py_ssize_t index_0
        cdef Py_ssize_t index_1 = PyInt_AsSsize_t(PyNumber_Int(key))
        if index_1 < 0:
            index_1 += __builtin_popcount(index_1)
            if index_1 < 0:
                raise IndexError()
        index_0 = __builtin_ffs(self.mask_0)
        while index_1 > 0:
            index_1 -= 1
            if index_0 == 0:
                raise IndexError()
            index_0 = __builtin_ffs(self.mask_0 & ~((1 << index_0) - 1))
        if index_0 == 0:
            raise IndexError()
        return index_0

    def __iter__(self):
        return self

    def __len__(self):
        return __builtin_popcount(self.mask_0)

    def __next__(self):
        cdef Py_ssize_t index_0 = __builtin_ffs(self.mask_0 & ~((1 << self.index_0) - 1))
        if index_0 > 0:
            self.index_0 = index_0
            return index_0
        raise StopIteration()


@cython.auto_pickle(False)
@cython.final
cdef class Item:
    cdef Py_ssize_t mask_0

    @property
    def is_fixed(self):
        if (self.mask_0 & NUMBER_FIXED) != 0:
            return True
        return False

    @property
    def is_error(self):
        if (self.mask_0 & NUMBER_ERROR) != 0:
            return True
        return False

    @property
    def is_subst(self):
        if (self.mask_0 & NUMBER_SUBST) != 0:
            return True
        return False

    @property
    def popcount(self):
        return __builtin_popcount(self.mask_0 & NUMBER_MASK)

    @property
    def numbers(self):
        cdef object result = ItemNumbersIter()
        (<ItemNumbersIter>result).mask_0 = (self.mask_0 & NUMBER_MASK)
        return result


@cython.auto_pickle(False)
@cython.final
cdef class Indexes:
    cdef Py_ssize_t ob_items[9]

    cdef Py_ssize_t contains(self, Py_ssize_t index_0) except -1:
        cdef Py_ssize_t index_1
        for index_1 in range(9):
            if self.ob_items[index_1] == index_0:
                return 1
        return 0

    def __repr__(self):
        return '(%d,%d,%d,%d,%d,%d,%d,%d,%d)' % (
                self.ob_items[0],
                self.ob_items[1],
                self.ob_items[2],
                self.ob_items[3],
                self.ob_items[4],
                self.ob_items[5],
                self.ob_items[6],
                self.ob_items[7],
                self.ob_items[8])


@cython.auto_pickle(False)
@cython.final
cdef class NumbersIter:
    cdef object parent
    cdef Py_ssize_t index_0

    def __next__(self):
        cdef Py_ssize_t index_0 = self.index_0
        cdef Py_ssize_t mask_0
        cdef object result
        if index_0 < (<Numbers>self.parent).ob_size:
            self.index_0 = index_0 + 1
            result = Item()
            mask_0 = (<Numbers>self.parent).ob_items[index_0]
            if (mask_0 & NUMBER_MASK) == 0:
                mask_0 |= NUMBER_ERROR
            (<Item>result).mask_0 = mask_0
            return result
        raise StopIteration()

    def __iter__(self):
        return self


@cython.auto_pickle(False)
cdef class Numbers:
    cdef Py_ssize_t ob_size
    cdef uint16_t ob_items[81]

    cdef object copy(self):
        cdef object result = new_numbers(self.ob_size)
        memcpy((<Numbers>result).ob_items, self.ob_items, sizeof(self.ob_items[0]) * self.ob_size)
        return result

    cdef Py_ssize_t do_check(self, object indexes) except -1:
        cdef Py_ssize_t result = 0
        cdef Py_ssize_t index_0
        cdef Py_ssize_t index_1
        cdef Py_ssize_t mask_0
        cdef Py_ssize_t mask_1
        for index_0 in range(9):
            index_0 = (<Indexes>indexes).ob_items[index_0]
            mask_0 = self.ob_items[index_0]
            if (mask_0 & NUMBER_MASK) == 0:
                self.ob_items[index_0] = <uint16_t>(mask_0 | NUMBER_ERROR)
                result = RESULT_FAILED
            elif __builtin_popcount(mask_0 & NUMBER_MASK) == 1:
                for index_1 in range(9):
                    index_1 = (<Indexes>indexes).ob_items[index_1]
                    if index_0 != index_1:
                        mask_1 = self.ob_items[index_1]
                        if (mask_1 & NUMBER_MASK) == (mask_0 & NUMBER_MASK):
                            # error: duplicate value
                            self.ob_items[index_0] = <uint16_t>(mask_0 | NUMBER_ERROR)
                            self.ob_items[index_1] = <uint16_t>(mask_1 | NUMBER_ERROR)
                            result = RESULT_FAILED
        return result

    cdef object do_solve(self, object outputs, object indexes):
        cdef Py_ssize_t index_0
        cdef Py_ssize_t mask_0
        cdef Py_ssize_t mask_1
        cdef Py_ssize_t checked_mask = 0
        cdef Py_ssize_t include_indexes
        cdef Py_ssize_t remain_indexes = 0
        # remove checking fixed numbers
        for index_0 in range(9):
            mask_0 = self.ob_items[(<Indexes>indexes).ob_items[index_0]] & NUMBER_MASK
            if __builtin_popcount(mask_0) == 1:
                checked_mask |= mask_0
            else:
                remain_indexes |= (1 << index_0)
        if checked_mask != NUMBER_MASK:
            if checked_mask != 0:
                mask_1 = remain_indexes
                mask_0 = ~checked_mask
                index_0 = __builtin_ffs(remain_indexes)
                while index_0 != 0:
                    (<Numbers>outputs).ob_items[(<Indexes>indexes).ob_items[index_0 - 1]] &= mask_0
                    mask_1 &= ~((1 << index_0) - 1)
                    index_0 = __builtin_ffs(mask_1)
            
            # checking unique numbers
            for index_0 in range(1, 1 << __builtin_popcount((~checked_mask) & NUMBER_MASK)):
                mask_0 = pdep(index_0, (~checked_mask) & NUMBER_MASK)
                include_indexes = 0
                mask_1 = remain_indexes
                index_0 = __builtin_ffs(remain_indexes)
                while index_0 != 0:
                    if (self.ob_items[(<Indexes>indexes).ob_items[index_0 - 1]] & mask_0) != 0:
                        include_indexes |= (1 << index_0)
                    mask_1 &= ~((1 << index_0) - 1)
                    index_0 = __builtin_ffs(mask_1)

                if __builtin_popcount(include_indexes) == __builtin_popcount(mask_0):
                    # setting mask
                    mask_1 = remain_indexes
                    index_0 = __builtin_ffs(remain_indexes)
                    while index_0 != 0:
                        if (include_indexes & (1 << index_0)) != 0:
                            (<Numbers>outputs).ob_items[(<Indexes>indexes).ob_items[index_0 - 1]] &= mask_0
                        else:
                            (<Numbers>outputs).ob_items[(<Indexes>indexes).ob_items[index_0 - 1]] &= ~mask_0
                        mask_1 &= ~((1 << index_0) - 1)
                        index_0 = __builtin_ffs(mask_1)

    cdef Py_ssize_t check_resolved(self, object place_indexes) except -1:
        cdef Py_ssize_t index_0
        cdef Py_ssize_t index_1
        cdef Py_ssize_t mask_0
        cdef Py_ssize_t count_0
        cdef Py_ssize_t count_1 = -1
        cdef Py_ssize_t result = -3
        cdef object key
        cdef object checked = set()
        for index_0 in range(self.ob_size):
            # checking pop-count
            mask_0 = self.ob_items[index_0] & NUMBER_MASK
            count_0 = __builtin_popcount(mask_0)
            if count_0 < 2:
                continue
            if result == -3:
                result = -2
            if count_0 != 2:
                continue
            # checking mask count
            PySet_Clear(checked)
            PySet_Add(checked, index_0)
            count_0 = 0
            for index_1 in range(Py_SIZE(place_indexes)):
                indexes = <object>PyTuple_GET_ITEM(place_indexes, index_1)
                if (<Indexes>indexes).contains(index_0) == 0:
                    continue
                for index_1 in range(9):
                    index_1 = (<Indexes>indexes).ob_items[index_1]
                    key = index_1
                    if key in checked:
                        continue
                    count_0 += __builtin_popcount(self.ob_items[index_1] & mask_0)
                    PySet_Add(checked, key)
            if count_0 > count_1:
                result = index_0
                count_1 = count_0
        return result

    def __eq__(self, other):
        if type(self) is type(other):
            if self.ob_size == (<Numbers>other).ob_size:
                if memcmp(self.ob_items, (<Numbers>other).ob_items, sizeof(self.ob_items[0]) * self.ob_size) == 0:
                    return True
        return False

    def __getitem__(self, key):
        cdef Py_ssize_t index_0 = PyInt_AsSsize_t(PyNumber_Int(key))
        cdef Py_ssize_t mask_0
        cdef object result
        if index_0 < 0:
            index_0 += self.ob_size
        if <size_t>(self.ob_size) <= <size_t>(index_0):
            raise IndexError('index out of range')
        result = Item()
        mask_0 = self.ob_items[index_0]
        if (mask_0 & NUMBER_MASK) == 0:
            mask_0 |= NUMBER_ERROR
        (<Item>result).mask_0 = mask_0
        return result

    def __iter__(self):
        cdef object result = NumbersIter()
        (<NumbersIter>result).parent = self
        return result

    def __repr__(self):
        cdef Py_ssize_t index_0
        cdef Py_ssize_t index_1
        cdef Py_ssize_t mask_0
        cdef object result = bytes(self.ob_size)
        for index_0 in range(self.ob_size):
            mask_0 = self.ob_items[index_0] & NUMBER_MASK
            count = __builtin_popcount(mask_0)
            if count == 1:
                PyBytes_AS_STRING(result)[index_0] = <char>(<Py_ssize_t>(<char>(b'0')) + __builtin_ffs(mask_0))
            elif count == 0:
                PyBytes_AS_STRING(result)[index_0] = <char>(b'X')
            else:
                PyBytes_AS_STRING(result)[index_0] = <char>(b'?')
        return PyUnicode_DecodeASCII(PyBytes_AS_STRING(result), self.ob_size, NULL)

    @property
    def state(self):
        cdef Py_ssize_t index_0
        for index_0 in range(self.ob_size):
            if __builtin_popcount(self.ob_items[index_0] & NUMBER_MASK) != 1:
                return '1'
        return '0'


@cython.auto_pickle(False)
@cython.final
cdef class Answer():
    cdef Py_ssize_t _type
    cdef object _places
    cdef object _children
    cdef object place_indexes

    cdef object process(self, object inputs, object place_indexes):
        cdef object outputs

        self._type = 0
        self._places = []
        self._children = []
        self.place_indexes = place_indexes

        if self.do_check(inputs) != 0:
            # duplicate error
            PyList_Append(self._places, inputs)
        else:
            outputs = self.do_solve(inputs)
            if inputs == outputs:
                # already resolved
                PyList_Append(self._places, outputs)
            elif self.do_check(outputs) != 0:
                # no answer
                PyList_Append(self._places, outputs)
            else:
                self.do_step(outputs)

    cdef object do_step(self, object inputs, Py_ssize_t steps=0):
        cdef Py_ssize_t index_0
        cdef Py_ssize_t index_1
        cdef Py_ssize_t mask_0
        cdef object child
        cdef object outputs

        while True:
            PyList_Append(self.places, inputs)
            outputs = self.do_solve(inputs)
            if inputs == outputs:
                # unchanged
                break
            if self.do_check(outputs) != 0:
                # no answer
                PyList_Append(self._places, outputs)
                return
            inputs = outputs

        # check resolved
        index_0 = (<Numbers>inputs).check_resolved(self.place_indexes)
        if index_0 == -3:
            # resolved
            pass
        elif index_0 == -2:
            # too main remains
            self._type = 2
        else:
            if MAX_SUBST <= steps:
                # too main remains
                self._type = 2
            else:
                # subst value, continue
                self._type = 1
                steps += 1
                mask_0 = (<Numbers>inputs).ob_items[index_0] & NUMBER_MASK
                # first bits
                index_1 = __builtin_ffs(mask_0)
                outputs = (<Numbers>inputs).copy()
                (<Numbers>outputs).ob_items[index_0] = (1 << (index_1 - 1)) | NUMBER_SUBST
                child = Answer()
                (<Answer>child)._type = 0
                (<Answer>child)._places = []
                (<Answer>child)._children = []
                (<Answer>child).place_indexes = self.place_indexes
                (<Answer>child).do_step(outputs, steps)
                PyList_Append(self._children, child)
                # second bits
                index_1 = __builtin_ffs(mask_0 & ~((1 << index_1) - 1))
                outputs = (<Numbers>inputs).copy()
                (<Numbers>outputs).ob_items[index_0] = (1 << (index_1 - 1)) | NUMBER_SUBST
                child = Answer()
                (<Answer>child)._type = 0
                (<Answer>child)._places = []
                (<Answer>child)._children = []
                (<Answer>child).place_indexes = self.place_indexes
                (<Answer>child).do_step(outputs, steps)
                PyList_Append(self._children, child)

    cdef Py_ssize_t do_check(self, object inputs) except -1:
        cdef Py_ssize_t index_0
        cdef Py_ssize_t result = 0
        for index_0 in range(Py_SIZE(self.place_indexes)):
            result |= (<Numbers>inputs).do_check(<object>PyTuple_GET_ITEM(self.place_indexes, index_0))
        return result

    cdef object do_solve(self, object inputs):
        cdef Py_ssize_t index_0
        cdef Py_ssize_t result = 0
        cdef object outputs = (<Numbers>inputs).copy()
        for index_0 in range(Py_SIZE(self.place_indexes)):
            (<Numbers>inputs).do_solve(outputs, <object>PyTuple_GET_ITEM(self.place_indexes, index_0))
        return outputs

    @property
    def type(self):
        return self._type

    @property
    def places(self):
        return self._places

    @property
    def children(self):
        return self._children


cdef Py_ssize_t pdep(Py_ssize_t src, Py_ssize_t mask) nogil:
    cdef Py_ssize_t index_0 = 0
    cdef Py_ssize_t index_1
    cdef Py_ssize_t index_2 = 0
    cdef Py_ssize_t result = 0
    while src != 0:
        index_1 = __builtin_ffs(src)
        while index_0 < index_1:
            index_2 = __builtin_ffs(mask & ~((1 << index_2) - 1))
            if index_2 == 0:
                return result
            index_0 += 1
        result |= (1 << (index_2 - 1))
        src &= ~((1 << index_1) - 1)
    return result

def ffs(src):
 return __builtin_ffs(src)

cdef object new_numbers(Py_ssize_t ob_size):
    cdef object result
    # TODO: variable ob_size
    assert(ob_size == 81)
    
    result = Numbers()
    (<Numbers>result).ob_size = ob_size
    return result

cdef object convert_place_indexes(object place_indexes):
    cdef object result = []
    cdef object data
    cdef object indexes
    cdef Py_ssize_t index_0
    for data in place_indexes:
        if len(data) != 9:
            raise ValueError()
        indexes = Indexes()
        for index_0 in range(9):
            (<Indexes>indexes).ob_items[index_0] = PyInt_AsSsize_t(PyNumber_Int(data[index_0]))
        PyList_Append(result, indexes)
    return PyList_AsTuple(result)

cdef object parse(object data, object place_indexes):
    # setting input data
    cdef Py_ssize_t index_0
    cdef Py_ssize_t index_1
    cdef Py_ssize_t result
    cdef object inputs
    # get maximum number of index
    result = -1
    for index_0 in range(Py_SIZE(place_indexes)):
        inputs = <object>PyTuple_GET_ITEM(place_indexes, index_0)
        for index_1 in range(9):
            if result < (<Indexes>inputs).ob_items[index_1]:
                result = (<Indexes>inputs).ob_items[index_1]
    # checking form data
    inputs = new_numbers(result + 1)
    result = 0
    for index_0 in range((<Numbers>inputs).ob_size):
        try:
            # if number is undefined, raise IndexError or ValueError
            index_1 = PyInt_AsSsize_t(PyNumber_Int(data['n%d' % (index_0)]))
            if 1 <= index_1 and index_1 <= 9:
                index_1 = (1 << (index_1 - 1)) | NUMBER_FIXED
                result = RESULT_CHANGED
            else:
                index_1 = NUMBER_MASK
        except:
            index_1 = NUMBER_MASK
        (<Numbers>inputs).ob_items[index_0] = index_1
    if result == 0:
        inputs = None
    return inputs

def get_answer(data, place_indexes):
    cdef object result = Answer()
    cdef object inputs
    place_indexes = convert_place_indexes(place_indexes)
    inputs = parse(data, place_indexes)
    if inputs is not None:
        (<Answer>result).process(inputs, place_indexes)
    return result
