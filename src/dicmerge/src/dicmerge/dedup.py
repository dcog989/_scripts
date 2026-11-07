def deduplicate(words: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for word in words:
        key = word.casefold()
        if key not in seen:
            seen.add(key)
            result.append(word)
    return result
