nextflow cloud
==============
This repo shows how to:

1. create a simple nextflow pipeline
2. run it in docker and pushing the docker image to ECS
3. run the pipeline on aws cloud using `nextflow cloud`

0. Set up a username and github url
-----------------------------------

    export NXF_username="hgbrian"
    export NXF_github_url="hgbrian/nextflow_scripts"


1. Running the pipeline locally
-------------------------------
A minimal nextflow pipeline, `blast.nf`, from 
[nextflow-io/examples](https://www.github.com/nextflow-io/examples) is included.
The pipeline reads in a local file, `sample.fa` 
and blasts it against a local protein database, `pdb/tiny`

If blastp is installed on your local computer, the pipeline can be run as follows:

    nextflow run blast.nf # or equivalently...
    nextflow run blast.nf -profile standard


2. Running the pipeline in Docker
---------------------------------
By running the pipeline in Docker, we can:
(a) freeze the environment running the pipeline;
(b) deploy the Docker image to remote servers.

The included Dockerfile is a minimal miniconda image (based on debian-jessie) 
that just basically just installs blast.

Build the miniconda Docker image (you must have docker installed):

    export NXF_username="NXF_$(whoami)"
    docker build . -t "${NXF_username}/blast"

Then run `docker images` and you should see something like this: `NXF_hgbrian/blast    latest   18d0ebc2f62e   19 hours ago   528.8 MB`

Then to run the pipeline using docker, make sure that the nextflow.config includes:

    process {
      container = '${NXF_username}/blast'
    }
    
Then run:

    nextflow run blast.nf -with-docker


<!-- 
CLOUD
export NXF_AWS_subnet_id="subnet-cc"
export NXF_AWS_efs_id="fs-dd"
export NXF_AWS_accessKey="aa"
export NXF_AWS_secretKey="bb/AU3"
export NXF_AWS_container_id="3211232.dkr.ecr.eu-west-1.amazonaws.com/nextflowuser_repo"
aws ecr get-login
 -->


Set up EFS on AWS
-----------------

Create a filesystem associated with this $username (one filesystem per user)
    ./nfvpc.sh setup_efs

Log into ECR (create a repository for $username if it doesn't exist)
    ./nfvpc.sh setup_ecr
    #319133706199.dkr.ecr.eu-west-1.amazonaws.com/nextflowuser_repo


Docker and ECR
--------------
This `blast` pipeline will be run inside docker:

    docker build . -t nextflowuser/blast

The docker image must be tagged with the ECR repo:

    docker tag ${NXF_username}/blast:latest ${NXF_AWS_container_id}
    docker push ${NXF_AWS_container_id}


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

