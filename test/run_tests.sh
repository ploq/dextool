#!/bin/bash
set -e

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

function check_status() {
    CHECK_STATUS_RVAL=$?
    MSG=$1
    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
    else
        echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    fi
}

outdir="outdata"
if [[ ! -d "$outdir" ]]; then
    mkdir "$outdir"
fi

for sourcef in testdata/*.hpp; do
    expect=${sourcef}".ref"
    out="$outdir/"$(basename ${sourcef})
    echo -e "${C_YELLOW}=== $sourcef  ===${C_NONE}"
    echo -e "\t${expect}" "\t$PWD/${out}"
    ../build/gen-test-double stub --debug $sourcef $outdir
    diff -u "${expect}" "${out}"
    # raw=$(diff -u "${expect}" "${out}")
    # echo $(echo $raw|wc -l)
    # if [[ $(echo $raw|wc -l) -ne 0 ]]; then
    #     echo -e "Failed\n"$raw
    #     exit 1
    # fi
done

rm -r "$outdir"

exit 0
