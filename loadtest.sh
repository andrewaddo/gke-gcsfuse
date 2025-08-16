#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_jobs>"
  exit 1
fi

N=$1

for i in $(seq 1 $N)
do
  echo "Deploying job $i"
  sed -e "s/value: \"1\"/value: \"$i\"/g" -e "s/name: samplejob-\\\$(JOB_INDEX)/name: samplejob-$i/g" samplejob.yaml | kubectl apply -f -
done
