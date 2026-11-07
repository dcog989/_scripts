from pathlib import Path

from dicmerge.scanner.base import Scanner


class PlainTextScanner(Scanner):
    def format_output(self, path: Path, words: list[str]) -> str:
        return "\n".join(words) + "\n"
