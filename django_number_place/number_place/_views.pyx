#cython: language_level=3
# -*- coding: utf-8 -*-

cimport cython
from cpython.bytes cimport (
	PyBytes_AS_STRING,
)
from cpython.dict cimport (
	PyDict_Contains,
	PyDict_GetItem,
	PyDict_SetItem,
	PyDict_Size,
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
	PyObject_Hash,
)
from cpython.ref cimport (
	Py_INCREF,
	Py_XDECREF,
)
from cpython.set cimport (
	PySet_Add,
	PySet_Clear,
	PySet_New,
)
from cpython.tuple cimport (
	PyTuple_GET_ITEM,
	PyTuple_New,
	PyTuple_SET_ITEM,
)
from cpython.unicode cimport (
	PyUnicode_DecodeLatin1,
	PyUnicode_Format,
)
from libc.stdlib cimport (
	free,
	malloc,
)

cdef extern from '<stdlib.h>' nogil:
	ctypedef signed short int_fast16_t
	ctypedef signed short int_least16_t

cdef extern from 'builtin.h' nogil:
	int __builtin_popcount(int value)
	int __builtin_ctz(int value)


cdef enum:
	NUMBER_MASK         = 0x01ff
	NUMBER_CHANGED      = 0x0200
	NUMBER_FIXED        = 0x0400
	NUMBER_TEMP         = 0x0800
	NUMBER_ERROR        = 0x1000

	RESULT_UNCHANGED    = 0x0
	RESULT_CHANGED      = 0x1
	RESULT_SOLVED       = 0x2
	RESULT_ERROR        = 0x4

	MAX_SOLVED          = 3

import sys


cdef object parse_blocks(
	object form_blocks,
	Py_ssize_t *blocks
):
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef object names = {}
	cdef object field_names = []
	cdef object block
	cdef object name
	cdef object namedtuple
	cdef PyObject *object_0

	from collections import namedtuple

	for index_0 in range(Py_SIZE(form_blocks)):
		block = <tuple?>(<object>(PyTuple_GET_ITEM(form_blocks, index_0)))
		if Py_SIZE(block) < 9:
			raise ValueError()
		for index_1 in range(9):
			name = <object>(PyTuple_GET_ITEM(block, index_1))
			if (name == 'method'):
				raise ValueError()
			object_0 = PyDict_GetItem(names, name)
			if object_0 is NULL:
				index_2 = Py_SIZE(field_names)
				PyDict_SetItem(names, name, PyLong_FromSsize_t(index_2))
				PyList_Append(field_names, name)
			else:
				index_2 = PyLong_AsSsize_t(<object>(object_0))
			blocks[index_0 * 9 + index_1] = index_2
	blocks[Py_SIZE(form_blocks) * 9] = -1

	PyList_Append(field_names, 'method')
	return namedtuple(
		PyUnicode_Format(
			'Place%x',
			(
				PyLong_FromSize_t(PyObject_Hash(PyList_AsTuple(field_names))),
			)
		),
		field_names
	)


cdef Py_ssize_t check_numbers(
	const Py_ssize_t *form_blocks,
	int_least16_t *numbers
) nogil:
	cdef Py_ssize_t result = RESULT_SOLVED
	cdef Py_ssize_t solved_indexes[9]
	cdef Py_ssize_t index_0 = 0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef Py_ssize_t index_4
	cdef int_fast16_t value_0
	cdef int_fast16_t value_1

	# if form data isn't empty, checking numbers.
	while form_blocks[index_0] >= 0:
		# initializing registered numbers (-1: unused)
		for index_1 in range(9):
			solved_indexes[index_1] = -1

		for index_1 in range(9):
			index_2 = form_blocks[index_0 + index_1]
			value_0 = numbers[index_2]
			value_1 = (value_0 & NUMBER_MASK)
			if value_1 == 0:
				numbers[index_2] = <int_least16_t>(value_0 | NUMBER_ERROR)
				result |= RESULT_ERROR
			elif __builtin_popcount(value_1) == 1:
				index_4 = __builtin_ctz(value_1)
				index_3 = solved_indexes[index_4]
				if index_3 >= 0:
					# found multiple solved number.
					numbers[index_2] = <int_least16_t>(value_0 | NUMBER_ERROR)
					numbers[index_3] = <int_least16_t>(numbers[index_3] | NUMBER_ERROR)
					result |= RESULT_ERROR
				solved_indexes[index_4] = index_2
			else:
				result &= (~RESULT_SOLVED)
		index_0 += 9

	return result


