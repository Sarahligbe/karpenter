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
HOSTNAME="$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)"
INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
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
setup_common_script=$(aws ssm get-parameter --name "/scripts/setup_common" --with-decryption --query "Parameter.Value" --output text --region $REGION)

echo "$setup_common_script" > /tmp/setup_common.sh
source /tmp/setup_common.sh

setup_controlplane() {
    log "Creating a directory for the IRSA bucket"
    mkdir -p $IRSA_DIR

    log "Retrieving IRSA keys from SSM Parameter Store"
    aws ssm get-parameter --name "/k8s/irsa/private-key" --with-decryption --query "Parameter.Value" --region $REGION --output text > $PRIV_KEY
    aws ssm get-parameter --name "/k8s/irsa/public-key" --with-decryption --query "Parameter.Value" --region $REGION --output text > $PKCS_KEY

    log "Creating kubeconfig file"
    cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
apiServer:
  extraArgs:
    - name: "service-account-key-file"
      value: "/etc/kubernetes/irsa/oidc-issuer.pub"
    - name: "service-account-signing-key-file"
      value: "/etc/kubernetes/irsa/oidc-issuer.key"
    - name: "api-audiences" 
      value: "sts.amazonaws.com"
    - name: "service-account-issuer"
      value:  "https://$ISSUER_HOSTPATH"
  extraVolumes:
    - name: irsa-keys
      hostPath: "/home/ubuntu/$IRSA_DIR"
      mountPath: /etc/kubernetes/irsa
      readOnly: true
      pathType: DirectoryOrCreate
networking:
  podSubnet: 192.168.0.0/16
EOF
    
    log "Initializing Kubernetes controlplane node"
    sudo kubeadm init --config kubeadm-config.yaml --v=5

    log "set up kubeconfig"
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown ubuntu:ubuntu $HOME/.kube/config

    log "Storing kubeconfig in SSM Parameter Store"
    KUBECONFIG_CONTENT=$(cat $HOME/.kube/config | base64 -w 0)
    aws ssm put-parameter \
        --name "/k8s/kubeconfig" \
        --type "SecureString" \
        --value "$KUBECONFIG_CONTENT" \
        --tier "Advanced" \
        --region $REGION \
        --overwrite

    log "Installing Calico network plugin"
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml
    kubectl set env daemonset/calico-node -n kube-system ICALICO_IPV4POOL_IPIP=CrossSubnet

    kubectl taint nodes $HOSTNAME node-role.kubernetes.io/control-plane:NoSchedule-

    log "Generating join command for worker nodes"
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    
    # Update the SSM parameter with the real join command
    if ! aws ssm put-parameter \
        --name "/k8s/join-command" \
        --type "SecureString" \
        --value "$JOIN_COMMAND" \
        --region $REGION \
        --overwrite; then
        log "Error: Failed to update SSM parameter with join command"
        return 1
    fi

    # Verify the parameter was updated correctly
    VERIFIED_COMMAND=$(aws ssm get-parameter \
        --name "/k8s/join-command" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region $REGION)

    if [ "$JOIN_COMMAND" != "$VERIFIED_COMMAND" ]; then
        log "Error: SSM parameter verification failed"
        return 1
    fi

    log "Join command stored in Parameter Store"

    log "Update providerID"
    kubectl patch node $HOSTNAME -p "{\"spec\":{\"providerID\":\"aws://$REGION/$INSTANCE_ID\"}}"
}

# Main execution
setup_common


if [ "$NODE_TYPE" == "controlplane" ]; then
    /sbin/runuser -l ubuntu << EOF
export REGION="$REGION"
export DISCOVERY_BUCKET="$DISCOVERY_BUCKET"
export IRSA_DIR="$IRSA_DIR"
export PKCS_KEY="$PKCS_KEY"
export PRIV_KEY="$PRIV_KEY"
export ISSUER_HOSTPATH="$ISSUER_HOSTPATH"
export K8S_VERSION="$K8S_VERSION"
export CALICO_VERSION="$CALICO_VERSION"
export POD_NETWORK_CIDR="$POD_NETWORK_CIDR"
export HOSTNAME="$HOSTNAME"
export INSTANCE_ID="$INSTANCE_ID"
export KARPENTER_VERSION="$KARPENTER_VERSION"
export KARPENTER_CONTROLLER_ROLE_ARN="$KARPENTER_CONTROLLER_ROLE_ARN"
export KARPENTER_INSTANCE_ROLE_ARN="$KARPENTER_INSTANCE_ROLE_ARN"
export AMI_ID="$AMI_ID"
export CLUSTER_NAME="$CLUSTER_NAME"
export IP_ADDR="$IP_ADDR"
$(declare -f log setup_controlplane)
setup_controlplane
EOF
else
    log "Error: Invalid node type specified. Must be 'controlplane' or 'worker'"
    exit 1
fi
