nextflow cloud
==============
This repo is an example of:

- creating a simple nextflow pipeline
- running it in docker
- deploying it to aws cloud using `nextflow cloud`

Steps
=====

- Create a nextflow.config file
- Create a workflow
- Test locally with docker

Run locally (`-profile standard` is optional, docker image is in `nextflow.config`):

    nextflow run blast2.nf -profile standard -with-docker

Run on the cloud:

    nextflow run blast2.nf -profile cloud -with-docker


Set up EFS on AWS
-----------------

Create a filesystem associated with this $username (one filesystem per user)
    ./nfvpc.sh setup_efs

Log into ECR (create a repository for $username if it doesn't exist)
    ./nfvpc.sh setup_ecr
    #319133706199.dkr.ecr.eu-west-1.amazonaws.com/nextflowuser_repo


Docker
------
This `blast` pipeline will be run inside docker:

    docker build . -t nextflowuser/blast

The docker image must be tagged with the ECR repo:

    docker tag nextflowuser/blast:latest $ecr_repo
    docker push $ecr_repo




nfvpc.sh
========
A script that creates and/or destroys a single-use VPC on AWS for use by `nextflow cloud`. 
The idea is to be able to create a VPC to enable running a nextflow job on the cloud, 
then tear down everything so that there are no lingering elements on AWS. 

For this to work you need:

- an account on AWS
- a user with sufficient privileges (e.g., nextflowuser, a member of the Administrator group)
- a key pair for that user (e.g., generated with `ssh-keygen -t rsa -f ~/.ssh/ssh-key-nextflowuser`)

Other notes:

- this is not tested very much, but works for me
- `ami-43f49030` (preconfigured for `nextflow cloud`) is only present in the eu-west (Ireland) region
  (see [https://www.nextflow.io/blog/2016/deploy-in-the-cloud-at-snap-of-a-finger.html])
- if `nextflow cloud shutdown` takes too long to shut down instances then the vpc teardown
  will not work

To run
------

    ./nfvpc.sh setup_vpc
    ./nfvpc.sh describe_vpc
    ./nfvpc.sh create_nextflow_cluster
    # ssh in and run `nextflow run hello`
    ./nfvpc.sh shutdown_nextflow_cluster
    ./nfvpc.sh shutdown_vpc


To run with EFS
---------------
    ./nfvpc.sh setup_vpc
    ./nfvpc.sh setup_efs
    ./nfvpc.sh setup_ecr
    ./nfvpc.sh describe_vpc
    ./nfvpc.sh create_nextflow_cluster
    # ssh in and run `nextflow run hello`
    ./nfvpc.sh shutdown_nextflow_cluster
    ./nfvpc.sh shutdown_vpc


Minimal nextflow.config
-----------------------

    cloud {
        userName = 'nextflowuser'
        keyFile = '~/.ssh/ssh-key-nextflowuser.pub'
        imageId = 'ami-43f49030'
        instanceType = 't2.nano'
        subnetId = 'subnet-xxx'
    }

    aws {
        accessKey = 'yyy'
        secretKey = 'zzz'
        region = 'eu-west-1'
    }

