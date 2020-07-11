#cython: language_level=3,always_allow_keywords=False,binding=True,cdivision=True,c_string_encoding=utf-8,optimize.use_switch=True,optimize.unpack_method_calls=False,warn.maybe_uninitialized=True,warn.multiple_declarators=True,warn.undeclared=True,warn.unused=True,warn.unused_arg=False,warn.unused_result=False
# -*- coding: utf-8 -*-

cimport cython
from cpython.dict cimport (
	PyDict_GetItem,
	PyDict_SetItem,
)
from cpython.long cimport (
	PyLong_AsSsize_t,
	PyLong_FromSsize_t,
	PyLong_FromSize_t,
)
from cpython.list cimport (
	PyList_Append,
	PyList_AsTuple,
	PyList_GET_ITEM,
	PyList_SetSlice,
)
from cpython.number cimport (
	PyNumber_Long,
)
from cpython.object cimport (
	Py_SIZE,
	Py_TYPE,
	PyObject,
	PyObject_GetItem,
	PyObject_Hash,
)
from cpython.ref cimport (
	Py_INCREF,
)
from cpython.set cimport (
	PySet_Add,
	PySet_Clear,
	PySet_Contains,
)
from cpython.tuple cimport (
	PyTuple_GET_ITEM,
	PyTuple_New,
	PyTuple_SET_ITEM,
)
from cpython.unicode cimport (
	PyUnicode_Format,
	PyUnicode_GET_SIZE,
)
from libc.stdlib cimport (
	free,
	malloc,
)
from libc.string cimport (
	memcpy,
)

cdef extern from '<Python.h>':
	Py_UCS4 PyUnicode_READ_CHAR(object o, Py_ssize_t index)

cdef extern from '<stdlib.h>' nogil:
	ctypedef signed short int_fast16_t
	ctypedef signed short int_least16_t

cdef extern from 'builtin.h' nogil:
	int __builtin_popcount(int value)
	int __builtin_ctz(int value)
	void *__builtin_alloca(Py_ssize_t size)


DEF NUMBER_MASK         = 0x01ff
DEF NUMBER_CHANGED      = 0x0200
DEF NUMBER_DOUBLE_CROSS = 0x0400
DEF NUMBER_FIXED        = 0x0800
DEF NUMBER_TEMP         = 0x1000
DEF NUMBER_ERROR        = 0x2000

DEF RESULT_UNCHANGED    = 0x0
DEF RESULT_CHANGED      = 0x1
DEF RESULT_SOLVED       = 0x2
DEF RESULT_ERROR        = 0x4

DEF MAX_SOLVED          = 3


