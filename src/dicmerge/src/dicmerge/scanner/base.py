from abc import ABC, abstractmethod
from pathlib import Path

from dicmerge.util import read_text_with_fallback


class Scanner(ABC):
    skip_header: int = 0

    @classmethod
    @abstractmethod
    def matches(cls, path: Path) -> bool: ...

    def read(self, path: Path) -> list[str]:
        words: list[str] = []
        for lineno, line in enumerate(read_text_with_fallback(path).splitlines(), 1):
            if lineno <= self.skip_header:
                continue
            word = line.strip()
            if word:
                words.append(word)
        return words

    @staticmethod
    @abstractmethod
    def format_output(words: list[str]) -> str: ...
