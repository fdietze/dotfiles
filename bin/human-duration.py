#!/usr/bin/env python3

import sys
from isodate import parse_duration

duration = parse_duration(sys.stdin.read())

hours, remainder = divmod(duration.total_seconds(), 3600)
minutes, seconds = divmod(remainder, 60)
if hours > 0:
    print('%dh %dm' % (hours, minutes))
elif minutes > 0: 
    print('%dm' % (minutes))
else: 
    print('%ds' % (seconds))
