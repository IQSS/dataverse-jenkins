#!/bin/bash -e

# For docs, see the "Deployment" page in the Dev Guide.

# repo and branch defaults
REPO_URL_DEFAULT='https://github.com/IQSS/dataverse-jenkins.git'
BRANCH_DEFAULT='master'
PEM_DEFAULT=${HOME}
SIZE='c4.large'

usage() {
  echo "Usage: $0 -h <hostname> -b <dataverse-jenkins branch> -r <repo> -p <pem_dir> -g <group_vars>" 1>&2
  echo "default branch is master"
  echo "default repo is https://github.com/IQSS/dataverse-jenkins"
  echo "default .pem location is ${HOME}"
  echo "example group_vars may be retrieved from https://raw.githubusercontent.com/IQSS/dataverse-jenkins/ansible/master/defaults/main.yml"
  exit 1
}

while getopts ":h:a:r:b:g:p:" o; do
  case "${o}" in
  h)
    DJ_HOSTNAME=${OPTARG}
    ;;
  r)
    REPO_URL=${OPTARG}
    ;;
  b)
    DJ_BRANCH=${OPTARG}
    ;;
  g)
    GRPVRS=${OPTARG}
    ;;
  p)
    PEM_DIR=${OPTARG}
    ;;
  *)
    usage
    ;;
  esac
done

# test for ansible group_vars
if [ ! -z "$GRPVRS" ]; then
   GVFILE=$(basename "$GRPVRS")
   GVARG="-e @$GVFILE"
   echo "using $GRPVRS for extra vars"
fi

# test for CLI args
if [ ! -z "$REPO_URL" ]; then
   GVARG+=" -e dataverse_repo=$REPO_URL"
   echo "using repo $REPO_URL"
else
   GVARG+=" -e dataverse_repo=$REPO_URL_DEFAULT"
fi

if [ ! -z "$DJ_BRANCH" ]; then
   GVARG+=" -e dataverse_branch=$DJ_BRANCH"
   echo "using branch $DJ_BRANCH"
fi

if [ ! -z "$DJ_HOSTNAME" ]; then
   GVARG+=" -e jenkins_hostname=$DJ_HOSTNAME"
   echo "using hostname $DJ_HOSTNAME"
fi

# ansible doesn't care about pem_dir (yet)
if [ -z "$PEM_DIR" ]; then
   PEM_DIR="$PEM_DEFAULT"
fi

AWS_CLI_VERSION=$(aws --version)
if [[ "$?" -ne 0 ]]; then
  echo 'The "aws" program could not be executed. Is it in your $PATH?'
  exit 1
fi

if [[ $(git ls-remote --heads $REPO_URL $DJ_BRANCH | wc -l) -eq 0 ]]; then
  echo "Branch \"$DJ_BRANCH\" does not exist at $REPO_URL"
  usage
  exit 1
fi

SECURITY_GROUP='dataverse-sg'
GROUP_CHECK=$(aws ec2 describe-security-groups --group-name $SECURITY_GROUP)
if [[ "$?" -ne 0 ]]; then
  echo "Creating security group \"$SECURITY_GROUP\"."
  aws ec2 create-security-group --group-name $SECURITY_GROUP --description "security group for Dataverse"
  aws ec2 authorize-security-group-ingress --group-name $SECURITY_GROUP --protocol tcp --port 22 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-name $SECURITY_GROUP --protocol tcp --port 80 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-name $SECURITY_GROUP --protocol tcp --port 443 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-name $SECURITY_GROUP --protocol tcp --port 8080 --cidr 0.0.0.0/0
fi

RANDOM_STRING="$(uuidgen | cut -c-8)"
KEY_NAME="key-$USER-$RANDOM_STRING"

