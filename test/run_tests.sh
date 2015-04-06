#!/bin/bash
set -e

for sourcef in testdata/*.hpp; do
    expect=${sourcef}".ref"
    out=$(basename ${sourcef})".out"
    echo -e "$sourcef" "\t${expect}" "\t${out}"
    ../build/gen-test-double stub $sourcef ${out}
    diff -u "${expect}" "${out}"
    # raw=$(diff -u "${expect}" "${out}")
    # echo $(echo $raw|wc -l)
    # if [[ $(echo $raw|wc -l) -ne 0 ]]; then
    #     echo -e "Failed\n"$raw
    #     exit 1
    # fi
done

rm *.out

exit 0