cdef Py_ssize_t parse_data(
	object form_data,
	object place_fields,
	const Py_ssize_t *form_blocks,
	int_least16_t *numbers,
) except -1:
	cdef Py_ssize_t result = 0
	cdef Py_ssize_t index_0
	cdef Py_ssize_t index_1
	cdef object name
	cdef object value_0

	# reading data from
	for index_0 in range(Py_SIZE(place_fields) - 1):
		name = <object>(PyTuple_GET_ITEM(place_fields, index_0))
		try:
			# if number is undefined, raise IndexError or ValueError
			index_1 = PyLong_AsSsize_t(PyNumber_Long(form_data[name]))
			if 1 <= index_1 and index_1 <= 9:
				numbers[index_0] = <int_least16_t>((1 << (index_1 - 1)) | NUMBER_FIXED)
				result |= RESULT_CHANGED
				continue
		except:
			pass
		numbers[index_0] = NUMBER_MASK

	if result != 0:
		# if form data isn't empty, checking numbers.
		result |= check_numbers(form_blocks, numbers)

	return result


cdef object make_place(
	object place_class,
	Py_ssize_t form_name_count,
	const int_least16_t *numbers,
	object method
):
	cdef Py_ssize_t index_0
	cdef int_fast16_t value_0
	cdef object values = PyTuple_New(form_name_count + 1)
	cdef object value_1

	for index_0 in range(form_name_count):
		value_1 = Cell()
		(<Cell>(value_1)).value_0 = <int_fast16_t>(numbers[index_0])
		Py_INCREF(value_1)
		PyTuple_SET_ITEM(values, index_0, value_1)
	Py_INCREF(method)
	PyTuple_SET_ITEM(values, form_name_count + 0, method)
	return place_class(*values)


cdef Py_ssize_t solve_method1(
	Py_ssize_t form_name_count,
	const Py_ssize_t *form_blocks,
	int_least16_t *numbers
) nogil:
	cdef Py_ssize_t result = 0
	cdef Py_ssize_t index_0 = 0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef int_fast16_t value_0
	cdef int_fast16_t value_1
	cdef int_fast16_t value_2
	cdef Py_ssize_t indexes_0

	# if number is fixed or solved, other numbers in block reduce fixed number.
	while form_blocks[index_0] >= 0:
		# finding solved indexes
		indexes_0 = 0
		value_2 = -1
		for index_1 in range(9):
			index_2 = form_blocks[index_0 + index_1]
			value_0 = (numbers[index_2 + form_name_count] & NUMBER_MASK)
			if __builtin_popcount(value_0) == 1:
				value_2 &= (~value_0)
				indexes_0 |= (1 << index_1)

		for index_1 in range(9):
			if (indexes_0 & (1 << index_1)) == 0:
				index_2 = form_blocks[index_0 + index_1]
				value_0 = numbers[index_2]
				value_1 = (value_0 & value_2)
				if value_1 != value_0:
					numbers[index_2] = <int_least16_t>(value_1 | NUMBER_CHANGED)
					result |= RESULT_CHANGED
		index_0 += 9

	if result != 0:
		# if form data isn't empty, checking numbers.
		result |= check_numbers(form_blocks, numbers)

	return result


