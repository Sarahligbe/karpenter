#!/bin/bash

# Enable exit on error and undefined variables
set -eu

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Variables
K8S_VERSION="1.31"
CALICO_VERSION="v3.28.2"
POD_NETWORK_CIDR="192.168.0.0/16"
REGION="${region}"
HOME="/home/ubuntu"
# Set variables for IRSA configuration
DISCOVERY_BUCKET="${discovery_bucket_name}" 
IRSA_DIR="irsa_keys"
PKCS_KEY="$IRSA_DIR/oidc-issuer.pub"
PRIV_KEY="$IRSA_DIR/oidc-issuer.key"
ISSUER_HOSTPATH="s3-${region}.amazonaws.com/${discovery_bucket_name}"
# Determine if this is a controlplane or worker node
NODE_TYPE="${node_type}"
CLUSTER_NAME="${cluster_name}"
AWS_LB_ROLE_ARN="${aws_lb_role_arn}"
HOSTNAME="$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)"
INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
GRAFANA_PASSWD="${grafana_passwd}"
CERT_ARN="${cert_arn}"
DOMAIN="${domain}"
DNS_ROLE_ARN="${dns_role_arn}"
KARPENTER_VERSION="0.37.0"
KARPENTER_CONTROLLER_ROLE_ARN="${karpenter_controller_role_arn}"
KARPENTER_INSTANCE_ROLE_ARN="${karpenter_instance_role_arn}"
AMI_ID="${ami_id}"
IP_ADDR="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"

log "Starting Kubernetes $NODE_TYPE node setup"

log "Installing AWS CLI"
sudo apt update
sudo apt-get install -y awscli

log "Fetching the setup_common script from Parameter Store"
aws ssm get-parameter --name "/scripts/setup_common" --with-decryption --query "Parameter.Value" --output text --region $REGION > /tmp/setup_common.sh

source /tmp/setup_common.sh

