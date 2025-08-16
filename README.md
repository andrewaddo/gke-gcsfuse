# gke-gcsfuse

This repository contains files to test and reproduce issues with GCS FUSE CSI driver on GKE Autopilot.

## 1. Test Autopilot 1.32 and GCS Fuse 1.14 auto-injection

This section describes how to test the auto-injection of GCS FUSE CSI driver v1.14.x on a GKE Autopilot cluster v1.32.
It also shows how to reproduce a bug related to `mv` command on a symbolic link.

### Steps:

1.  **Create a pod with a GCS FUSE volume:**
    ```bash
    kubectl apply -f autopilot-1.32-gcsfuse-1.14-pod.yaml
    ```
    The pod `gcsfuse-autopilot-pod` will be created with the GCS FUSE CSI driver v1.14.x automatically injected by GKE Autopilot.

2.  **Exec into the pod and reproduce the bug:**
    ```bash
    kubectl exec -it gcsfuse-autopilot-pod -- /bin/sh
    ```
    Inside the pod, run the following commands:
    ```bash
    # cd /content
    # echo "hello" > target1.txt
    # ln -s target1.txt link1.txt
    # mv link1.txt renamed1.txt
    mv: can't rename 'link1.txt': Input/output error
    ```
    The `mv` command fails with an "Input/output error".

## 2. Test overriding with GCS Fuse 1.8.9

This section describes how to override the auto-injected GCS FUSE CSI driver with a specific version (v1.8.9) to validate that the bug is resolved.

### Steps:

1.  **Create a pod with a specific GCS FUSE version:**
    ```bash
    kubectl apply -f override-gcsfuse-1.8.9-pod.yaml
    ```
    The pod `gcsfuse-override-pod` will be created with the GCS FUSE CSI driver v1.8.9.

2.  **Exec into the pod and validate the fix:**
    ```bash
    kubectl exec -it gcsfuse-override-pod -- /bin/bash
    ```
    Inside the pod, run the following commands:
    ```bash
    # cd /content
    # echo "hello" > target2.txt
    # ln -s target2.txt link2.txt
    # mv link2.txt renamed2.txt
    # ls
    link1.txt  renamed2.txt  target1.txt  target2.txt
    # cat renamed2.txt
    hello
    ```
    The `mv` command works as expected.

## 3. Test a more generic approach to use kyverno-cp-pod to patch the gcsfuse drive when the pod is created

This section describes an approach to use a Kyverno ClusterPolicy to patch the GCS FUSE driver when a pod is created.
This approach aims to avoid the auto-injection of the default GCS FUSE driver by GKE.

The policy is defined in `kyverno-cp-pod.yaml`.

**Note:** This approach was not fully tested.

## 4. Test another approach to use kyverno-cp-job to patch the gcsfuse drive the job is created

This section describes another approach to use a Kyverno ClusterPolicy to patch the GCS FUSE driver when a job is created.
This approach is similar to the previous one, but it targets jobs instead of pods.

The policy is defined in `kyverno-cp-job.yaml`.

**Note:** This approach was not fully tested.
The following error was observed, which indicates a clash with the auto-injection mechanism:
```
Error: failed to reserve container name "gcsfuse-prewarm_samplejob-dtg9v_default_dde4ed2d-6413-4ad9-b13b-3fcaf7f6c711_0": name "gcsfuse-prewarm_samplejob-dtg9v_default_dde4ed2d-6413-4ad9-b13b-3fcaf7f6c711_0" is reserved for "a9b5df6e4529814096e15bb875a1acbcfe737c628ebd2c1ad1e00a42eef791d0"
```

## Load test

This section contains instructions to run a load test.
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
```
