from pathlib import Path

from dicmerge.scanner.base import Scanner


class PlainTextScanner(Scanner):
    @classmethod
    def matches(cls, path: Path) -> bool:
        return True

    @staticmethod
    def format_output(words: list[str]) -> str:
        return "\n".join(words) + "\n"
