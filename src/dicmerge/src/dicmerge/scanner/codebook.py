import json
import tomllib
from pathlib import Path

from dicmerge.scanner.base import Scanner
from dicmerge.util import read_text_with_fallback


class CodebookScanner(Scanner):
    @classmethod
    def matches(cls, path: Path) -> bool:
        return path.name == "codebook.toml"

    def read(self, path: Path) -> list[str]:
        data = tomllib.loads(read_text_with_fallback(path))
        words = data.get("words", [])
        if not isinstance(words, list) or not all(isinstance(word, str) for word in words):
            raise ValueError(f"{path}: 'words' must be a list of strings")
        return words

    def format_output(self, path: Path, words: list[str]) -> str:
        dictionaries = _read_dictionaries(path)
        lines = ["dictionaries = ["]
        lines += [f"    {json.dumps(entry)}," for entry in dictionaries]
        lines += ["]", "words = ["]
        lines += [f"    {json.dumps(word)}," for word in words]
        lines.append("]")
        return "\n".join(lines) + "\n"


def _read_dictionaries(path: Path) -> list[str]:
    data = tomllib.loads(read_text_with_fallback(path))
    dictionaries = data.get("dictionaries", [])
    return [entry for entry in dictionaries if isinstance(entry, str)]
