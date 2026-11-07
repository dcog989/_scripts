from pathlib import Path

from dicmerge.scanner.base import Scanner
from dicmerge.util import read_text_with_fallback

_LO_HEADER = "OOoUserDict1\nlang: en-US\ntype: positive\nreplacement: \n"
_HEADER_LINES = len(_LO_HEADER.splitlines())


class LibreOfficeScanner(Scanner):
    skip_header = _HEADER_LINES

    @classmethod
    def matches(cls, path: Path) -> bool:
        if not path.name.endswith(".dic"):
            return False
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                first = f.readline().strip()
        except OSError:
            return False
        return first == "OOoUserDict1"

    def format_output(self, path: Path, words: list[str]) -> str:
        return _read_header(path) + "\n".join(words) + "\n"


def _read_header(path: Path) -> str:
    try:
        lines = read_text_with_fallback(path).splitlines()
    except OSError, ValueError:
        return _LO_HEADER
    if len(lines) >= _HEADER_LINES and lines[0].strip() == "OOoUserDict1":
        return "\n".join(lines[:_HEADER_LINES]) + "\n"
    return _LO_HEADER
