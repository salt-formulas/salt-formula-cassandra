#!/usr/bin/env python
#
# Expects YAML on standard input.
# Prints value of listen_address key if key is in input data
# and nothing in other case, returns with 0.
# Returns with 1 in case of error.
#
from __future__ import print_function
import sys
import yaml
try:
    data = yaml.load(sys.stdin)
    listen_address = data.get("listen_address", "")
    if listen_address:
        print(listen_address)
    else:
        print('listen_address key is not found in the input', file=sys.stderr)
    sys.exit(0)
except Exception as e:
    print('Failed to get listen_address key.'
          ' YAML input is expected', file=sys.stderr)
    sys.exit(1)