cdef void sort_block_index(
	Py_ssize_t *f_blocks,
	Py_ssize_t index_0,
	Py_ssize_t index_1
) nogil:
	cdef Py_ssize_t index_2 = index_1 - index_0
	cdef Py_ssize_t index_3
	cdef Py_ssize_t index_4
	cdef Py_ssize_t value_0
	cdef Py_ssize_t value_1
	cdef Py_ssize_t *values

	if index_2 <= 1:
		pass
	elif index_2 == 2:
		value_0 = f_blocks[index_0 + 0]
		value_1 = f_blocks[index_0 + 1]
		if value_0 < value_1:
			f_blocks[index_0 + 0] = value_0
			f_blocks[index_0 + 1] = value_1
		else:
			f_blocks[index_0 + 0] = value_1
			f_blocks[index_0 + 1] = value_0
	else:
		index_2 = (index_2 // 2)
		index_3 = index_0 + index_2
		sort_block_index(f_blocks, index_0, index_3)
		sort_block_index(f_blocks, index_3, index_1)

		values = <Py_ssize_t *>(
			__builtin_alloca(sizeof(f_blocks[0]) * index_2)
		)
		memcpy(
			values,
			f_blocks + index_0,
			index_2 * sizeof(f_blocks[0])
		)

		index_0 = 0
		index_4 = 0
		# index_0: result index
		# index_1: right-side end
		# index_2: left-side end
		# index_3: right-side index
		# index_4: left-side index
		# value_0: right_side value (cached)
		# value_1: left_side value (cached)
		value_0 = f_blocks[index_3]
		value_1 = values[index_4]
		while True:
			if value_0 < value_1:
				f_blocks[index_0] = value_0
				index_0 += 1
				index_3 += 1
				if index_3 == index_1:
					index_4 += 1
					f_blocks[index_0] = value_1
					memcpy(
						f_blocks + index_0 + 1,
						values + index_4,
						index_2 - index_4
					)
					break
				value_0 = f_blocks[index_3]
			else:
				f_blocks[index_0] = value_1
				index_0 += 1
				index_4 += 1
				if index_4 == index_2:
					index_3 += 1
					f_blocks[index_0] = value_0
					memcpy(
						f_blocks + index_0 + 1,
						f_blocks + index_2,
						index_1 - index_3
					)
					break
				value_1 = values[index_4]


cdef inline void copy_block_index(
	Py_ssize_t *f_blocks_dst,
	Py_ssize_t *f_blocks_src
) nogil:
	memcpy(f_blocks_dst, f_blocks_src, sizeof(f_blocks_src[0]) * 9)
	sort_block_index(f_blocks_src, 0, 9)


cdef object parse_blocks(
	object form_blocks,
	Py_ssize_t *f_blocks
):
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef object name_indexes = {}
	cdef object field_names = []
	cdef object names = set()
	cdef object block
	cdef object value_1
	cdef object namedtuple
	cdef object row_block_indexes = []
	cdef object col_block_indexes = []
	cdef object other_block_indexes = []
	cdef Py_UCS4 row_name
	cdef Py_UCS4 col_name
	cdef PyObject *object_0
	cdef Py_ssize_t *temp_blocks

	from collections import namedtuple

	temp_blocks = <Py_ssize_t *>(
		malloc(Py_SIZE(form_blocks) * 9 * sizeof(f_blocks[0]))
	)
	if temp_blocks is NULL:
		raise MemoryError()
	try:
		for index_0 in range(Py_SIZE(form_blocks)):
			block = <tuple?>(PyTuple_GET_ITEM(form_blocks, index_0))
			if Py_SIZE(block) < 9:
				raise ValueError(
					PyUnicode_Format(
						"%s: The tuple length must be 9.",
						(repr(block),)
					)
				)

			row_name = 0
			col_name = 0
			PySet_Clear(names)
			for index_1 in range(9):
				value_1 = <unicode?>(PyTuple_GET_ITEM(block, index_1))
				if PyUnicode_GET_SIZE(value_1) != 2:
					raise ValueError(
						PyUnicode_Format(
							"%s: The length must be 2.",
							(value_1,)
						)
					)
				if PySet_Contains(names, value_1) > 0:
					raise ValueError(
						PyUnicode_Format(
							"%s: Duplicate name.",
							(value_1,)
						)
					)
				PySet_Add(names, value_1)

				if index_1 == 0:
					row_name = PyUnicode_READ_CHAR(value_1, 0)
					col_name = PyUnicode_READ_CHAR(value_1, 1)
				else:
					if row_name != 0:
						if PyUnicode_READ_CHAR(value_1, 0) != row_name:
							row_name = 0
					if col_name != 0:
						if PyUnicode_READ_CHAR(value_1, 1) != col_name:
							col_name = 0

				object_0 = PyDict_GetItem(name_indexes, value_1)
				if object_0 is NULL:
					index_2 = Py_SIZE(field_names)
					PyDict_SetItem(name_indexes, value_1, PyLong_FromSsize_t(index_2))
					PyList_Append(field_names, value_1)
				else:
					index_2 = PyLong_AsSsize_t(<object>(object_0))
				temp_blocks[index_0 * 9 + index_1] = index_2

			value_1 = PyLong_FromSsize_t(index_0)
			if row_name != 0:
				PyList_Append(row_block_indexes, value_1)
			elif col_name != 0:
				PyList_Append(col_block_indexes, value_1)
			else:
				PyList_Append(other_block_indexes, value_1)

		# adding horizontal block
		f_blocks[0] = Py_SIZE(field_names)
		f_blocks[1] = Py_SIZE(row_block_indexes)
		index_1 = 2
		for index_0 in range(Py_SIZE(row_block_indexes)):
			index_2 = PyLong_AsSsize_t(
				<object>(PyList_GET_ITEM(row_block_indexes, index_0))
			)
			copy_block_index(
				&f_blocks[index_1 + index_0 * 9],
				&temp_blocks[index_2 * 9],
			)

		# adding vertical block
		index_1 += Py_SIZE(row_block_indexes) * 9
		f_blocks[index_1] = Py_SIZE(col_block_indexes)
		index_1 += 1
		for index_0 in range(Py_SIZE(col_block_indexes)):
			index_2 = PyLong_AsSsize_t(
				<object>(PyList_GET_ITEM(col_block_indexes, index_0))
			)
			copy_block_index(
				&f_blocks[index_1 + index_0 * 9],
				&temp_blocks[index_2 * 9],
			)

		# adding other block
		index_1 += Py_SIZE(col_block_indexes) * 9
		f_blocks[index_1] = Py_SIZE(other_block_indexes)
		index_1 += 1
		for index_0 in range(Py_SIZE(other_block_indexes)):
			index_2 = PyLong_AsSsize_t(
				<object>(PyList_GET_ITEM(other_block_indexes, index_0))
			)
			copy_block_index(
				&f_blocks[index_1 + index_0 * 9],
				&temp_blocks[index_2 * 9],
			)

		index_1 += Py_SIZE(other_block_indexes) * 9
		f_blocks[index_1] = 0

	finally:
		free(temp_blocks)

	PyList_Append(field_names, 'method')
	return namedtuple(
		PyUnicode_Format(
			'Place%x',
			(
				PyLong_FromSize_t(
					PyObject_Hash(PyList_AsTuple(field_names))
				),
			)
		),
		field_names
	)


cdef inline Py_ssize_t check_numbers_block(
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers,
	Py_ssize_t result
) nogil:
	cdef Py_ssize_t solved_indexes[9]
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef int_fast16_t value_0
	cdef int_fast16_t value_1

	# initializing registered numbers (-1: unused)
	for index_0 in range(9):
		solved_indexes[index_0] = -1

	for index_0 in range(9):
		index_1 = f_blocks[index_0]
		value_0 = <int_fast16_t>(numbers[index_1])
		value_1 = <int_fast16_t>(value_0 & NUMBER_MASK)
		if value_1 == 0:
			numbers[index_1] = <int_least16_t>(
				value_0 | NUMBER_ERROR
			)
			result |= RESULT_ERROR
		elif __builtin_popcount(value_1) == 1:
			index_3 = __builtin_ctz(value_1)
			index_2 = solved_indexes[index_3]
			if index_2 >= 0:
				# found multiple solved number.
				numbers[index_1] = <int_least16_t>(
					value_0 | NUMBER_ERROR
				)
				numbers[index_2] = <int_least16_t>(
					numbers[index_2] | NUMBER_ERROR
				)
				result |= RESULT_ERROR
			solved_indexes[index_3] = index_1
		else:
			result &= (~RESULT_SOLVED)

	return result


cdef Py_ssize_t check_numbers(
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers
) nogil:
	cdef Py_ssize_t result = RESULT_SOLVED
	cdef Py_ssize_t index_0 = 1
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2

	index_1 = f_blocks[index_0]
	while index_1 > 0:
		index_0 += 1
		for index_2 in range(index_1):
			result = check_numbers_block(
				f_blocks + (index_0 + index_2 * 9),
				numbers,
				result
			)
		index_0 += index_1 * 9
		index_1 = f_blocks[index_0]

	return result


cdef Py_ssize_t parse_data(
	object form_data,
	object place_fields,
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers,
) except -1:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef object value_0

	for index_0 in range(f_blocks[0]):
		value_0 = <object>(PyTuple_GET_ITEM(place_fields, index_0))
		try:
			# if number is undefined, raise IndexError or ValueError
			index_1 = PyLong_AsSsize_t(
				PyNumber_Long(
					PyObject_GetItem(form_data, value_0)
				)
			)
			if 1 <= index_1 and index_1 <= 9:
				numbers[index_0] = <int_least16_t>(
					(1 << (index_1 - 1)) | NUMBER_FIXED
				)
				result |= RESULT_CHANGED
				continue
		except:
			pass
		numbers[index_0] = NUMBER_MASK

	return result


cdef object make_place(
	object place_class,
	Py_ssize_t form_name_count,
	const int_least16_t *numbers,
	object method
):
	cdef Py_ssize_t index_0
	cdef object values = PyTuple_New(form_name_count + 1)
	cdef object value_0

	for index_0 in range(form_name_count):
		value_0 = Cell()
		(<Cell>(value_0)).value_0 = <int_fast16_t>(numbers[index_0])
		Py_INCREF(value_0)
		PyTuple_SET_ITEM(values, index_0, value_0)
	Py_INCREF(method)
	PyTuple_SET_ITEM(values, form_name_count + 0, method)
	return place_class(*values)


cdef inline Py_ssize_t solve_method1_block(
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers,
	Py_ssize_t form_name_count,
	Py_ssize_t result,
	int_fast16_t value_0
) nogil:
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef int_fast16_t value_1
	cdef int_fast16_t value_2
	cdef int_fast16_t value_3
	cdef Py_ssize_t indexes_0 = 0
	cdef Py_ssize_t indexes_1 = 0

	for index_0 in range(9):
		index_1 = f_blocks[index_0]
		value_1 = <int_fast16_t>(
			numbers[index_1 + form_name_count] & NUMBER_MASK
		)
		if value_1 == value_0:
			indexes_0 |= (1 << index_0)
		elif (value_1 & value_0) == 0:
			indexes_1 |= (1 << index_0)

	if __builtin_popcount(indexes_0) == __builtin_popcount(value_0):
		value_3 = <int_fast16_t>(~value_0)
		for index_0 in range(9):
			if (indexes_0 & (1 << index_0)) == 0:
				index_1 = f_blocks[index_0]
				value_1 = <int_fast16_t>(numbers[index_1])
				value_2 = <int_fast16_t>(value_1 & value_3)
				if value_2 != value_1:
					numbers[index_1] = <int_least16_t>(
						value_2 | NUMBER_CHANGED
					)
					result |= RESULT_CHANGED
	elif __builtin_popcount(indexes_1) == 9 - __builtin_popcount(value_0):
		value_3 = <int_fast16_t>(value_0 | (~NUMBER_MASK))
		for index_0 in range(9):
			if (indexes_1 & (1 << index_0)) == 0:
				index_1 = f_blocks[index_0]
				value_1 = <int_fast16_t>(numbers[index_1])
				value_2 = <int_fast16_t>(value_1 & value_3)
				if value_2 != value_1:
					numbers[index_1] = <int_least16_t>(
						value_2 | NUMBER_CHANGED
					)
					result |= RESULT_CHANGED

	return result


cdef inline Py_ssize_t solve_method1(
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers
) nogil:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef Py_ssize_t index_0 = 1
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef int_fast16_t value_0

	index_1 = f_blocks[index_0]
	while index_1 > 0:
		index_0 += 1
		for index_2 in range(index_1):
			for value_0 in range(1, 1 << 9):
				result = solve_method1_block(
					f_blocks + (index_0 + index_2 * 9),
					numbers,
					f_blocks[0],
					result,
					value_0
				)
		index_0 += index_1 * 9
		index_1 = f_blocks[index_0]

	return result


cdef Py_ssize_t solve_method2a_find(
	const Py_ssize_t *f_blocks,
	Py_ssize_t index_0,
	Py_ssize_t index_1,
	Py_ssize_t value_0
) nogil:
	cdef Py_ssize_t index_2
	cdef Py_ssize_t value_1

	while index_0 <= index_1:
		index_2 = (index_0 + index_1) // 2
		value_1 = f_blocks[index_2]
		if value_1 == value_0:
			return index_2
		elif value_1 < value_0:
			index_0 = index_2 + 1
		else:
			index_1 = index_2 - 1

	return - index_0 - 1


cdef Py_ssize_t solve_method2_replace(
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers,
	Py_ssize_t index_0,
	Py_ssize_t index_1,
	Py_ssize_t value_0
) nogil:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef int_fast16_t value_1
	cdef int_fast16_t value_2

	for index_2 in range(index_0):
		index_3 = f_blocks[index_2]
		value_1 = <int_fast16_t>(numbers[index_3])
		value_2 = <int_fast16_t>(value_1 & value_0)
		if value_2 != value_1:
			numbers[index_3] = <int_least16_t>(
				value_2 | NUMBER_CHANGED
			)
			result |= RESULT_CHANGED

	for index_2 in range(index_0 + 1, index_1):
		index_3 = f_blocks[index_2]
		value_1 = <int_fast16_t>(numbers[index_3])
		value_2 = <int_fast16_t>(value_1 & value_0)
		if value_2 != value_1:
			numbers[index_3] = <int_least16_t>(
				value_2 | NUMBER_CHANGED
			)
			result |= RESULT_CHANGED

	for index_2 in range(index_1 + 1, 9):
		index_3 = f_blocks[index_2]
		value_1 = <int_fast16_t>(numbers[index_3])
		value_2 = <int_fast16_t>(value_1 & value_0)
		if value_2 != value_1:
			numbers[index_3] = <int_least16_t>(
				value_2 | NUMBER_CHANGED
			)
			result |= RESULT_CHANGED

	return result


cdef struct DoubleCrossItem:
	DoubleCrossItem *indexes_0
	Py_ssize_t index_0
	Py_ssize_t index_1


cdef Py_ssize_t solve_method2a(
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers,
	Py_ssize_t index_0,
	Py_ssize_t index_1,
	int_fast16_t value_0
) nogil:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef Py_ssize_t index_4
	cdef Py_ssize_t index_5
	cdef Py_ssize_t index_6
	cdef Py_ssize_t index_7
	cdef Py_ssize_t index_8
	cdef Py_ssize_t index_9
	cdef Py_ssize_t index_a
	cdef Py_ssize_t index_b
	cdef Py_ssize_t index_c
	cdef Py_ssize_t index_d
	cdef DoubleCrossItem *indexes_0
	cdef DoubleCrossItem *indexes_1
	cdef DoubleCrossItem *indexes_2[1]
	cdef DoubleCrossItem **indexes_3 = indexes_2

	indexes_2[0] = NULL

	# finding a pair of candidate items
	for index_2 in range(f_blocks[index_0]):
		# finding 1st candidate index
		for index_5 in range(9):
			index_3 = f_blocks[
				index_0 + 1 + index_2 * 9 + index_5
			]
			if (numbers[index_3 + f_blocks[0]] & value_0) != 0:
				# finding 2nd candidate index
				for index_6 in range(index_5 + 1, 9):
					index_4 = f_blocks[
						index_0 + 1 + index_2 * 9 + index_6
					]
					if (numbers[index_4 + f_blocks[0]] & value_0) != 0:
						# finding 3rd candidate index
						for index_7 in range(index_6 + 1, 9):
							index_8 = f_blocks[
								index_0 + 1 + index_2 * 9 + index_7
							]
							if (numbers[index_8 + f_blocks[0]] & value_0) != 0:
								break
						else:
							# found only 2 candicate indexes
							indexes_0 = <DoubleCrossItem *>(
								__builtin_alloca(sizeof(DoubleCrossItem))
							)
							indexes_0.indexes_0 = NULL
							indexes_0.index_0 = index_3
							indexes_0.index_1 = index_4
							indexes_3[0] = indexes_0
							indexes_3 = (&(indexes_0.indexes_0))

						break
				break

	indexes_0 = indexes_2[0]
	value_0 = (~value_0)
	while indexes_0 is not NULL:
		index_8 = indexes_0.index_0
		index_9 = indexes_0.index_1
		indexes_0 = indexes_0.indexes_0
		if indexes_0 is NULL:
			break

		for index_6 in range(f_blocks[index_1]):
			# finding part of double cross indexes
			index_2 = solve_method2a_find(
				f_blocks + (index_1 + 1 + index_6 * 9),
				0,
				9 - 1,
				index_8
			)
			if index_2 < 0:
				index_2 = solve_method2a_find(
					f_blocks + (index_1 + 1 + index_6 * 9),
					- index_2 - 1,
					9 - 1,
					index_9
				)
				if index_2 < 0:
					continue
				index_c = index_8
			else:
				index_c = index_9

			indexes_1 = indexes_0
			while indexes_1 is not NULL:
				index_a = indexes_1.index_0
				index_b = indexes_1.index_1
				indexes_1 = indexes_1.indexes_0

				# finding another part of double cross indexes
				index_3 = solve_method2a_find(
					f_blocks + (index_1 + 1 + index_6 * 9),
					0,
					9 - 1,
					index_a
				)
				if index_3 < 0:
					index_3 = solve_method2a_find(
						f_blocks + (index_1 + 1 + index_6 * 9),
						- index_3 - 1,
						9 - 1,
						index_b
					)
					if index_3 < 0:
						continue
					index_d = index_a
				else:
					index_d = index_b

				if index_c > index_d:
					index_7 = index_d
					index_d = index_c
					index_c = index_7

				for index_7 in range(index_6 + 1, f_blocks[index_1]):
					index_4 = solve_method2a_find(
						f_blocks + (index_1 + 1 + index_7 * 9),
						0,
						9 - 1,
						index_c
					)
					if index_4 < 0:
						continue
					index_5 = solve_method2a_find(
						f_blocks + (index_1 + 1 + index_7 * 9),
						index_4 + 1,
						9 - 1,
						index_d
					)
					if index_5 < 0:
						continue

					# removing bits: value_0 (a pair of candidate numbers)
					if index_2 < index_3:
						result |= solve_method2_replace(
							f_blocks + (index_1 + 1 + index_6 * 9),
							numbers,
							index_2,
							index_3,
							value_0
						)
					else:
						result |= solve_method2_replace(
							f_blocks + (index_1 + 1 + index_6 * 9),
							numbers,
							index_3,
							index_2,
							value_0
						)
					result |= solve_method2_replace(
						f_blocks + (index_1 + 1 + index_7 * 9),
						numbers,
						index_4,
						index_5,
						value_0
					)
					if result != RESULT_UNCHANGED:
						numbers[index_8] = <int_least16_t>(
							numbers[index_8] | NUMBER_DOUBLE_CROSS
						)
						numbers[index_9] = <int_least16_t>(
							numbers[index_9] | NUMBER_DOUBLE_CROSS
						)
						numbers[index_a] = <int_least16_t>(
							numbers[index_a] | NUMBER_DOUBLE_CROSS
						)
						numbers[index_b] = <int_least16_t>(
							numbers[index_b] | NUMBER_DOUBLE_CROSS
						)
						return result
					break

	return result


cdef Py_ssize_t solve_method2(
	const Py_ssize_t *f_blocks,
	int_least16_t *numbers
) except -1:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef int_fast16_t value_0

	for value_0 in range(9):
		# check vertical block, filter horizontal block
		result = solve_method2a(
			f_blocks,
			numbers,
			1,
			f_blocks[1] * 9 + 2,
			1 << value_0
		)
		if result != RESULT_UNCHANGED:
			break

		# check horizontal block, filter vertical block
		result = solve_method2a(
			f_blocks,
			numbers,
			f_blocks[1] * 9 + 2,
			1,
			1 << value_0
		)
		if result != RESULT_UNCHANGED:
			break

	return result


@cython.auto_pickle(False)
@cython.final
cdef class Answer():
	cdef object _places
	cdef object _children
	cdef Py_ssize_t _tasks


	cdef Py_ssize_t solve(
		self,
		object place_class,
		const Py_ssize_t *f_blocks,
		int_least16_t *numbers,
		Py_ssize_t solved_count
	) except -1:
		cdef Py_ssize_t result
		cdef Py_ssize_t new_solved_count
		cdef Py_ssize_t index_0
		cdef Py_ssize_t index_1
		cdef int_fast16_t value_0
		cdef int_fast16_t value_1
		cdef int_least16_t *next_numbers
		cdef object child
		cdef object _children_all
		cdef object _children_solved


		while True:
			memcpy(
				numbers + f_blocks[0],
				numbers,
				f_blocks[0] * sizeof(numbers[0])
			)

			result = solve_method1(f_blocks, numbers)
			if result != RESULT_UNCHANGED:
				child = 1
			else:
				result = solve_method2(f_blocks, numbers)
				if result != RESULT_UNCHANGED:
					child = 2
				else:
					break

			result |= check_numbers(f_blocks, numbers)
			PyList_Append(
				self._places,
				make_place(place_class, f_blocks[0], numbers, child)
			)
			if (result & (RESULT_SOLVED | RESULT_ERROR)) != 0:
				self._tasks += Py_SIZE(self._places)
				self._places = PyList_AsTuple(self._places)
				return ((result & (RESULT_SOLVED)) != 0)

			for index_0 in range(f_blocks[0]):
				numbers[index_0] = <int_least16_t>(
					numbers[index_0] & (~(NUMBER_CHANGED | NUMBER_DOUBLE_CROSS))
				)

		# Assign a value to a single block whose answer has not been determined
		# because it cannot be resolved any further.
		index_0 = -1
		value_0 = 10
		for index_1 in range(f_blocks[0]):
			value_1 = __builtin_popcount(numbers[index_1] & NUMBER_MASK)
			if value_1 == 2:
				index_0 = index_1
				break
			elif value_1 > 2:
				if value_1 < value_0:
					index_0 = index_1
					value_0 = value_1

		new_solved_count = solved_count
		if index_0 >= 0:
			_children_all = []
			_children_solved = []
			next_numbers = <int_least16_t *>(
				malloc(f_blocks[0] * sizeof(numbers[0]) * 2)
			)
			if next_numbers is NULL:
				raise MemoryError()
			try:
				for index_1 in range(9):
					if (numbers[index_0] & (1 << index_1)) == 0:
						continue

					if new_solved_count >= MAX_SOLVED:
						break

					# copy from numbers to next_numbers
					memcpy(
						next_numbers,
						numbers,
						f_blocks[0] * sizeof(numbers[0])
					)
					next_numbers[index_0] = <int_least16_t>(
						(1 << index_1) | NUMBER_CHANGED
					)
					child = Answer()
					(<Answer>(child))._places = [
						make_place(
							place_class,
							f_blocks[0],
							next_numbers,
							3
						)
					]
					next_numbers[index_0] = <int_least16_t>(
						(1 << index_1) | NUMBER_TEMP
					)
					result = (<Answer>(child)).solve(
						place_class,
						f_blocks,
						next_numbers,
						new_solved_count
					)
					self._tasks += (<Answer>(child))._tasks
					PyList_Append(_children_all, child)
					if result > 0:
						PyList_Append(_children_solved, child)
						new_solved_count += result
			finally:
				free(next_numbers)

			result = Py_SIZE(_children_solved)
			if result == 0:
				self._children = PyList_AsTuple(_children_all)
			elif result == 1:
				child = <object>(PyList_GET_ITEM(_children_solved, 0))
				PyList_SetSlice(
					self._places,
					Py_SIZE(self._places),
					Py_SIZE(self._places),
					(<Answer>(child))._places
				)
				self._tasks -= Py_SIZE((<Answer>(child))._places)
				self._children = (<Answer>(child))._children
			else:
				self._children = PyList_AsTuple(_children_solved)

		self._tasks += Py_SIZE(self._places)
		self._places = PyList_AsTuple(self._places)
		return new_solved_count - solved_count


	@property
	def places(self):
		return self._places


	@property
	def children(self):
		return self._children


	@property
	def tasks(self):
		return self._tasks


DEF Cell_Numbers = (
	'',              1,               2,               '12-\n---\n---',
	3,               '1-3\n---\n---', '-23\n---\n---', '123\n---\n---',
	4,               '1--\n4--\n---', '-2-\n4--\n---', '12-\n4--\n---',
	'--3\n4--\n---', '1-3\n4--\n---', '-23\n4--\n---', '123\n4--\n---',
	5,               '1--\n-5-\n---', '-2-\n-5-\n---', '12-\n-5-\n---',
	'--3\n-5-\n---', '1-3\n-5-\n---', '-23\n-5-\n---', '123\n-5-\n---',
	'---\n45-\n---', '1--\n45-\n---', '-2-\n45-\n---', '12-\n45-\n---',
	'--3\n45-\n---', '1-3\n45-\n---', '-23\n45-\n---', '123\n45-\n---',
	6,               '1--\n--6\n---', '-2-\n--6\n---', '12-\n--6\n---',
	'--3\n--6\n---', '1-3\n--6\n---', '-23\n--6\n---', '123\n--6\n---',
	'---\n4-6\n---', '1--\n4-6\n---', '-2-\n4-6\n---', '12-\n4-6\n---',
	'--3\n4-6\n---', '1-3\n4-6\n---', '-23\n4-6\n---', '123\n4-6\n---',
	'---\n-56\n---', '1--\n-56\n---', '-2-\n-56\n---', '12-\n-56\n---',
	'--3\n-56\n---', '1-3\n-56\n---', '-23\n-56\n---', '123\n-56\n---',
	'---\n456\n---', '1--\n456\n---', '-2-\n456\n---', '12-\n456\n---',
	'--3\n456\n---', '1-3\n456\n---', '-23\n456\n---', '123\n456\n---',
	7,               '1--\n---\n7--', '-2-\n---\n7--', '12-\n---\n7--',
	'--3\n---\n7--', '1-3\n---\n7--', '-23\n---\n7--', '123\n---\n7--',
	'---\n4--\n7--', '1--\n4--\n7--', '-2-\n4--\n7--', '12-\n4--\n7--',
	'--3\n4--\n7--', '1-3\n4--\n7--', '-23\n4--\n7--', '123\n4--\n7--',
	'---\n-5-\n7--', '1--\n-5-\n7--', '-2-\n-5-\n7--', '12-\n-5-\n7--',
	'--3\n-5-\n7--', '1-3\n-5-\n7--', '-23\n-5-\n7--', '123\n-5-\n7--',
	'---\n45-\n7--', '1--\n45-\n7--', '-2-\n45-\n7--', '12-\n45-\n7--',
	'--3\n45-\n7--', '1-3\n45-\n7--', '-23\n45-\n7--', '123\n45-\n7--',
	'---\n--6\n7--', '1--\n--6\n7--', '-2-\n--6\n7--', '12-\n--6\n7--',
	'--3\n--6\n7--', '1-3\n--6\n7--', '-23\n--6\n7--', '123\n--6\n7--',
	'---\n4-6\n7--', '1--\n4-6\n7--', '-2-\n4-6\n7--', '12-\n4-6\n7--',
	'--3\n4-6\n7--', '1-3\n4-6\n7--', '-23\n4-6\n7--', '123\n4-6\n7--',
	'---\n-56\n7--', '1--\n-56\n7--', '-2-\n-56\n7--', '12-\n-56\n7--',
	'--3\n-56\n7--', '1-3\n-56\n7--', '-23\n-56\n7--', '123\n-56\n7--',
	'---\n456\n7--', '1--\n456\n7--', '-2-\n456\n7--', '12-\n456\n7--',
	'--3\n456\n7--', '1-3\n456\n7--', '-23\n456\n7--', '123\n456\n7--',
	8,               '1--\n---\n-8-', '-2-\n---\n-8-', '12-\n---\n-8-',
	'--3\n---\n-8-', '1-3\n---\n-8-', '-23\n---\n-8-', '123\n---\n-8-',
	'---\n4--\n-8-', '1--\n4--\n-8-', '-2-\n4--\n-8-', '12-\n4--\n-8-',
	'--3\n4--\n-8-', '1-3\n4--\n-8-', '-23\n4--\n-8-', '123\n4--\n-8-',
	'---\n-5-\n-8-', '1--\n-5-\n-8-', '-2-\n-5-\n-8-', '12-\n-5-\n-8-',
	'--3\n-5-\n-8-', '1-3\n-5-\n-8-', '-23\n-5-\n-8-', '123\n-5-\n-8-',
	'---\n45-\n-8-', '1--\n45-\n-8-', '-2-\n45-\n-8-', '12-\n45-\n-8-',
	'--3\n45-\n-8-', '1-3\n45-\n-8-', '-23\n45-\n-8-', '123\n45-\n-8-',
	'---\n--6\n-8-', '1--\n--6\n-8-', '-2-\n--6\n-8-', '12-\n--6\n-8-',
	'--3\n--6\n-8-', '1-3\n--6\n-8-', '-23\n--6\n-8-', '123\n--6\n-8-',
	'---\n4-6\n-8-', '1--\n4-6\n-8-', '-2-\n4-6\n-8-', '12-\n4-6\n-8-',
	'--3\n4-6\n-8-', '1-3\n4-6\n-8-', '-23\n4-6\n-8-', '123\n4-6\n-8-',
	'---\n-56\n-8-', '1--\n-56\n-8-', '-2-\n-56\n-8-', '12-\n-56\n-8-',
	'--3\n-56\n-8-', '1-3\n-56\n-8-', '-23\n-56\n-8-', '123\n-56\n-8-',
	'---\n456\n-8-', '1--\n456\n-8-', '-2-\n456\n-8-', '12-\n456\n-8-',
	'--3\n456\n-8-', '1-3\n456\n-8-', '-23\n456\n-8-', '123\n456\n-8-',
	'---\n---\n78-', '1--\n---\n78-', '-2-\n---\n78-', '12-\n---\n78-',
	'--3\n---\n78-', '1-3\n---\n78-', '-23\n---\n78-', '123\n---\n78-',
	'---\n4--\n78-', '1--\n4--\n78-', '-2-\n4--\n78-', '12-\n4--\n78-',
	'--3\n4--\n78-', '1-3\n4--\n78-', '-23\n4--\n78-', '123\n4--\n78-',
	'---\n-5-\n78-', '1--\n-5-\n78-', '-2-\n-5-\n78-', '12-\n-5-\n78-',
	'--3\n-5-\n78-', '1-3\n-5-\n78-', '-23\n-5-\n78-', '123\n-5-\n78-',
	'---\n45-\n78-', '1--\n45-\n78-', '-2-\n45-\n78-', '12-\n45-\n78-',
	'--3\n45-\n78-', '1-3\n45-\n78-', '-23\n45-\n78-', '123\n45-\n78-',
	'---\n--6\n78-', '1--\n--6\n78-', '-2-\n--6\n78-', '12-\n--6\n78-',
	'--3\n--6\n78-', '1-3\n--6\n78-', '-23\n--6\n78-', '123\n--6\n78-',
	'---\n4-6\n78-', '1--\n4-6\n78-', '-2-\n4-6\n78-', '12-\n4-6\n78-',
	'--3\n4-6\n78-', '1-3\n4-6\n78-', '-23\n4-6\n78-', '123\n4-6\n78-',
	'---\n-56\n78-', '1--\n-56\n78-', '-2-\n-56\n78-', '12-\n-56\n78-',
	'--3\n-56\n78-', '1-3\n-56\n78-', '-23\n-56\n78-', '123\n-56\n78-',
	'---\n456\n78-', '1--\n456\n78-', '-2-\n456\n78-', '12-\n456\n78-',
	'--3\n456\n78-', '1-3\n456\n78-', '-23\n456\n78-', '123\n456\n78-',
	9,               '1--\n---\n--9', '-2-\n---\n--9', '12-\n---\n--9',
	'--3\n---\n--9', '1-3\n---\n--9', '-23\n---\n--9', '123\n---\n--9',
	'---\n4--\n--9', '1--\n4--\n--9', '-2-\n4--\n--9', '12-\n4--\n--9',
	'--3\n4--\n--9', '1-3\n4--\n--9', '-23\n4--\n--9', '123\n4--\n--9',
	'---\n-5-\n--9', '1--\n-5-\n--9', '-2-\n-5-\n--9', '12-\n-5-\n--9',
	'--3\n-5-\n--9', '1-3\n-5-\n--9', '-23\n-5-\n--9', '123\n-5-\n--9',
	'---\n45-\n--9', '1--\n45-\n--9', '-2-\n45-\n--9', '12-\n45-\n--9',
	'--3\n45-\n--9', '1-3\n45-\n--9', '-23\n45-\n--9', '123\n45-\n--9',
	'---\n--6\n--9', '1--\n--6\n--9', '-2-\n--6\n--9', '12-\n--6\n--9',
	'--3\n--6\n--9', '1-3\n--6\n--9', '-23\n--6\n--9', '123\n--6\n--9',
	'---\n4-6\n--9', '1--\n4-6\n--9', '-2-\n4-6\n--9', '12-\n4-6\n--9',
	'--3\n4-6\n--9', '1-3\n4-6\n--9', '-23\n4-6\n--9', '123\n4-6\n--9',
	'---\n-56\n--9', '1--\n-56\n--9', '-2-\n-56\n--9', '12-\n-56\n--9',
	'--3\n-56\n--9', '1-3\n-56\n--9', '-23\n-56\n--9', '123\n-56\n--9',
	'---\n456\n--9', '1--\n456\n--9', '-2-\n456\n--9', '12-\n456\n--9',
	'--3\n456\n--9', '1-3\n456\n--9', '-23\n456\n--9', '123\n456\n--9',
	'---\n---\n7-9', '1--\n---\n7-9', '-2-\n---\n7-9', '12-\n---\n7-9',
	'--3\n---\n7-9', '1-3\n---\n7-9', '-23\n---\n7-9', '123\n---\n7-9',
	'---\n4--\n7-9', '1--\n4--\n7-9', '-2-\n4--\n7-9', '12-\n4--\n7-9',
	'--3\n4--\n7-9', '1-3\n4--\n7-9', '-23\n4--\n7-9', '123\n4--\n7-9',
	'---\n-5-\n7-9', '1--\n-5-\n7-9', '-2-\n-5-\n7-9', '12-\n-5-\n7-9',
	'--3\n-5-\n7-9', '1-3\n-5-\n7-9', '-23\n-5-\n7-9', '123\n-5-\n7-9',
	'---\n45-\n7-9', '1--\n45-\n7-9', '-2-\n45-\n7-9', '12-\n45-\n7-9',
	'--3\n45-\n7-9', '1-3\n45-\n7-9', '-23\n45-\n7-9', '123\n45-\n7-9',
	'---\n--6\n7-9', '1--\n--6\n7-9', '-2-\n--6\n7-9', '12-\n--6\n7-9',
	'--3\n--6\n7-9', '1-3\n--6\n7-9', '-23\n--6\n7-9', '123\n--6\n7-9',
	'---\n4-6\n7-9', '1--\n4-6\n7-9', '-2-\n4-6\n7-9', '12-\n4-6\n7-9',
	'--3\n4-6\n7-9', '1-3\n4-6\n7-9', '-23\n4-6\n7-9', '123\n4-6\n7-9',
	'---\n-56\n7-9', '1--\n-56\n7-9', '-2-\n-56\n7-9', '12-\n-56\n7-9',
	'--3\n-56\n7-9', '1-3\n-56\n7-9', '-23\n-56\n7-9', '123\n-56\n7-9',
	'---\n456\n7-9', '1--\n456\n7-9', '-2-\n456\n7-9', '12-\n456\n7-9',
	'--3\n456\n7-9', '1-3\n456\n7-9', '-23\n456\n7-9', '123\n456\n7-9',
	'---\n---\n-89', '1--\n---\n-89', '-2-\n---\n-89', '12-\n---\n-89',
	'--3\n---\n-89', '1-3\n---\n-89', '-23\n---\n-89', '123\n---\n-89',
	'---\n4--\n-89', '1--\n4--\n-89', '-2-\n4--\n-89', '12-\n4--\n-89',
	'--3\n4--\n-89', '1-3\n4--\n-89', '-23\n4--\n-89', '123\n4--\n-89',
	'---\n-5-\n-89', '1--\n-5-\n-89', '-2-\n-5-\n-89', '12-\n-5-\n-89',
	'--3\n-5-\n-89', '1-3\n-5-\n-89', '-23\n-5-\n-89', '123\n-5-\n-89',
	'---\n45-\n-89', '1--\n45-\n-89', '-2-\n45-\n-89', '12-\n45-\n-89',
	'--3\n45-\n-89', '1-3\n45-\n-89', '-23\n45-\n-89', '123\n45-\n-89',
	'---\n--6\n-89', '1--\n--6\n-89', '-2-\n--6\n-89', '12-\n--6\n-89',
	'--3\n--6\n-89', '1-3\n--6\n-89', '-23\n--6\n-89', '123\n--6\n-89',
	'---\n4-6\n-89', '1--\n4-6\n-89', '-2-\n4-6\n-89', '12-\n4-6\n-89',
	'--3\n4-6\n-89', '1-3\n4-6\n-89', '-23\n4-6\n-89', '123\n4-6\n-89',
	'---\n-56\n-89', '1--\n-56\n-89', '-2-\n-56\n-89', '12-\n-56\n-89',
	'--3\n-56\n-89', '1-3\n-56\n-89', '-23\n-56\n-89', '123\n-56\n-89',
	'---\n456\n-89', '1--\n456\n-89', '-2-\n456\n-89', '12-\n456\n-89',
	'--3\n456\n-89', '1-3\n456\n-89', '-23\n456\n-89', '123\n456\n-89',
	'---\n---\n789', '1--\n---\n789', '-2-\n---\n789', '12-\n---\n789',
	'--3\n---\n789', '1-3\n---\n789', '-23\n---\n789', '123\n---\n789',
	'---\n4--\n789', '1--\n4--\n789', '-2-\n4--\n789', '12-\n4--\n789',
	'--3\n4--\n789', '1-3\n4--\n789', '-23\n4--\n789', '123\n4--\n789',
	'---\n-5-\n789', '1--\n-5-\n789', '-2-\n-5-\n789', '12-\n-5-\n789',
	'--3\n-5-\n789', '1-3\n-5-\n789', '-23\n-5-\n789', '123\n-5-\n789',
	'---\n45-\n789', '1--\n45-\n789', '-2-\n45-\n789', '12-\n45-\n789',
	'--3\n45-\n789', '1-3\n45-\n789', '-23\n45-\n789', '123\n45-\n789',
	'---\n--6\n789', '1--\n--6\n789', '-2-\n--6\n789', '12-\n--6\n789',
	'--3\n--6\n789', '1-3\n--6\n789', '-23\n--6\n789', '123\n--6\n789',
	'---\n4-6\n789', '1--\n4-6\n789', '-2-\n4-6\n789', '12-\n4-6\n789',
	'--3\n4-6\n789', '1-3\n4-6\n789', '-23\n4-6\n789', '123\n4-6\n789',
	'---\n-56\n789', '1--\n-56\n789', '-2-\n-56\n789', '12-\n-56\n789',
	'--3\n-56\n789', '1-3\n-56\n789', '-23\n-56\n789', '123\n-56\n789',
	'---\n456\n789', '1--\n456\n789', '-2-\n456\n789', '12-\n456\n789',
	'--3\n456\n789', '1-3\n456\n789', '-23\n456\n789', '123\n456\n789',
)


@cython.auto_pickle(False)
@cython.final
cdef class Cell:
	cdef int_fast16_t value_0


	@property
	def state(self):
		cdef object result
		cdef int_fast16_t value_0 = self.value_0
		cdef int_fast16_t value_1 = <int_fast16_t>(value_0 & (~NUMBER_MASK))

		if value_1 == (NUMBER_ERROR | NUMBER_FIXED):
			result = ' f e'
		elif value_1 == (NUMBER_ERROR | NUMBER_TEMP):
			result = ' t e'
		elif value_1 == (NUMBER_ERROR | NUMBER_CHANGED):
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				result = ' u c e'
			else:
				result = ' c e'
		elif value_1 == (NUMBER_ERROR | NUMBER_DOUBLE_CROSS):
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				result = ' u d e'
			else:
				result = ' d e'
		elif value_1 == NUMBER_ERROR:
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				result = ' u e'
			else:
				result = ' e'
		elif value_1 == NUMBER_FIXED:
			result = ' f'
		elif value_1 == NUMBER_TEMP:
			result = ' t'
		elif value_1 == NUMBER_CHANGED:
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				result = ' u c'
			else:
				result = ' c'
		elif value_1 == NUMBER_DOUBLE_CROSS:
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				result = ' u d'
			else:
				result = ' d'
		else:
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				result = ' u'
			else:
				result = ''
		return result


	@property
	def number(self):
		return <object>(
			PyTuple_GET_ITEM(Cell_Numbers, self.value_0 & NUMBER_MASK)
		)


	def __repr__(self):
		return PyUnicode_Format(
			'Cell(%x)',
			(
				PyLong_FromSsize_t(self.value_0),
			)
		)


@cython.warn.maybe_uninitialized(False)
def get_answer(form_data, form_blocks):
	cdef object self = Answer()
	cdef object place_class
	cdef Py_ssize_t result
	cdef int_least16_t *numbers
	cdef Py_ssize_t *f_blocks

	# allocating blocks information
	f_blocks = <Py_ssize_t *>(
		malloc(
			(Py_SIZE(<tuple?>(form_blocks)) * 9 + 5) * sizeof(f_blocks[0])
		)
	)
	if f_blocks is NULL:
		raise MemoryError()
	try:
		place_class = parse_blocks(form_blocks, f_blocks)
		numbers = <int_least16_t *>(
			malloc(
				f_blocks[0] * sizeof(numbers[0]) * 2
			)
		)
		if numbers is NULL:
			raise MemoryError()
		try:
			result = parse_data(
				form_data,
				place_class._fields,
				f_blocks,
				numbers
			)
			if result == RESULT_UNCHANGED:
				(<Answer>(self))._tasks = -1
			else:
				result = check_numbers(f_blocks, numbers)
				if (result & (RESULT_SOLVED | RESULT_ERROR)) != 0:
					(<Answer>(self))._places = (
						make_place(
							place_class,
							f_blocks[0],
							numbers,
							0
						),
					)
				else:
					(<Answer>(self))._places = []
					(<Answer>(self)).solve(
						place_class,
						f_blocks,
						numbers,
						0
					)
		finally:
			free(numbers)
	finally:
		free(f_blocks)

	return self