cdef Py_ssize_t solve_method2(
	Py_ssize_t form_name_count,
	const Py_ssize_t *form_blocks,
	int_least16_t *numbers
) nogil:
	cdef Py_ssize_t result = 0
	cdef Py_ssize_t index_0 = 0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef Py_ssize_t index_4
	cdef Py_ssize_t index_5
	cdef int_fast16_t value_0
	cdef int_fast16_t value_1
	cdef int_fast16_t value_2
	cdef int_fast16_t value_3
	cdef int_fast16_t value_4
	cdef Py_ssize_t indexes_0

	while form_blocks[index_0] >= 0:
		indexes_0 = 0
		value_2 = 0
		for index_1 in range(9):
			if (indexes_0 & (1 << index_1)) == 0:
				index_2 = form_blocks[index_0 + index_1]
				value_0 = numbers[index_2 + form_name_count]
				value_2 = (value_0 & NUMBER_MASK)
				if __builtin_popcount(value_2) == 2:
					index_2 = -1
					for index_3 in range(index_1 + 1, 9):
						index_4 = form_blocks[index_0 + index_3]
						value_0 = (numbers[index_4 + form_name_count] & NUMBER_MASK)
						if value_0 == value_2:
							if index_2 >= 0:
								break
							index_2 = index_3
					else:
						if index_2 >= 0:
							value_2 = (~value_2)
							for index_3 in range(index_1):
								index_4 = form_blocks[index_0 + index_3]
								value_0 = (numbers[index_4] & NUMBER_MASK)
								value_1 = (value_0 & value_2)
								if value_1 != value_0:
									numbers[index_4] = <int_least16_t>(value_1 | NUMBER_CHANGED)
									result |= RESULT_CHANGED
							for index_3 in range(index_1 + 1, index_2):
								index_4 = form_blocks[index_0 + index_3]
								value_0 = (numbers[index_4] & NUMBER_MASK)
								value_1 = (value_0 & value_2)
								if value_1 != value_0:
									numbers[index_4] = <int_least16_t>(value_1 | NUMBER_CHANGED)
									result |= RESULT_CHANGED
							for index_3 in range(index_2 + 1, 9):
								index_4 = form_blocks[index_0 + index_3]
								value_0 = (numbers[index_4] & NUMBER_MASK)
								value_1 = (value_0 & value_2)
								if value_1 != value_0:
									numbers[index_4] = <int_least16_t>(value_1 | NUMBER_CHANGED)
									result |= RESULT_CHANGED
		index_0 += 9

	if result != 0:
		# if form data isn't empty, checking numbers.
		result |= check_numbers(form_blocks, numbers)

	return result


