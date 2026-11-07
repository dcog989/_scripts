from pathlib import Path

from dicmerge.scanner.base import Scanner

_LO_HEADER = "OOoUserDict1\nlang: en-US\ntype: positive\nreplacement: \n"


class LibreOfficeScanner(Scanner):
    skip_header = len(_LO_HEADER.splitlines())

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

    @staticmethod
    def format_output(words: list[str]) -> str:
        return _LO_HEADER + "\n".join(words) + "\n"