setup_worker() {
    log "Retrieving join command from Parameter Store"
    max_attempts=5
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        JOIN_COMMAND=$(aws ssm get-parameter \
            --name "/k8s/join-command" \
            --with-decryption \
            --query "Parameter.Value" \
            --output text \
            --region $REGION)

        if [ -n "$JOIN_COMMAND" ] && [ "$JOIN_COMMAND" != "placeholder" ]; then
            log "Join command retrieved successfully"
            break
        fi

        log "Attempt $attempt: Failed to retrieve valid join command, retrying in 30 seconds..."
        sleep 30
        attempt=$((attempt+1))
    done

    if [ $attempt -gt $max_attempts ]; then
        log "Error: Failed to retrieve valid join command after $max_attempts attempts"
        return 1
    fi

    log "Joining the Kubernetes cluster"
    if ! sudo $JOIN_COMMAND; then
        log "Error: Failed to join the Kubernetes cluster"
        return 1
    fi

    log "Successfully joined the Kubernetes cluster"

    log "Retrieving kubeconfig from SSM Parameter Store"
    KUBECONFIG_CONTENT=$(aws ssm get-parameter \
        --name "/k8s/kubeconfig" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region $REGION)

    if [ -n "$KUBECONFIG_CONTENT" ]; then
        log "Setting up kubeconfig for worker node"
        mkdir -p $HOME/.kube
        echo "$KUBECONFIG_CONTENT" | base64 -d > $HOME/.kube/config
        sudo chown ubuntu:ubuntu $HOME/.kube/config
        chmod 700 $HOME/.kube
        chmod 600 $HOME/.kube/config
        log "Kubeconfig set up successfully"
    else
        log "Error: Failed to retrieve kubeconfig from SSM Parameter Store"
        return 1
    fi
 
    log "Installing cert manager"
    kubectl create -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml

    log "Waiting for cert-manager pods to be ready"
    kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s

    log "Verifying cert-manager webhook"
    # Retry mechanism for webhook verification
    max_attempts=5
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if kubectl get validatingwebhookconfigurations cert-manager-webhook -o jsonpath='{.webhooks[0].clientConfig.service.name}' | grep -q "cert-manager-webhook"; then
            log "Cert-manager webhook is verified and ready"
            break
        fi
        log "Attempt $attempt: Cert-manager webhook not ready yet, waiting 30 seconds..."
        sleep 30
        attempt=$((attempt+1))
    done

    if [ $attempt -gt $max_attempts ]; then
        log "Error: Cert-manager webhook not ready after $max_attempts attempts"
        return 1
    fi

    log "cert-manager is ready. Installing aws-pod-identity-webhook"
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/auth.yaml
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/service.yaml
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/mutatingwebhook.yaml
    curl -o deployment.yaml https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/deployment-base.yaml
    sed -i 's|IMAGE|amazon/amazon-eks-pod-identity-webhook:v0.5.7|' deployment.yaml
    kubectl apply -f deployment.yaml

    log "Waiting for pod identity pods to be ready"
    kubectl wait --for=condition=Available deployment/pod-identity-webhook --timeout=300s
    log "aws-pod-identity-webhook installation completed"

    log "Setting up Karpenter"
    helm install karpenter oci://public.ecr.aws/karpenter/karpenter --version $KARPENTER_VERSION --namespace kube-system \
         --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$KARPENTER_CONTROLLER_ROLE_ARN \
         --set settings.clusterName=$CLUSTER_NAME \
         --set settings.clusterEndpoint="https://$IP_ADDR:6443" \
         --wait

    cat <<EOF > karpenter-node-config.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t"]
        - key: karpenter.k8s.aws/instance-generation
          operator: In
          values: ["2", "3"]
        - key: "karpenter.k8s.aws/instance-size"
          operator: NotIn
          values: [nano, micro, small, xlarge, 2xlarge]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
  limits:
    cpu: 50
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: Ubuntu
  role: "KarpenterWorkerRole" 
  tags:
    Name: "karpenter-provisioned"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "$CLUSTER_NAME" 
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "$CLUSTER_NAME"
  amiSelectorTerms:
    - id: "$AMI_ID"
  userData: |
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    K8S_VERSION="1.31"
    REGION="\$(curl -s http://169.254.169.254/latest/meta-data/placement/region)"
    HOSTNAME="\$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)"
    INSTANCE_ID="\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

    log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    }

    log "Fetching the setup_common script from Parameter Store"
    log "Installing AWS CLI"
    sudo apt update
    sudo apt-get install -y awscli

    aws ssm get-parameter --name "/scripts/setup_common" --with-decryption --query "Parameter.Value" --output text --region $REGION > /tmp/setup_common.sh
    source /tmp/setup_common.sh
    setup_common

    log "Retrieving join command from Parameter Store"
    max_attempts=5
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        JOIN_COMMAND=$(aws ssm get-parameter \
            --name "/k8s/join-command" \
            --with-decryption \
            --query "Parameter.Value" \
            --output text \
            --region $REGION)

        if [ -n "$JOIN_COMMAND" ] && [ "$JOIN_COMMAND" != "placeholder" ]; then
            log "Join command retrieved successfully"
            break
        fi

        log "Attempt $attempt: Failed to retrieve valid join command, retrying in 30 seconds..."
        sleep 30
        attempt=$((attempt+1))
    done

    if [ $attempt -gt $max_attempts ]; then
        log "Error: Failed to retrieve valid join command after $max_attempts attempts"
        return 1
    fi

    log "Joining the Kubernetes cluster"
    if ! sudo $JOIN_COMMAND; then
        log "Error: Failed to join the Kubernetes cluster"
        return 1
    fi

    log "Successfully joined the Kubernetes cluster"
    --BOUNDARY
EOF

    kubectl apply -f karpenter-node-config.yaml
    log "Karpenter setup successfully"

    log "Update providerID"
    kubectl patch node $HOSTNAME -p "{\"spec\":{\"providerID\":\"aws://$REGION/$INSTANCE_ID\"}}"

    log "Waiting for pod identity pods to be ready"
    kubectl wait --for=condition=Ready pods --all --timeout=300s

    log "Setting up aws loadbalancer controller"
    cat <<EOF > aws_lb_service_account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: $AWS_LB_ROLE_ARN
EOF
    kubectl apply -f aws_lb_service_account.yaml
    helm repo add eks https://aws.github.io/eks-charts
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=$CLUSTER_NAME --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller
    
    kubectl wait --for=condition=Available deployment/aws-load-balancer-controller -n kube-system --timeout=300s
    log "AWS LBC installed successfully"

    log "Installing external dns"
    cat <<EOF > external_dns_values.yaml
