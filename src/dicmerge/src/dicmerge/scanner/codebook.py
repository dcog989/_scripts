import json
import re
import tomllib
from pathlib import Path

from dicmerge.scanner.base import Scanner
from dicmerge.util import read_text_with_fallback

_WORDS_ARRAY = re.compile(r"(?ms)^words[ \t]*=[ \t]*\[[^\]\n]*\]|^words[ \t]*=[ \t]*\[.*?^\]")


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
        block = "words = [\n" + "".join(f"    {json.dumps(word)},\n" for word in words) + "]"
        text = read_text_with_fallback(path)
        if _WORDS_ARRAY.search(text):
            return _WORDS_ARRAY.sub(lambda _match: block, text, count=1)
        separator = "" if text.endswith("\n") else "\n"
        return f"{text}{separator}{block}\n"
