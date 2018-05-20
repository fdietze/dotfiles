#!/usr/bin/env python3

import sys
from isodate import parse_duration

print(parse_duration(sys.stdin.read()))
