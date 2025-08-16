# gke-gcsfuse

This repository contains files to test, reproduce, and solve the issue with GCS FUSE CSI driver (1.14) on GKE Autopilot (1.32).

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
    Inside the pod, run the following commands and observe the outputs:
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
    Inside the pod, run the following commands and observe the outputs:
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

This section contains instructions to run a load test.
```bash
# Test with a single job
kubectl apply -f kyverno-cp-pod.yaml
sed -e 's/value: "1"/value: "0"/g' -e 's/name: samplejob-$(JOB_INDEX)/name: samplejob-0/g' samplejob.yaml | kubectl apply -f -

# Validate that the file is renamed correctly
gsutil ls gs://addo-gke-gcsfuse | grep target | wc -l
gsutil ls gs://addo-gke-gcsfuse | grep renamed | wc -l
```

## 4. Test another approach to use kyverno-cp-job to patch the gcsfuse drive the job is created

This section describes another approach to use a Kyverno ClusterPolicy to patch the GCS FUSE driver when a job is created.
This approach is similar to the previous one, but it targets jobs instead of pods.

The policy is defined in `kyverno-cp-job.yaml`.

```bash
# Test with a single job
kubectl apply -f kyverno-cp-job.yaml
sed -e 's/value: "1"/value: "0"/g' -e 's/name: samplejob-$(JOB_INDEX)/name: samplejob-0/g' samplejob.yaml | kubectl apply -f -

# Validate that the file is renamed correctly
gsutil ls gs://addo-gke-gcsfuse | grep target | wc -l
gsutil ls gs://addo-gke-gcsfuse | grep renamed | wc -l
```

## Load test

This section contains instructions to run a load test.

### Pod level policy

```bash
kubectl apply -f kyverno-cp-pod.yaml
./loadtest.sh 100
# Validate that the file is renamed correctly
gsutil ls gs://addo-gke-gcsfuse | grep target | wc -l
gsutil ls gs://addo-gke-gcsfuse | grep renamed | wc -l
```

### Job level policy

```bash
kubectl apply -f kyverno-cp-job.yaml
./loadtest.sh 100
# Validate that the file is renamed correctly
gsutil ls gs://addo-gke-gcsfuse | grep target | wc -l
gsutil ls gs://addo-gke-gcsfuse | grep renamed | wc -l
```

## References

```bash
# Clean up before the test
gsutil rm gs://addo-gke-gcsfuse/*
kubectl delete ClusterPolicy --all
kubectl delete jobs --all
kubectl delete pods --all
```

## Notes

1. Autopilot cluster warden requires the `ephemeral-storage` to be defined. This is not required in Standard cluster. For the policy at the job level, the parameters are required

```bash
resources:
  requests:
    ephemeral-storage: "1Gi"
  limits:
    ephemeral-storage: "1Gi"
```

For policy at the pod level, the `ephemeral-storage` is automatically generated so there is no need to include these parameters explicitly.

2. For the policy at the pod level, the `initContainers` object presents at the pod, so the mechanism to patch through merging with `patchStrategicMerge` works. For the policy at the job leve, the `initContainers` would not be present for patching, so `patchesJson6902` is used instead.

## History log

```bash
gcloud container clusters get-credentials ap-cluster-1 --location asia-southeast1
```

## Issues log

1. "MountVolume.MountDevice failed for volume "gcsfuse-debugger-pv" : kubernetes.io/csi: attacher.MountDevice failed to create newCsiDriverClient: driver name gcsfuse.csi.storage.gke.io not found in the list of registered CSI drivers"

The intermittent error is a race condition. In Autopilot, when a new node is provisioned for your pod, the GCS FUSE CSI driver, a DaemonSet, also needs to start on that node. If your pod starts before the driver registers with the kubelet, the mount fails. The issue resolves on its own because the driver eventually starts, and the pod creation is retried successfully.