PRIVATE_KEY=$(aws ec2 create-key-pair --key-name $PEM_DIR/$KEY_NAME --query 'KeyMaterial' --output text)
if [[ $PRIVATE_KEY == '-----BEGIN RSA PRIVATE KEY-----'* ]]; then
  PEM_FILE="$PEM_DIR/$KEY_NAME.pem"
  printf -- "$PRIVATE_KEY" >$PEM_FILE
  chmod 400 $PEM_FILE
  echo "Your newly created private key file is \"$PEM_FILE\". Keep it secret. Keep it safe."
else
  echo "Could not create key pair. Exiting."
  exit 1
fi

# The AMI ID may change in the future and the way to look it up is with the
# following command, which takes a long time to run:
#
# aws ec2 describe-images  --owners 'aws-marketplace' --filters 'Name=product-code,Values=aw0evgkw8e5c1q413zgy5pjce' --query 'sort_by(Images, &CreationDate)[-1].[ImageId]' --output 'text'
#
# To use this AMI, we subscribed to it from the AWS GUI.
# AMI IDs are specific to the region.
AMI_ID='ami-9887c6e7'
# Smaller than medium lead to Maven and Solr problems.
echo "Creating EC2 instance"
# TODO: Add some error checking for "ec2 run-instances".
INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI_ID --security-groups $SECURITY_GROUP --count 1 --instance-type $SIZE --key-name $PEM_DIR/$KEY_NAME --query 'Instances[0].InstanceId' --block-device-mappings '[ { "DeviceName": "/dev/sda1", "Ebs": { "DeleteOnTermination": true } } ]' | tr -d \")
echo "Instance ID: "$INSTANCE_ID
echo "giving instance 60 seconds to wake up..."
sleep 60
echo "End creating EC2 instance"

PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[*].Instances[*].[PublicDnsName]" --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[*].Instances[*].[PublicIpAddress]" --output text)

USER_AT_HOST="centos@${PUBLIC_DNS}"
echo "New instance created with ID \"$INSTANCE_ID\". To ssh into it:"
echo "ssh -i $PEM_FILE $USER_AT_HOST"

echo "Please wait at least 15 minutes while the branch \"$DJ_BRANCH\" from $REPO_URL is being deployed."

if [ ! -z "$GRPVRS" ]; then
   scp -i $PEM_FILE -o 'StrictHostKeyChecking no' -o 'UserKnownHostsFile=/dev/null' -o 'ConnectTimeout=300' $GRPVRS $USER_AT_HOST:$GVFILE
fi

echo "git clone -b $DJ_BRANCH $REPO_URL dataverse-jenkins"

# epel-release is installed first to ensure the latest ansible is installed after
# TODO: Add some error checking for this ssh command.
ssh -T -i $PEM_FILE -o 'StrictHostKeyChecking no' -o 'UserKnownHostsFile=/dev/null' -o 'ConnectTimeout=300' $USER_AT_HOST <<EOF
sudo yum -y install epel-release
#sudo yum -y install https://releases.ansible.com/ansible/rpm/release/epel-7-x86_64/ansible-2.7.9-1.el7.ans.noarch.rpm
sudo yum -y install ansible git nano curl java-1.8.0-openjdk
git clone -b $DJ_BRANCH $REPO_URL dataverse-jenkins
export ANSIBLE_ROLES_PATH=.
pwd
ansible-playbook -v dataverse-jenkins/ansible/dataverse-jenkins.pb --connection=local $GVARG
EOF

# Port 8080 has been added because Ansible puts a redirect in place
# from HTTP to HTTPS and the cert is invalid (self-signed), forcing
# the user to click through browser warnings.
CLICKABLE_LINK="http://${PUBLIC_DNS}"
echo "To ssh into the new instance:"
echo "ssh -i $PEM_FILE $USER_AT_HOST"
echo "Branch $DJ_BRANCH from $REPO_URL has been deployed to $CLICKABLE_LINK"
echo "When you are done, please terminate your instance with:"
echo "aws ec2 terminate-instances --instance-ids $INSTANCE_ID"