provider:
  name: aws
env:
  - name: AWS_DEFAULT_REGION
    value: "$REGION"
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: $DNS_ROLE_ARN
EOF
    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
    helm install external-dns external-dns/external-dns --values external_dns_values.yaml

    log "installing argocd"
    cat <<EOF > argo_cd_values.yaml
global:
  domain: "argocd.$DOMAIN"
server:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: instance
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/group.name: bird-alb
      alb.ingress.kubernetes.io/certificate-arn: "$CERT_ARN"
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      external-dns.alpha.kubernetes.io/hostname: "argocd.$DOMAIN"
    hostname: "argocd.$DOMAIN"
    paths:
      - /
    pathType: Prefix
  extraArgs:
    - --insecure
  service:
    type: NodePort
applicationSet:
  enabled: true
EOF
    helm repo add argo https://argoproj.github.io/argo-helm
    helm install argocd argo/argo-cd --namespace argocd --create-namespace --values argo_cd_values.yaml

    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

    log "Argocd installed successfully"

    log "Deploy bird app"
    cat <<EOF > bird_appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: birdapp
  namespace: argocd
spec: 
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators: 
  - git: 
      repoURL: https://github.com/Sarahligbe/devops-challenge.git
      revision: HEAD
      directories: 
      - path: helm
  template: 
    metadata: 
      name: '{{.path.basename}}'
    spec: 
      project: default
      sources: 
        - repoURL: https://github.com/Sarahligbe/devops-challenge.git
          targetRevision: HEAD
          path: '{{.path.path}}'
          helm:
            parameters:
            - name: global.ingress.annotations.\\alb\\.ingress\\.kubernetes\\.io/certificate-arn
              value: "$CERT_ARN"
            - name: bird.ingress.annotations.\\external-dns\\.alpha\\.kubernetes\\.io/hostname
              value: 'bird.$DOMAIN'
            - name: birdimage.ingress.annotations.\\external-dns\\.alpha\\.kubernetes\\.io/hostname
              value: "birdimage.$DOMAIN"
            - name: "bird.ingress.host"
              value: "bird.$DOMAIN"
            - name: "birdimage.ingress.host"
              value: "birdimage.$DOMAIN"
      destination: 
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
      syncPolicy: 
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF
    log "Applying birdapp argocd manifest"
    kubectl apply -f bird_appset.yaml

    log "Installing Prometheus and grafana"
    cat <<EOF > prometheus_values.yaml
prometheus:
  service:
    type: NodePort
grafana:
  adminPassword: "$GRAFANA_PASSWD"
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: instance
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/group.name: bird-alb
      alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/healthcheck-path: /login
      external-dns.alpha.kubernetes.io/hostname: "grafana.$DOMAIN"
    hosts:
      - "grafana.$DOMAIN"
    path: /
    pathType: Prefix
  service:
    type: NodePort
EOF

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --values prometheus_values.yaml

    kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s
    log "monitoring stack installed successfully"
    
}

# Main execution
setup_common


if [ "$NODE_TYPE" == "worker" ]; then
    /sbin/runuser -l ubuntu << EOF
export REGION="$REGION"
export K8S_VERSION="$K8S_VERSION"
export CLUSTER_NAME="$CLUSTER_NAME"
export AWS_LB_ROLE_ARN="$AWS_LB_ROLE_ARN"
export INSTANCE_ID="$INSTANCE_ID"
export GRAFANA_PASSWD="$GRAFANA_PASSWD"
export CERT_ARN="$CERT_ARN"
export DOMAIN="$DOMAIN"
export DNS_ROLE_ARN="$DNS_ROLE_ARN"
export KARPENTER_VERSION="$KARPENTER_VERSION"
export KARPENTER_CONTROLLER_ROLE_ARN="$KARPENTER_CONTROLLER_ROLE_ARN"
export KARPENTER_INSTANCE_ROLE_ARN="$KARPENTER_INSTANCE_ROLE_ARN"
export AMI_ID="$AMI_ID"
export CLUSTER_NAME="$CLUSTER_NAME"
export IP_ADDR="$IP_ADDR"
$(declare -f log setup_worker)
setup_worker
EOF
else
    log "Error: Invalid node type specified. Must be 'controlplane' or 'worker'"
    exit 1
fi
