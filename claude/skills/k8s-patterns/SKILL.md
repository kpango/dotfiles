---
name: k8s-patterns
description: Kubernetes manifest patterns, Operators, Helm, kustomize, kubectl debugging, and production readiness for Go-based services.
trigger: /k8s-patterns
---

# Kubernetes Patterns

## Manifest Best Practices

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
      containers:
      - name: myapp
        image: ghcr.io/org/myapp:v1.0.0
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 256Mi
        readinessProbe:
          httpGet:
            path: /healthz/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /healthz/live
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: [ALL]
```

## PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: myapp
```

## HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Kustomize

```
base/
  kustomization.yaml
  deployment.yaml
  service.yaml
overlays/
  dev/
    kustomization.yaml    # replicas=1, dev image tag
  prod/
    kustomization.yaml    # replicas=3, HPA, PDB
```

```yaml
# overlays/prod/kustomization.yaml
resources:
- ../../base
patches:
- path: replicas-patch.yaml
images:
- name: myapp
  newTag: v1.2.3
```

## Helm

```bash
helm upgrade --install myapp ./chart -f values.prod.yaml -n myapp --create-namespace
helm diff upgrade myapp ./chart -f values.prod.yaml
helm lint ./chart --strict
```

## kubectl Debugging

```bash
kubectl describe pod <pod> -n <ns>
kubectl get events -n <ns> --sort-by='.lastTimestamp' | tail -20
kubectl logs <pod> -n <ns> --previous --tail=100
kubectl exec -it <pod> -n <ns> -- sh
kubectl port-forward svc/<svc> 8080:80 -n <ns>
kubectl top pods -n <ns>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# Force-delete stuck pod (last resort)
kubectl delete pod <pod> -n <ns> --grace-period=0 --force
```

## Go Operator Pattern (controller-runtime)

```go
func (r *MyAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    var obj myv1.MyApp
    if err := r.Get(ctx, req.NamespacedName, &obj); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    if !obj.DeletionTimestamp.IsZero() {
        return r.reconcileDelete(ctx, &obj)
    }

    defer func() {
        r.Status().Update(ctx, &obj)
    }()

    return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}
```

## Production Readiness Checklist

- [ ] Resource requests and limits set
- [ ] Readiness and liveness probes configured
- [ ] `runAsNonRoot: true`, `readOnlyRootFilesystem: true`
- [ ] PodDisruptionBudget for critical services
- [ ] NetworkPolicy to restrict ingress/egress
- [ ] HPA for variable load
- [ ] Image pinned by digest in production
- [ ] Secrets via external-secrets or sealed-secrets (not plain Secret in git)
- [ ] ServiceMonitor for Prometheus scraping

## Anti-Patterns

- `latest` image tag in production
- Missing `resources:` (unbounded consumption)
- Plain `Secret` committed to git
- `hostNetwork: true` without explicit need
- Missing readiness probe (traffic to unready pods)
- `kubectl edit` in production (breaks GitOps)