cdef Py_ssize_t solve_method3(
	Py_ssize_t form_name_count,
	const Py_ssize_t *form_blocks,
	int_least16_t *numbers
) except -1:
	cdef Py_ssize_t result = 0
	cdef Py_ssize_t index_0 = 0
	cdef Py_ssize_t index_1
	cdef Py_ssize_t index_2
	cdef Py_ssize_t index_3
	cdef int_fast16_t value_0
	cdef int_fast16_t value_1
	cdef int_fast16_t value_2
	cdef int_fast16_t value_3
	cdef int_fast16_t value_4
	cdef Py_ssize_t indexes_0
	cdef Py_ssize_t indexes_1


	while form_blocks[index_0] >= 0:
		# finding solved indexes
		indexes_0 = 0
		value_2 = 0
		for index_1 in range(9):
			index_2 = form_blocks[index_0 + index_1]
			value_0 = (numbers[index_2 + form_name_count] & NUMBER_MASK)
			if __builtin_popcount(value_0) == 1:
				value_2 |= value_0
				indexes_0 |= (1 << index_1)

		for value_3 in range(1, NUMBER_MASK):
			if (value_3 & value_2) == 0:
				indexes_1 = 0
				for index_1 in range(9):
					if (indexes_0 & (1 << index_1)) == 0:
						index_2 = form_blocks[index_0 + index_1]
						value_0 = numbers[index_2 + form_name_count]
						if (value_0 & value_3) != 0:
							indexes_1 |= (1 << index_1)

				if __builtin_popcount(indexes_1) == __builtin_popcount(value_3):
					value_4 = (~value_3)
					value_3 |= (~NUMBER_MASK)
					for index_1 in range(9):
						if (indexes_0 & (1 << index_1)) == 0:
							index_2 = form_blocks[index_0 + index_1]
							value_0 = numbers[index_2]
							if (indexes_1 & (1 << index_1)) != 0:
								value_1 = (value_0 & value_3)
							else:
								value_1 = (value_0 & value_4)
							if value_1 != value_0:
								numbers[index_2] = <int_least16_t>(value_1 | NUMBER_CHANGED)
								result |= RESULT_CHANGED
		index_0 += 9

	if result != 0:
		# if form data isn't empty, checking numbers.
		result |= check_numbers(form_blocks, numbers)

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
		Py_ssize_t form_name_count,
		const Py_ssize_t *form_blocks,
		int_least16_t *numbers,
		Py_ssize_t solved_count,
		Py_ssize_t temp_index
	) except -1:
		cdef Py_ssize_t result
		cdef Py_ssize_t index_0
		cdef Py_ssize_t index_1
		cdef int_fast16_t value_0
		cdef int_fast16_t value_1
		cdef int_fast16_t value_2
		cdef int_least16_t *next_numbers
		cdef object child
		cdef object _places = []
		cdef object _children

		if temp_index >= 0:
			result = check_numbers(form_blocks, numbers)
			PyList_Append(
				_places,
				make_place(place_class, form_name_count, numbers, 4)
			)
			if (result & (RESULT_SOLVED | RESULT_ERROR)) != 0:
				if (result & (RESULT_SOLVED)) != 0:
					solved_count += 1
				self._places = PyList_AsTuple(_places)
				return solved_count

			numbers[temp_index] = <int_least16_t>(
				numbers[temp_index] | NUMBER_TEMP
			)

		while True:
			for index_0 in range(form_name_count):
				value_0 = (numbers[index_0] & (~NUMBER_CHANGED))
				numbers[index_0] = <int_least16_t>(value_0)
				numbers[index_0 + form_name_count] = <int_least16_t>(value_0)

			result = solve_method1(form_name_count, form_blocks, numbers)
			if result != RESULT_UNCHANGED:
				PyList_Append(
					_places,
					make_place(place_class, form_name_count, numbers, 1)
				)
				if (result & (RESULT_SOLVED | RESULT_ERROR)) == 0:
					continue
				if (result & (RESULT_SOLVED)) != 0:
					solved_count += 1
				self._places = PyList_AsTuple(_places)
				return solved_count

			result = solve_method2(form_name_count, form_blocks, numbers)
			if result != RESULT_UNCHANGED:
				PyList_Append(
					_places,
					make_place(place_class, form_name_count, numbers, 2)
				)
				if (result & (RESULT_SOLVED | RESULT_ERROR)) == 0:
					continue
				if (result & (RESULT_SOLVED)) != 0:
					solved_count += 1
				self._places = PyList_AsTuple(_places)
				return solved_count

			result = solve_method3(form_name_count, form_blocks, numbers)
			if result != RESULT_UNCHANGED:
				PyList_Append(
					_places,
					make_place(place_class, form_name_count, numbers, 3)
				)
				if (result & (RESULT_SOLVED | RESULT_ERROR)) == 0:
					continue
				if (result & (RESULT_SOLVED)) != 0:
					solved_count += 1
				self._places = PyList_AsTuple(_places)
				return solved_count
			break

		# Assign a value to a single block whose answer has not been determined
		# because it cannot be resolved any further.
		index_0 = -1
		value_2 = 10
		for index_1 in range(form_name_count):
			value_0 = numbers[index_1]
			value_1 = __builtin_popcount(value_0 & NUMBER_MASK)
			if value_1 == 2:
				index_0 = index_1
				break
			elif value_1 > 2:
				if value_1 < value_2:
					index_0 = index_1
					value_2 = value_1

		if index_0 >= 0:
			_children = []
			next_numbers = <int_least16_t *>(
				malloc(form_name_count * sizeof(numbers[0]) * 2)
			)
			if next_numbers is NULL:
				raise MemoryError()
			try:
				for index_1 in range(9):
					if (value_0 & (1 << index_1)) == 0:
						continue

					if solved_count >= MAX_SOLVED:
						break
					child = Answer()

					# copy from numbers to next_numbers
					for index_2 in range(index_0):
						next_numbers[index_2] = <int_least16_t>(numbers[index_2] & (~NUMBER_CHANGED))
					next_numbers[index_0] = <int_least16_t>((1 << index_1) | NUMBER_CHANGED)
					for index_2 in range(index_0 + 1, form_name_count):
						next_numbers[index_2] = <int_least16_t>(numbers[index_2] & (~NUMBER_CHANGED))
					result = (<Answer>(child)).solve(
						place_class,
						form_name_count,
						form_blocks,
						next_numbers,
						solved_count,
						index_0
					)
					self._tasks += (<Answer>(child))._tasks
					if result > solved_count:
						PyList_Append(_children, child)
					solved_count = result
			finally:
				free(next_numbers)

			if Py_SIZE(_children) == 1:
				child = <object>(PyList_GET_ITEM(_children, 0))
				PyList_SetSlice(
					_places,
					Py_SIZE(_places),
					Py_SIZE(_places),
					(<Answer>(child))._places
				)
				self._tasks -= Py_SIZE((<Answer>(child))._places)
				self._children = (<Answer>(child))._children
			else:
				self._children = PyList_AsTuple(_children)

		self._tasks += Py_SIZE(_places)
		self._places = PyList_AsTuple(_places)
		return solved_count


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
		cdef int_fast16_t value_1 = (value_0 & (~NUMBER_MASK))

		if value_1 == (NUMBER_ERROR | NUMBER_FIXED):
			result = ' f e'
		elif value_1 == (NUMBER_ERROR | NUMBER_TEMP):
			result = ' t e'
		elif value_1 == (NUMBER_ERROR | NUMBER_CHANGED):
			if __builtin_popcount(value_0 & NUMBER_MASK) > 1:
				result = ' u c e'
			else:
				result = ' c e'
		elif value_1 == (NUMBER_ERROR):
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


