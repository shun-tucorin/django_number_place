# encoding: utf-8
from typing import Dict, List, Tuple

class Answer:
	@property
	def state(self) -> str: ...

	@property
	def places(self) -> List[Dict]: ...

	@property
	def children(self) -> List[Answer]: ...


def get_answer(form_data: object, form_blocks: Tuple[Tuple[str]]) -> Answer: ...
