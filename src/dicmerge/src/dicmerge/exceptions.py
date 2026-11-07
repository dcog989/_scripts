class DicmergeError(Exception):
    exit_code: int = 1


class ConfigError(DicmergeError):
    exit_code = 2


class NoSourcesError(DicmergeError):
    exit_code = 3


class WriteBackError(DicmergeError):
    exit_code = 4


class OutputError(DicmergeError):
    exit_code = 5
