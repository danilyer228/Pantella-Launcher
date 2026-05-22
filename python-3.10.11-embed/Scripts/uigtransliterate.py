#!C:\Users\pathos\Downloads\PL-v0.0.6\python-3.10.11-embed\python.exe

import fileinput
import epitran

epi = epitran.Epitran('uig-Arab')
for line in fileinput.input():
    s = epi.transliterate(line.strip())
    print(s)
