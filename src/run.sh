#!/bin/bash

# ./run.sh con -v o --verbose to show simulation output, otherwise it will be hidden
VERBOSE=false
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE=true
fi

make

if [ "$VERBOSE" = true ]; then
    ./testbench.exe --stop-time=100000ns --wave=tmp.ghw
else
    ./testbench.exe --stop-time=100000ns --wave=tmp.ghw > /dev/null
fi

gtkwave tmp.ghw --save=signals.gtkw
rm tmp.ghw testbench.exe