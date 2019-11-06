Installing Jenkins for Dataverse
================================

## Quickstart

This should spin up a working Jenkins installation on AWS EC2:

    ec2/ec2-create-instance.sh -b develop -r https://github.com/IQSS/dataverse-jenkins.git

## Custom Configuration

You can customize your installation of Jenkins by passing a custom "group vars" file.

    cp ansible/defaults/main.yml groupvars.yml
    vi groupvars.yml # add AWS credentials, etc.
    ec2/ec2-create-instance.sh -b develop -r https://github.com/IQSS/dataverse-jenkins.git -g groupvars.yml

## Hardware Requirements

- AWS EC2 [t2.large][] or equivalent with 8 GB RAM and 2 CPUs

## Sofware Requirements

- CentOS 7

## Installing Jenkins

As root:

    git clone https://github.com/IQSS/dataverse-jenkins.git
    cd dataverse-jenkins
    ./install-jenkins.sh

If the installation was successful, you should be able to get the version of Jenkins installed with this command:

    java -jar /opt/jenkins-cli.jar -s http://localhost:8080 -auth admin:admin version

## Adding a job

Assuming you have already cloned the repo, as root:

    cd dataverse-jenkins
    ./import-job.sh <jobname>

The script defaults to "IQSS-Dataverse-Develop"

[t2.large]: https://aws.amazon.com/ec2/instance-types/t2/
