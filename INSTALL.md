Installing Jenkins for Dataverse
================================

## Quickstart

This should spin up a working Jenkins installation on AWS EC2:

    ec2/ec2-create-instance.sh -b master -r https://github.com/IQSS/dataverse-jenkins.git

See below for other ways to install Jenkins.

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
    ./import-job.sh

[t2.large]: https://aws.amazon.com/ec2/instance-types/t2/
