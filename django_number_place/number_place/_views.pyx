#cython: language_level=3,always_allow_keywords=False,binding=True,cdivision=True,c_string_encoding=utf-8,optimize.use_switch=True,optimize.unpack_method_calls=False,warn.maybe_uninitialized=True,warn.multiple_declarators=True,warn.undeclared=True,warn.unused=True,warn.unused_arg=False,warn.unused_result=False
# -*- coding: utf-8 -*-

cimport cython
from cpython.dict cimport (
	PyDict_GetItem,
	PyDict_SetItem,
)
from cpython.iterator cimport (
	PyIter_Next,
)
from cpython.list cimport (
	PyList_Append,
	PyList_AsTuple,
	PyList_GET_ITEM,
	PyList_SetSlice,
	PyList_Sort,
)
from cpython.long cimport (
	PyLong_AsSsize_t,
	PyLong_FromSsize_t,
	PyLong_FromSize_t,
)
from cpython.number cimport (
	PyNumber_Long,
)
from cpython.object cimport (
	Py_SIZE,
	Py_TYPE,
	PyObject,
	PyObject_GetIter,
	PyObject_GetItem,
	PyObject_Hash,
	PyObject_Size,
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
	PyUnicode_InternFromString,
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
	object __Pyx_PyDict_NewPresized(Py_ssize_t n)

cdef extern from '<stdlib.h>' nogil:
	ctypedef signed short int_fast16_t
	ctypedef signed short int_least16_t
	ctypedef unsigned int uint_fast16_t
	ctypedef signed int int_fast32_t
	ctypedef signed int int_least32_t

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

DEF MAX_DOUBLE_CROSS_BITS = 4


cdef struct DoubleCrossItem:
	DoubleCrossItem *next
	Py_ssize_t block_index
	int_fast16_t number_bits


cdef inline void sort_values_5(
	int_fast16_t *values_dst,
	const int_fast16_t *values_src
) nogil:
	cdef int_fast16_t value_0 = values_src[0]
	cdef int_fast16_t value_1 = values_src[1]
	cdef int_fast16_t value_2 = values_src[2]
	cdef int_fast16_t value_3 = values_src[3]
	cdef int_fast16_t value_4 = values_src[4]
	cdef int_fast16_t temp

	if value_0 > value_1:
		temp = value_0
		value_0 = value_1
		value_1 = temp
	# (value_0 < value_1) ? value_2 ? value_3 ? value_4
	if value_2 > value_3:
		temp = value_2
		value_2 = value_3
		value_3 = temp
	# (value_0 < value_1) ? (value_2 < value_3) ? value_4
	if value_0 > value_2:
		# (value_2 < ((value_0 < value_1) ? value_3) ? value_4
		temp = value_0
		value_0 = value_2
		value_2 = temp
		temp = value_1
		value_1 = value_3
		value_3 = temp
	# (value_0 < ((value_2 < value_3) ? value_1) ? value_4
	if value_2 < value_4:
		# (value_0 < value_2 < (value_3 ? value_4)) and (value_0 < value_1)
		values_dst[0] = value_0
		if value_3 > value_4:
			temp = value_3
			value_3 = value_4
			value_4 = temp
		# value_0 < ((value_2 < value_3 < value_4) ? value_1)
		if value_1 < value_3:
			# value_0 < (value_1 ? value_2) < value_3 < value_4
			values_dst[3] = value_3
			values_dst[4] = value_4
			if value_1 < value_2:
				# value_0 < value_1 < value_2 < value_3 < value_4
				values_dst[1] = value_1
				values_dst[2] = value_2
			else:
				# value_0 < value_2 < value_1 < value_3 < value_4
				values_dst[1] = value_2
				values_dst[2] = value_1
		else:
			# value_0 < value_2 < value_3 < (value_1 ? value_4)
			values_dst[1] = value_2
			values_dst[2] = value_3
			if value_1 < value_4:
				# value_0 < value_2 < value_3 < value_1 < value_4
				values_dst[3] = value_1
				values_dst[4] = value_4
			else:
				# value_0 < value_2 < value_3 < value_4 < value_1
				values_dst[3] = value_4
				values_dst[4] = value_1
	else:
		# ((value_0 ? value_4) < value_2 < value_3) and (value_0 < value_1)
		if value_0 < value_4:
			# value_0 < ((value_4 < value_2 < value_3) ? value_1)
			values_dst[0] = value_0
			if value_1 < value_2:
				# value_0 < (value_1 ? value_4) < value_2 < value_3
				values_dst[3] = value_2
				values_dst[4] = value_3
				if value_1 < value_4:
					# value_0 < value_1 < value_4 < value_2 < value_3
					values_dst[1] = value_1
					values_dst[2] = value_4
				else:
					# value_0 < value_4 < value_1 < value_2 < value_3
					values_dst[1] = value_4
					values_dst[2] = value_1
			else:
				# value_0 < value_4 < value_2 < (value_1 ? value_3)
				values_dst[0] = value_0
				values_dst[1] = value_4
				values_dst[2] = value_2
				if value_1 < value_3:
					# value_0 < value_4 < value_2 < value_1 < value_3
					values_dst[3] = value_1
					values_dst[4] = value_3
				else:
					# value_0 < value_4 < value_2 < value_3 < value_1
					values_dst[3] = value_3
					values_dst[4] = value_1
		else:
			# value_4 < value_0 < ((value_2 < value_3) ? value_1)
			values_dst[0] = value_4
			values_dst[1] = value_0
			if value_1 < value_2:
				# value_4 < value_0 < value_1 < value_2 < value_3
				values_dst[2] = value_1
				values_dst[3] = value_2
				values_dst[4] = value_3
			else:
				# value_4 < value_0 < value_2 < (value_1 ? value_3)
				values_dst[2] = value_2
				if value_1 < value_3:
					# value_4 < value_0 < value_2 < value_1 < value_3
					values_dst[3] = value_1
					values_dst[4] = value_3
				else:
					# value_4 < value_0 < value_2 < value_3 < value_1
					values_dst[3] = value_3
					values_dst[4] = value_1


cdef void sort_values(
	int_fast16_t *values_dst,
	const int_fast16_t *values_src,
	int_fast16_t values_count
) nogil:
	cdef int_fast16_t index_dst
	cdef int_fast16_t index_left_current
	cdef int_fast16_t index_left_end
	cdef int_fast16_t index_right_current
	cdef int_fast16_t value_left
	cdef int_fast16_t value_right
	cdef int_fast16_t *values_temp

	if values_count <= 1:
		pass
	elif values_count == 2:
		value_left = values_src[0]
		value_right = values_src[1]
		if value_left < value_right:
			values_dst[0] = value_left
			values_dst[1] = value_right
		else:
			values_dst[0] = value_right
			values_dst[1] = value_left
	elif values_count == 5:
		sort_values_5(values_dst, values_src)
	else:
		index_left_end = <int_fast16_t>(values_count >> 1)
		values_temp = <int_fast16_t *>(
			__builtin_alloca(index_left_end * sizeof(int_fast16_t))
		)
		sort_values(
			values_temp,
			values_src,
			index_left_end
			)
		sort_values(
			values_dst + index_left_end,
			values_src + index_left_end,
			values_count - index_left_end
		)

		index_dst = 0
		index_left_current = 0
		index_right_current = index_left_end
		value_left = values_temp[index_left_current]
		value_right = values_dst[index_right_current]
		while True:
			if value_left < value_right:
				values_dst[index_dst] = value_left
				index_left_current += 1
				index_dst += 1
				if index_left_current == index_left_end:
					# index_dst == index_right_current
					break
				value_left = values_temp[index_left_current]
			else:
				values_dst[index_dst] = value_right
				index_right_current += 1
				index_dst += 1
				if index_right_current == values_count:
					memcpy(
						values_dst + index_dst,
						values_temp + index_left_current,
						(index_left_end - index_left_current) * sizeof(int_fast16_t)
					)
					break
				value_right = values_dst[index_right_current]


cdef Py_ssize_t set_block_items(
	int_fast16_t *block_items,
	object form_blocks,
	object names
) except -128:
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef object block_values

	PyList_Sort(form_blocks)
	for index_0 in range(Py_SIZE(form_blocks)):
		block_values = <object>(PyList_GET_ITEM(form_blocks, index_0))
		for index_1 in range(9):
			block_items[index_0 * 9 + index_1] = <int_fast16_t>(
				PyLong_AsSsize_t(
					<object>(
						PyDict_GetItem(
							names,
							<object>(
								PyTuple_GET_ITEM(
									block_values,
									index_1
								)
							)
						)
					)
				)
			)
		sort_values(
			block_items + (index_0 * 9),
			block_items + (index_0 * 9),
			9
		)

	return 0


cdef inline object parse_blocks(
	object form_blocks,
	int_fast16_t **block_items_addr
):
	cdef Py_ssize_t index_0
	cdef Py_UCS4 row_name
	cdef Py_UCS4 col_name
	cdef int_fast16_t *block_items
	cdef object horizontal_form_blocks = []
	cdef object vertical_form_blocks = []
	cdef object other_form_blocks = []
	cdef object field_names = set()
	cdef object names = set()
	cdef object block_values
	cdef object form_name

	for block_values in form_blocks:
		block_values = list(block_values)

		if Py_SIZE(block_values) < 9:
			raise ValueError(
				PyUnicode_Format(
					'%s: The number of elements must be greater than 9.',
					(block_values,)
				)
			)

		# 1st loop
		form_name = <unicode?>(PyList_GET_ITEM(block_values, 0))
		if PyUnicode_GET_SIZE(form_name) != 2:
			raise ValueError(
				PyUnicode_Format(
					'%s: The length must be 2.',
					(form_name,)
				)
			)
		PySet_Clear(names)
		PySet_Add(names, form_name)
		PySet_Add(field_names, form_name)
		row_name = PyUnicode_READ_CHAR(form_name, 0)
		col_name = PyUnicode_READ_CHAR(form_name, 1)

		for index_0 in range(1, 9):
			# 2nd - 9th loops.
			form_name = <unicode?>(PyList_GET_ITEM(block_values, index_0))
			if PyUnicode_GET_SIZE(form_name) != 2:
				raise ValueError(
					PyUnicode_Format(
						'%s: The length must be 2.',
						(form_name,)
					)
				)
			if PySet_Contains(names, form_name) > 0:
				raise ValueError(
					PyUnicode_Format(
						'%s: Duplicate name %s.',
						(block_values, form_name,)
					)
				)
			PySet_Add(names, form_name)
			PySet_Add(field_names, form_name)
			if row_name != 0:
				if PyUnicode_READ_CHAR(form_name, 0) != row_name:
					row_name = 0
			if col_name != 0:
				if PyUnicode_READ_CHAR(form_name, 1) != col_name:
					col_name = 0

		block_values = PyList_AsTuple(block_values)

		if row_name != 0:
			PyList_Append(horizontal_form_blocks, block_values)
		elif col_name != 0:
			PyList_Append(vertical_form_blocks, block_values)
		else:
			PyList_Append(other_form_blocks, block_values)

	field_names = list(field_names)
	if Py_SIZE(field_names) > 0x7fff:
		raise ValueError(
			'The number of form_names must not exceed 0x7fff.'
		)
	PyList_Sort(field_names)
	field_names = PyList_AsTuple(field_names)
	names = {}
	block_items = <int_fast16_t *>(
		malloc(
			((Py_SIZE(horizontal_form_blocks)
			+ Py_SIZE(vertical_form_blocks)
			+ Py_SIZE(other_form_blocks)) * 9 + 5) * sizeof(int_fast16_t)
		)
	)
	if block_items is NULL:
		raise MemoryError()
	block_items_addr[0] = block_items

	for index_0 in range(Py_SIZE(field_names)):
		PyDict_SetItem(
			names,
			<object>(PyTuple_GET_ITEM(field_names, index_0)),
			PyLong_FromSsize_t(index_0)
		)

	block_items[0] = Py_SIZE(field_names)
	index_0 = 1
	# adding horizontal blocks
	block_items[index_0] = Py_SIZE(horizontal_form_blocks)
	index_0 += 1
	set_block_items(
		block_items + index_0,
		horizontal_form_blocks,
		names
	)
	index_0 += Py_SIZE(horizontal_form_blocks) * 9
	# adding vertical blocks
	block_items[index_0] = Py_SIZE(vertical_form_blocks)
	index_0 += 1
	set_block_items(
		block_items + index_0,
		vertical_form_blocks,
		names
	)
	index_0 += Py_SIZE(vertical_form_blocks) * 9
	# adding other blocks
	block_items[index_0] = Py_SIZE(other_form_blocks)
	index_0 += 1
	set_block_items(
		block_items + index_0,
		other_form_blocks,
		names
	)
	index_0 += Py_SIZE(other_form_blocks) * 9
	block_items[index_0] = -1

	return field_names


cdef inline Py_ssize_t check_number_items_block(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	Py_ssize_t result
) nogil:
	cdef Py_ssize_t solved_indexes[9]
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef int_fast16_t value_0
	cdef int_fast16_t value_1

	# initializing registered number_items (-1: unused)
	for index_0 in range(9):
		solved_indexes[index_0] = -1

	for index_0 in range(9):
		index_1 = block_items[index_0]
		value_0 = <int_fast16_t>(number_items[index_1])
		value_1 = <int_fast16_t>(value_0 & NUMBER_MASK)
		if value_1 == 0:
			number_items[index_1] = <int_least16_t>(
				value_0 | NUMBER_ERROR
			)
			result = RESULT_ERROR
		elif __builtin_popcount(value_1) == 1:
			index_3 = __builtin_ctz(value_1)
			index_2 = solved_indexes[index_3]
			if index_2 >= 0:
				# found multiple solved number.
				number_items[index_1] = <int_least16_t>(
					value_0 | NUMBER_ERROR
				)
				number_items[index_2] = <int_least16_t>(
					number_items[index_2] | NUMBER_ERROR
				)
				result = RESULT_ERROR
			solved_indexes[index_3] = index_1
		else:
			result &= (~RESULT_SOLVED)

	return result


cdef inline Py_ssize_t check_number_items(
	const int_fast16_t *block_items,
	int_least16_t *number_items
) nogil:
	cdef Py_ssize_t result = RESULT_SOLVED
	cdef Py_ssize_t index_0 = 1
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2

	index_1 = block_items[index_0]
	while index_1 > 0:
		index_0 += 1
		for index_2 in range(index_1):
			result = check_number_items_block(
				block_items + (index_0 + index_2 * 9),
				number_items,
				result
			)
		index_0 += index_1 * 9
		index_1 = block_items[index_0]

	return result


cdef inline Py_ssize_t parse_data(
	object form_data,
	object field_names,
	const int_fast16_t *block_items,
	int_least16_t *number_items
) except -128:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1

	for index_0 in range(block_items[0]):
		try:
			# if number is undefined, raise IndexError or ValueError
			index_1 = PyLong_AsSsize_t(
				PyNumber_Long(
					PyObject_GetItem(form_data, <object>(PyTuple_GET_ITEM(field_names, index_0)))
				)
			)
			if 1 <= index_1 and index_1 <= 9:
				number_items[index_0] = <int_least16_t>(
					(1 << (index_1 - 1)) | NUMBER_FIXED
				)
				result |= RESULT_CHANGED
				continue
		except:
			pass
		number_items[index_0] = NUMBER_MASK

	return result


cdef object make_place(
	object field_names,
	const int_least16_t *number_items,
	object method
):
	cdef Py_ssize_t index_0
	cdef object value_0
	cdef object result = __Pyx_PyDict_NewPresized(
		Py_SIZE(field_names) + 1
	)

	for index_0 in range(Py_SIZE(field_names)):
		value_0 = Cell()
		(<Cell>(value_0)).value_0 = <int_fast16_t>(number_items[index_0])
		PyDict_SetItem(
			result,
			<object>(PyTuple_GET_ITEM(field_names, index_0)),
			value_0
		)
	PyDict_SetItem(result, 'method', method)
	return result


cdef inline Py_ssize_t solve_method1_block(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	Py_ssize_t form_name_count,
	int_fast16_t value_0,
	Py_ssize_t result
) nogil:
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef int_fast16_t value_1
	cdef int_fast16_t value_2
	cdef int_fast16_t value_3
	cdef Py_ssize_t indexes_0 = 0
	cdef Py_ssize_t indexes_1 = 0

	for index_0 in range(9):
		index_1 = block_items[index_0]
		value_1 = <int_fast16_t>(
			number_items[index_1 + form_name_count] & NUMBER_MASK
		)
		if value_1 == value_0:
			indexes_0 |= (1 << index_0)
		elif (value_1 & value_0) == 0:
			indexes_1 |= (1 << index_0)

	value_1 = __builtin_popcount(value_0)
	if __builtin_popcount(indexes_0) == value_1:
		value_3 = <int_fast16_t>(~value_0)
		for index_0 in range(9):
			if (indexes_0 & (1 << index_0)) == 0:
				index_1 = block_items[index_0]
				value_1 = <int_fast16_t>(number_items[index_1])
				value_2 = <int_fast16_t>(value_1 & value_3)
				if value_2 != value_1:
					number_items[index_1] = <int_least16_t>(
						value_2 | NUMBER_CHANGED
					)
					result |= RESULT_CHANGED
	elif __builtin_popcount(indexes_1) == 9 - value_1:
		value_3 = <int_fast16_t>(value_0 | (~NUMBER_MASK))
		for index_0 in range(9):
			if (indexes_1 & (1 << index_0)) == 0:
				index_1 = block_items[index_0]
				value_1 = <int_fast16_t>(number_items[index_1])
				value_2 = <int_fast16_t>(value_1 & value_3)
				if value_2 != value_1:
					number_items[index_1] = <int_least16_t>(
						value_2 | NUMBER_CHANGED
					)
					result |= RESULT_CHANGED

	return result


cdef inline Py_ssize_t solve_method1(
	const int_fast16_t *block_items,
	int_least16_t *number_items
) nogil:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef Py_ssize_t index_0 = 1
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef int_fast16_t value_0

	index_1 = block_items[index_0]
	while index_1 > 0:
		index_0 += 1
		for index_2 in range(index_1):
			for value_0 in range(1, (1 << 9) - 1):
				result = solve_method1_block(
					block_items + (index_0 + index_2 * 9),
					number_items,
					block_items[0],
					value_0,
					result
				)
		index_0 += index_1 * 9
		index_1 = block_items[index_0]

	return result


cdef int_fast16_t solve_method2_find(
	const int_fast16_t *block_items,
	Py_ssize_t block_filter_index,	    # first double cross index of block_items
	int_fast16_t number_bits,
	Py_ssize_t block_reduce_index	    # second double cross index of block_items
) except -128:
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef int_fast16_t index_2
	cdef int_fast16_t index_3

	for index_0 in range(9):
		if (number_bits & (1 << index_0)) != 0:
			index_2 = block_items[block_filter_index + index_0]
			for index_1 in range(9):
				index_3 = block_items[block_reduce_index + index_1]
				if index_3 == index_2:
					return <int_fast32_t>(
						(number_bits & (~(1 << index_0))) | (index_1 << 9)
					)
				elif index_3 > index_2:
					break

	return -1


cdef int_fast16_t solve_method2_find2(
	const int_fast16_t *block_items,
	int_fast16_t block_filter_index,	    # first double cross index of block_items
	int_fast16_t block_reduce_index	    # second double cross index of block_items
) except -128:
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef int_fast16_t index_2
	cdef int_fast16_t index_3

	for index_0 in range(9):
		index_2 = block_items[block_filter_index + index_0]
		for index_1 in range(9):
			index_3 = block_items[block_reduce_index + index_1]
			if index_3 == index_2:
				return <int_fast16_t>(index_1 << 9)
			elif index_3 > index_2:
				break

	return -1


cdef inline Py_ssize_t solve_method2_replace(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	int_fast16_t *double_cross_indexes,
	int_fast16_t number_bits_count,          # number of candidate items
	int_fast16_t match_number_bit,       # double cross value bit
	Py_ssize_t block_reduce_index,         # second double cross index of block_items
	int_fast16_t *values_temp
) except -128:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef int_fast16_t cross_number_bits

	# found blocks, processing reduce
	for index_1 in range(number_bits_count):
		cross_number_bits = 0
		for index_2 in range(number_bits_count):
			cross_number_bits = <int_fast16_t>(
				cross_number_bits | (1 << (values_temp[number_bits_count * (index_1 + 2) + index_2] >> 9))
			)

		index_3 = block_reduce_index + 1 + values_temp[number_bits_count * 1 + index_1] * 9
		for index_2 in range(9):
			if (cross_number_bits & (1 << index_2)) == 0:
				index_2 = block_items[index_3 + index_2]
				if (number_items[index_2 + block_items[0]] & match_number_bit) != 0:
					number_items[index_2] = <int_least16_t>(
						(number_items[index_2] & (~(match_number_bit))) | NUMBER_CHANGED
					)
					result |= RESULT_CHANGED

	if result == RESULT_UNCHANGED:
		# registering for temporary decide items
		if number_bits_count == 2:
			if double_cross_indexes[0] == 0:
				double_cross_indexes[0] = match_number_bit
				for index_1 in range(number_bits_count):
					index_3 = block_reduce_index + 1 + values_temp[number_bits_count * 1 + index_1] * 9
					for index_2 in range(number_bits_count):
						double_cross_indexes[index_2 * number_bits_count + index_1 + 1] = block_items[
							index_3 + (values_temp[number_bits_count * (index_1 + 2) + index_2] >> 9)
						]
	else:
		# setting double cross mark
		for index_1 in range(number_bits_count):
			index_3 = block_reduce_index + 1 + values_temp[number_bits_count * 1 + index_1] * 9
			for index_2 in range(number_bits_count):
				index_2 = block_items[
					index_3 + (values_temp[number_bits_count * (index_1 + 2) + index_2] >> 9)
				]
				number_items[index_2] = <int_least16_t>(
					number_items[index_2] | NUMBER_DOUBLE_CROSS
				)

	return result


cdef Py_ssize_t solve_method2_check_candidates_3(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	int_fast16_t *double_cross_indexes,
	int_fast16_t number_bits_count,         # number of candidate items
	int_fast16_t match_number_bit,
	Py_ssize_t block_reduce_index,         # second double cross index of block_items
	int_fast16_t *values_temp,
	Py_ssize_t result,
	Py_ssize_t index_0,         # index of second double cross blocks
	Py_ssize_t index_3          # index of candidate item
) except -128:
	cdef Py_ssize_t index_4
	cdef int_fast16_t remain_number_bits
	cdef int_fast16_t find_result

	if values_temp[number_bits_count * 1 + 0] != index_0:
		for index_4 in range(number_bits_count):
			remain_number_bits = <int_fast16_t>(
				values_temp[number_bits_count * (index_3 + 1) + index_4] & NUMBER_MASK
			)
			find_result = solve_method2_find(
				block_items,
				values_temp[number_bits_count * 0 + index_4],
				remain_number_bits,
				block_reduce_index + 1 + index_0 * 9
			)
			if find_result < 0:
				if __builtin_popcount(remain_number_bits) >= (number_bits_count - index_3):
					return result
				find_result = solve_method2_find2(
					block_items,
					values_temp[number_bits_count * 0 + index_4],
					block_reduce_index + 1 + index_0 * 9
				)
				if find_result < 0:
					return result
				find_result = <int_fast16_t>(
					remain_number_bits | find_result
				)
			values_temp[number_bits_count * (index_3 + 2) + index_4] = find_result

		values_temp[number_bits_count * 1 + index_3] = index_0
		if (index_3 + 1) < number_bits_count:
			for index_4 in range(index_0 + 1, block_items[block_reduce_index] - (number_bits_count - (index_3 + 1))):
				result = solve_method2_check_candidates_3(
					block_items,
					number_items,
					double_cross_indexes,
					number_bits_count,
					match_number_bit,
					block_reduce_index,
					values_temp,
					result,
					index_4,
					index_3 + 1
				)
		else:
			result |= solve_method2_replace(
				block_items,
				number_items,
				double_cross_indexes,
				number_bits_count,
				match_number_bit,
				block_reduce_index,
				values_temp
			)

	return result


cdef Py_ssize_t solve_method2_check_candidates_2(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	int_fast16_t *double_cross_indexes,
	int_fast16_t number_bits_count,         # number of candidate items
	int_fast16_t match_number_bit,       # double cross value bit
	Py_ssize_t block_reduce_index,         # second double cross index of block_items
	int_fast16_t *values_temp,
	Py_ssize_t result,
	DoubleCrossItem *item_0,
	Py_ssize_t index_3,         # index of candidate item
	Py_ssize_t index_0          # index of second double cross blocks
) except -128:
	cdef Py_ssize_t index_4
	cdef int_fast16_t find_result

	# checking candidate items
	while item_0 is not NULL:
		find_result = solve_method2_find(
			block_items,
			item_0.block_index,
			item_0.number_bits,
			block_reduce_index + 1 + index_0 * 9
		)
		if find_result < 0:
			if __builtin_popcount(item_0.number_bits) >= number_bits_count:
				item_0 = item_0.next
				continue
			find_result = solve_method2_find2(
				block_items,
				item_0.block_index,
				block_reduce_index + 1 + index_0 * 9
			)
			if find_result < 0:
				item_0 = item_0.next
				continue
			find_result = <int_fast16_t>(
				item_0.number_bits | find_result
			)

		values_temp[number_bits_count * 0 + index_3] = item_0.block_index
		values_temp[number_bits_count * 2 + index_3] = find_result
		if (index_3 + 1) < number_bits_count:
			result = solve_method2_check_candidates_2(
				block_items,
				number_items,
				double_cross_indexes,
				number_bits_count,
				match_number_bit,
				block_reduce_index,
				values_temp,
				result,
				item_0.next,
				index_3 + 1,
				index_0
			)
		else:
			values_temp[number_bits_count * 1 + 0] = index_0
			for index_4 in range(block_items[block_reduce_index] - (number_bits_count - 2)):
				result = solve_method2_check_candidates_3(
					block_items,
					number_items,
					double_cross_indexes,
					number_bits_count,
					match_number_bit,
					block_reduce_index,
					values_temp,
					result,
					index_4,
					1
				)
		item_0 = item_0.next

	return result


cdef inline Py_ssize_t solve_method2_check_candidates_1(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	int_fast16_t *double_cross_indexes,
	int_fast16_t number_bits_count,         # number of candidate items
	int_fast16_t match_number_bit,       # double cross value bit
	Py_ssize_t block_reduce_index,         # second double cross index of block_items
	int_fast16_t *values_temp,
	Py_ssize_t result,
	DoubleCrossItem *item_0,
	DoubleCrossItem *item_1,
	Py_ssize_t index_0         # index of second double cross blocks
) except -128:
	cdef int_fast16_t find_result

	# checking candidate items
	while item_0 is not item_1:
		find_result = solve_method2_find(
			block_items,
			item_0.block_index,
			item_0.number_bits,
			block_reduce_index + 1 + index_0 * 9
		)
		if find_result >= 0:
			values_temp[number_bits_count * 0 + 0] = item_0.block_index
			values_temp[number_bits_count * 2 + 0] = find_result
			result = solve_method2_check_candidates_2(
				block_items,
				number_items,
				double_cross_indexes,
				number_bits_count,
				match_number_bit,
				block_reduce_index,
				values_temp,
				result,
				item_0.next,
				1,
				index_0
			)
		item_0 = item_0.next

	return result


cdef Py_ssize_t solve_method2_main(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	int_fast16_t *double_cross_indexes,
	int_fast16_t number_bits_count,
	int_fast16_t match_number_bit,
	Py_ssize_t block_reduce_index,
	Py_ssize_t block_filter_index,
	Py_ssize_t result
) except -128:
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef DoubleCrossItem *item_0 = NULL
	cdef DoubleCrossItem *item_1 = NULL
	cdef DoubleCrossItem *item_2
	cdef DoubleCrossItem **item_end_0 = &(item_0)
	cdef DoubleCrossItem **item_end_1 = &(item_1)
	cdef int_fast16_t number_bits
	cdef uint_fast16_t popcount_minus_2
	cdef int_fast16_t values_temp[MAX_DOUBLE_CROSS_BITS * (MAX_DOUBLE_CROSS_BITS + 2)]

	# finding candidate items
	for index_0 in range(block_items[block_filter_index]):
		index_0 = block_filter_index + 1 + index_0 * 9
		# finding candidate items
		number_bits = 0
		for index_1 in range(9):
			index_2 = block_items[index_0 + index_1]
			if (number_items[index_2 + block_items[0]] & match_number_bit) != 0:
				# found a candidate index
				number_bits |= (1 << index_1)
		popcount_minus_2 = <uint_fast16_t>(__builtin_popcount(number_bits) - 2)
		if popcount_minus_2 == <uint_fast16_t>(number_bits_count - 2):
			item_2 = <DoubleCrossItem *>(
				__builtin_alloca(sizeof(DoubleCrossItem))
			)
			item_2.block_index = index_0
			item_2.number_bits = number_bits
			item_end_0[0] = item_2
			item_end_0 = (&(item_2.next))
		elif popcount_minus_2 < <uint_fast16_t>(number_bits_count - 2):
			# found candicate indexes
			item_2 = <DoubleCrossItem *>(
				__builtin_alloca(sizeof(DoubleCrossItem))
			)
			item_2.block_index = index_0
			item_2.number_bits = number_bits
			item_end_1[0] = item_2
			item_end_1 = (&(item_2.next))

	item_end_1[0] = NULL
	item_end_0[0] = item_1
	for index_0 in range(block_items[block_reduce_index]):
		result = solve_method2_check_candidates_1(
			block_items,
			number_items,
			double_cross_indexes,
			number_bits_count,
			match_number_bit,
			block_reduce_index,
			values_temp,
			result,
			item_0,
			item_1,
			index_0
		)

	return result


cdef inline Py_ssize_t solve_method2(
	const int_fast16_t *block_items,
	int_least16_t *number_items,
	int_fast16_t *double_cross_indexes
) except -128:
	cdef Py_ssize_t result = RESULT_UNCHANGED
	cdef int_fast16_t match_number_bit
	cdef int_fast16_t number_bits_count

	for number_bits_count in range(2, MAX_DOUBLE_CROSS_BITS + 1):
		match_number_bit = 1
		while True:
			# check vertical block, filter horizontal block
			result = solve_method2_main(
				block_items,
				number_items,
				double_cross_indexes,
				number_bits_count,
				match_number_bit,
				block_items[1] * 9 + 2,
				1,
				result
			)
			# check horizontal block, filter vertical block
			result = solve_method2_main(
				block_items,
				number_items,
				double_cross_indexes,
				number_bits_count,
				match_number_bit,
				1,
				block_items[1] * 9 + 2,
				result
			)
			if match_number_bit == (1 << 9):
				break
			match_number_bit <<= 1

		if result != RESULT_UNCHANGED:
			break

	return result


cdef inline Py_ssize_t find_candidate_index(
	const int_fast16_t *block_items,
	const int_least16_t *number_items
) nogil:
	cdef Py_ssize_t index_0 = 0
	cdef Py_ssize_t index_1
	cdef int_fast16_t value_0 = 10
	cdef int_fast16_t value_1

	for index_1 in range(block_items[0]):
		value_1 = __builtin_popcount(number_items[index_1] & NUMBER_MASK)
		if value_1 == 2:
			index_0 = index_1
			break
		elif value_1 > 2:
			if value_1 < value_0:
				index_0 = index_1
				value_0 = value_1

	return index_0


@cython.auto_pickle(False)
@cython.final
cdef class Answer():
	cdef object _places
	cdef object _children
	cdef Py_ssize_t _tasks


	cdef Py_ssize_t solve(
		self,
		object field_names,
		const int_fast16_t *block_items,
		int_least16_t *number_items,
		Py_ssize_t solved_count
	) except -128:
		cdef Py_ssize_t result
		cdef Py_ssize_t new_solved_count
		cdef Py_ssize_t index_0
		cdef Py_ssize_t number_bit
		cdef int_least16_t *saved_number_items
		cdef object child
		cdef object _children
		cdef int_fast16_t double_cross_indexes[2 * 2 + 1]

		# processing: Exclude verified number_items.
		while True:
			memcpy(
				number_items + block_items[0],
				number_items,
				block_items[0] * sizeof(number_items[0])
			)

			result = solve_method1(block_items, number_items)
			if result != RESULT_UNCHANGED:
				child = 1
			else:
				double_cross_indexes[0] = 0
				result = solve_method2(block_items, number_items, double_cross_indexes)
				if result != RESULT_UNCHANGED:
					child = 2
				else:
					break

			result = check_number_items(block_items, number_items)
			PyList_Append(
				self._places,
				make_place(field_names, number_items, child)
			)
			if result != 0:
				self._tasks += Py_SIZE(self._places)
				self._places = PyList_AsTuple(self._places)
				return 1 if (result & (RESULT_SOLVED)) != 0 else 0

			# resetting CHANGED/DOUBLE CROSS state
			for index_0 in range(block_items[0]):
				number_items[index_0] = <int_least16_t>(
					number_items[index_0] & (~(NUMBER_CHANGED | NUMBER_DOUBLE_CROSS))
				)

		# processing: Temporarily decide the number.
		_children = []
		self._children = []
		new_solved_count = 0
		saved_number_items = <int_least16_t *>(
			malloc(block_items[0] * sizeof(number_items[0]))
		)
		if saved_number_items is NULL:
			raise MemoryError()
		try:
			memcpy(
				saved_number_items,
				number_items,
				block_items[0] * sizeof(number_items[0])
			)
			number_bit = double_cross_indexes[0]
			if number_bit != 0:
				# first double cross items
				if solved_count + new_solved_count < MAX_SOLVED:
					index_0 = double_cross_indexes[1 + 0]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					index_0 = double_cross_indexes[1 + 3]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					index_0 = double_cross_indexes[1 + 1]
					number_items[index_0] = <int_least16_t>(
						(number_items[index_0] & (~(number_bit))) | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					index_0 = double_cross_indexes[1 + 2]
					number_items[index_0] = <int_least16_t>(
						(number_items[index_0] & (~(number_bit))) | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					child = Answer()
					(<Answer>(child))._places = [
						make_place(
							field_names,
							number_items,
							3
						)
					]
					index_0 = double_cross_indexes[1 + 0]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_TEMP
					)
					index_0 = double_cross_indexes[1 + 3]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_TEMP
					)
					index_0 = double_cross_indexes[1 + 1]
					number_items[index_0] = <int_least16_t>(
						number_items[index_0] & (~(NUMBER_CHANGED | NUMBER_DOUBLE_CROSS))
					)
					index_0 = double_cross_indexes[1 + 2]
					number_items[index_0] = <int_least16_t>(
						number_items[index_0] & (~(NUMBER_CHANGED | NUMBER_DOUBLE_CROSS))
					)
					result = (<Answer>(child)).solve(
						field_names,
						block_items,
						number_items,
						solved_count + new_solved_count
					)
					memcpy(
						number_items,
						saved_number_items,
						block_items[0] * sizeof(number_items[0])
					)
					self._tasks += (<Answer>(child))._tasks
					PyList_Append(self._children, child)
					if result > 0:
						PyList_Append(_children, child)
						new_solved_count += result

				# second double cross items
				if solved_count + new_solved_count < MAX_SOLVED:
					index_0 = double_cross_indexes[1 + 1]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					index_0 = double_cross_indexes[1 + 2]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					index_0 = double_cross_indexes[1 + 0]
					number_items[index_0] = <int_least16_t>(
						(number_items[index_0] & (~(number_bit))) | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					index_0 = double_cross_indexes[1 + 3]
					number_items[index_0] = <int_least16_t>(
						(number_items[index_0] & (~(number_bit))) | NUMBER_CHANGED | NUMBER_DOUBLE_CROSS
					)
					child = Answer()
					(<Answer>(child))._places = [
						make_place(
							field_names,
							number_items,
							3
						)
					]
					index_0 = double_cross_indexes[1 + 1]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_TEMP
					)
					index_0 = double_cross_indexes[1 + 2]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_TEMP
					)
					index_0 = double_cross_indexes[1 + 0]
					number_items[index_0] = <int_least16_t>(
						number_items[index_0] & (~(NUMBER_CHANGED | NUMBER_DOUBLE_CROSS))
					)
					index_0 = double_cross_indexes[1 + 3]
					number_items[index_0] = <int_least16_t>(
						number_items[index_0] & (~(NUMBER_CHANGED | NUMBER_DOUBLE_CROSS))
					)
					result = (<Answer>(child)).solve(
						field_names,
						block_items,
						number_items,
						solved_count + new_solved_count
					)
					memcpy(
						number_items,
						saved_number_items,
						block_items[0] * sizeof(number_items[0])
					)
					self._tasks += (<Answer>(child))._tasks
					PyList_Append(self._children, child)
					if result > 0:
						PyList_Append(_children, child)
						new_solved_count += result
			else:
				# Assign a value to a single block whose answer has not been determined
				# because it cannot be resolved any further.
				index_0 = find_candidate_index(block_items, number_items)
				for number_bit in range(9):
					number_bit = (1 << number_bit)
					if (number_items[index_0] & number_bit) == 0:
						continue
					if solved_count + new_solved_count >= MAX_SOLVED:
						break

					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_CHANGED
					)
					child = Answer()
					(<Answer>(child))._places = [
						make_place(
							field_names,
							number_items,
							3
						)
					]
					number_items[index_0] = <int_least16_t>(
						number_bit | NUMBER_TEMP
					)
					result = (<Answer>(child)).solve(
						field_names,
						block_items,
						number_items,
						solved_count + new_solved_count
					)
					memcpy(
						number_items,
						saved_number_items,
						block_items[0] * sizeof(number_items[0])
					)
					self._tasks += (<Answer>(child))._tasks
					PyList_Append(self._children, child)
					if result > 0:
						PyList_Append(_children, child)
						new_solved_count += result

		finally:
			free(saved_number_items)

		result = Py_SIZE(_children)
		if result == 0:
			_children = self._children
			result = Py_SIZE(_children)
		if result == 0:
			self._children = None
		elif result == 1:
			child = <object>(PyList_GET_ITEM(_children, 0))
			PyList_SetSlice(
				self._places,
				Py_SIZE(self._places),
				Py_SIZE(self._places),
				(<Answer>(child))._places
			)
			self._tasks -= Py_SIZE((<Answer>(child))._places)
			self._children = (<Answer>(child))._children
		else:
			self._children = PyList_AsTuple(_children)

		self._tasks += Py_SIZE(self._places)
		self._places = PyList_AsTuple(self._places)
		return new_solved_count


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
		cdef char state_str[9]
		cdef int_fast16_t value_0 = self.value_0
		cdef Py_ssize_t state_size = 0

		if (value_0 & (NUMBER_FIXED | NUMBER_TEMP)) == 0:
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				state_str[state_size + 0] = b' '
				state_str[state_size + 1] = b'u'
				state_size += 2
		elif (value_0 & NUMBER_FIXED) != 0:
			state_str[state_size + 0] = b' '
			state_str[state_size + 1] = b'f'
			state_size += 2
		else:
			state_str[state_size + 0] = b' '
			state_str[state_size + 1] = b't'
			state_size += 2

		if (value_0 & NUMBER_CHANGED) != 0:
			state_str[state_size + 0] = b' '
			state_str[state_size + 1] = b'c'
			state_size += 2
		if (value_0 & NUMBER_DOUBLE_CROSS) != 0:
			state_str[state_size + 0] = b' '
			state_str[state_size + 1] = b'd'
			state_size += 2
		if (value_0 & NUMBER_ERROR) != 0:
			state_str[state_size + 0] = b' '
			state_str[state_size + 1] = b'e'
			state_size += 2
		state_str[state_size] = b'\0'

		return PyUnicode_InternFromString(state_str)


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
	cdef object field_names
	cdef Py_ssize_t result
	cdef int_least16_t *number_items
	cdef int_fast16_t *block_items = NULL

	# allocating blocks information
	result = PyObject_Size(form_blocks)
	if result > (0x8000 - 5) // 9:
		raise ValueError('Too many form_blocks!')
	block_items = <int_fast16_t *>(
		malloc((result * 9 + 5) * sizeof(int_fast16_t))
	)
	field_names = parse_blocks(form_blocks, &block_items)
	try:
		number_items = <int_least16_t *>(
			malloc(
				block_items[0] * sizeof(int_least16_t) * 2
			)
		)
		if number_items is NULL:
			raise MemoryError()
		try:
			result = parse_data(
				form_data,
				field_names,
				block_items,
				number_items
			)
			if result == RESULT_UNCHANGED:
				(<Answer>(self))._tasks = -1
			else:
				result = check_number_items(block_items, number_items)
				if (result & (RESULT_SOLVED | RESULT_ERROR)) != 0:
					(<Answer>(self))._places = (
						make_place(
							field_names,
							number_items,
							0
						),
					)
				else:
					(<Answer>(self))._places = []
					(<Answer>(self)).solve(
						field_names,
						block_items,
						number_items,
						0
					)
		finally:
			free(number_items)
	finally:
		free(block_items)

	return self
