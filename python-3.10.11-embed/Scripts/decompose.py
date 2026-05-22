#!C:\Users\pathos\Downloads\PL-v0.0.6\python-3.10.11-embed\python.exe

import unicodedata
import sys


def main(fn: str) -> None:
    with open(fn, encoding='utf-8') as f:
        print(unicodedata.normalize('NFD', f.read()))


if __name__ == '__main__':
    main(sys.argv[1])