def get_answer(form_data, form_blocks):
	cdef object self = Answer()
	cdef object place_class
	cdef Py_ssize_t result
	cdef Py_ssize_t form_name_count
	cdef void *numbers
	cdef void *blocks

	# allocating blocks information
	blocks = malloc((Py_SIZE(<tuple?>(form_blocks)) * 9 + 1) * sizeof(Py_ssize_t))
	if blocks is NULL:
		raise MemoryError()
	try:
		place_class = parse_blocks(
			form_blocks,
			<Py_ssize_t *>(blocks)
		)
		form_name_count = Py_SIZE(place_class._fields) - 1
		numbers = malloc(form_name_count * sizeof(int_least16_t) * 2)
		if numbers is NULL:
			raise MemoryError()
		try:
			result = parse_data(
				form_data,
				place_class._fields,
				<Py_ssize_t *>(blocks),
				<int_least16_t *>(numbers),
			)
			if result == RESULT_CHANGED:
				(<Answer>(self)).solve(
					place_class,
					form_name_count,
					<Py_ssize_t *>(blocks),
					<int_least16_t *>(numbers),
					0,
					-1
				)
			elif result != RESULT_UNCHANGED:
				(<Answer>(self))._places = (
					make_place(
						place_class,
						form_name_count,
						<int_least16_t *>(numbers),
						0
					),
				)
		finally:
			free(numbers)
	finally:
		free(blocks)

	return self

