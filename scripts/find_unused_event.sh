#!/bin/bash

dir="contracts"

for i in $(find $dir -name '*.sol');
do
    echo $i    
    grep event $i | grep -v "\*" | grep -v "\//"
    echo $event
    grep emit $i | grep -v "\*" | grep -v "\//"
    echo $emit
done;
