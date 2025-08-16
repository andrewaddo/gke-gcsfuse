# gke-gcsfuse

## Findings

```logs
1. TODO
```

Use Autopilot cluster
```bash
$ gcloud container clusters get-credentials ap-cluster-1 --location asia-southeast1

gcloud storage buckets add-iam-policy-binding gs://addo-gke-gcsfuse \
  --member "principal://iam.googleapis.com/projects/827859227929/locations/global/workloadIdentityPools/addo-argolis-demo.svc.id.goog/subject/ns/default/sa/default" \
  --role "roles/storage.objectUser"

## autopilot-pod
Image:           asia-southeast1-artifactregistry.gcr.io/gke-release/gke-release/gcs-fuse-csi-driver-sidecar-mounter:v1.14.3-gke.0@sha256:b4e420985f54714e5952ece5da15f19e8b11f47e18cc6fe0a03995bc6a0ae7d3

## override-gcsfuse-pod
Image:           gcr.io/gke-release/gcs-fuse-csi-driver-sidecar-mounter:v1.8.9-gke.2
```

Debug

```bash
gcloud container clusters describe ap-cluster-1 \
    --location=asia-southeast1 \
    --project=addo-argolis-demo \
    --format="value(addonsConfig.gcsFuseCsiDriverConfig.enabled)"

gcloud container clusters update ap-cluster-1 \
    --update-addons GcsFuseCsiDriver=ENABLED \
    --location=asia-southeast1

kubectl exec -it gcsfuse-autopilot-pod -- /bin/sh

# ducdo@control-tower-25:~/workspaces/gke-gcsfuse
# $ kubectl exec -it gcsfuse-autopilot-pod -- /bin/sh
# Defaulted container "prewarm-inodes" out of: prewarm-inodes, gke-gcsfuse-sidecar (init)
# / # ls
# bin      content  dev      etc      home     lib      lib64    proc     root     sys      tmp      usr      var
# / # cd content/
# /content # echo "hello" > target1.txt
# /content # ln -s target1.txt link1.txt
# /content # mv link1.txt renamed1.txt
# mv: can't rename 'link1.txt': Input/output error
# /content # exit

kubectl exec -it gcsfuse-override-pod -- /bin/bash

# ducdo@control-tower-25:~/workspaces/gke-gcsfuse
# $ kubectl exec -it gcsfuse-override-pod -- /bin/bash
# Defaulted container "shell" out of: shell, gke-gcsfuse-sidecar (init), prewarm-inodes (init)
# root@gcsfuse-override-pod:/# ls 
# bin  boot  content  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
# root@gcsfuse-override-pod:/# cd content/
# root@gcsfuse-override-pod:/content# echo "hello" > target2.txt
# root@gcsfuse-override-pod:/content# ln -s target2.txt link2.txt
# root@gcsfuse-override-pod:/content# mv link2.txt renamed2.txt
# root@gcsfuse-override-pod:/content# ls
# link1.txt  renamed2.txt  target1.txt  target2.txt
# root@gcsfuse-override-pod:/content# cat target2.txt 
# hello
# root@gcsfuse-override-pod:/content# cat renamed2.txt 
# hello
# root@gcsfuse-override-pod:/content# exit
# exit
```

Kyverno

```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.12.5/install.yaml
  
kubectl apply -f Kyverno_gcssidecard_policy.yaml

  Error: failed to reserve container name "gcsfuse-prewarm_samplejob-dtg9v_default_dde4ed2d-6413-4ad9-b13b-3fcaf7f6c711_0": name "gcsfuse-prewarm_samplejob-dtg9v_default_dde4ed2d-6413-4ad9-b13b-3fcaf7f6c711_0" is reserved for "a9b5df6e4529814096e15bb875a1acbcfe737c628ebd2c1ad1e00a42eef791d0"

  --> look like it clashes with the auto-injection done by Autopilot
```

Load test

```bash
sed -e 's/value: "1"/value: "0"/g' -e 's/name: samplejob-$(JOB_INDEX)/name: samplejob-0/g' samplejob.yaml | kubectl apply -f -

gsutil rm gs://addo-gke-gcsfuse/*
kubectl delete ClusterPolicy --all
kubectl delete jobs --all

kubectl apply -f kyverno-cp-job.yaml
./loadtest.sh 1
kubectl apply -f kyverno-cp-pod.yaml
./loadtest.sh 1

./loadtest.sh 1000

# output
ducdo@control-tower-25:~/workspaces/gke-gcsfuse
$ gsutil ls gs://addo-gke-gcsfuse | grep target | wc -l
100
ducdo@control-tower-25:~/workspaces/gke-gcsfuse
$ gsutil ls gs://addo-gke-gcsfuse | grep renamed | wc -l
100

```