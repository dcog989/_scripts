from pathlib import Path

from dicmerge.scanner.base import Scanner


class PlainTextScanner(Scanner):
    @classmethod
    def matches(cls, path: Path) -> bool:
        return True

    def format_output(self, path: Path, words: list[str]) -> str:
        return "\n".join(words) + "\n"
