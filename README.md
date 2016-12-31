Running nextflow cloud on AWS
=============================

1. Create a simple nextflow pipeline
2. Run it in Docker and push the Docker image to AWS EC2 Container Service
3. Run the pipeline on AWS using `nextflow cloud` and `nxf_cloud.sh`


1. Running the pipeline locally
-------------------------------

A minimal nextflow pipeline, `blast.nf`, from 
[nextflow-io/examples](https://www.github.com/nextflow-io/examples) is included.
The pipeline reads in a local fasta, `sample.fa` 
and blasts it against a local protein database, `examples/pdb/tiny`

If nextflow and blastp are installed on your local computer, the pipeline can be run as follows:

    nextflow run blast.nf


2. Running the pipeline in Docker
---------------------------------
By running the pipeline in Docker, we can:
(a) freeze the environment;
(b) deploy the Docker image to remote servers.
The included Dockerfile is a minimal miniconda image (based on debian-jessie) 
that just basically just installs blast.

First, build the miniconda Docker image (you must have docker installed):

    export NXF_username="NXF_$(whoami)"
    docker build . -t "${NXF_username}/blast"

Then run `docker images` and you should see something like this:
    
    NXF_hgbrian/blast    latest   18d0ebc2f62e   19 hours ago   528.8 MB

Then to run the pipeline with docker, nextflow.config must include the container name:

    process {
      container = '${NXF_username}/blast'
    }
    
Run and the output should be the same:

    nextflow run blast.nf -with-docker



3. Running the pipeline in Docker on AWS
----------------------------------------
To run this pipeline on the cloud, we need to do two things:
- move the code over to the cloud
- move the data over to the cloud

There are two scripts being used:
- **nxf_cloud.sh** : a bash script to help manage the VPC, cloud, etc.
- **nextflow.config** : the nextflow config file also includes information on nextflow's cloud setup


Because these two files need to share information, 
I'll first set four environment variables:
- **NXF_username**    : a username for this project (e.g., NXF_hgbrian)
- **NXF_github_repo** : the location of the code (e.g., hgbrian/nextflow_scripts)
- **NXF_static_path** : the location of the data (e.g., /pdb, s3://${static_bucket}/pdb)
- **NXF_out_path**    : the location where results should be written (e.g., results.txt, s3://${out_bucket}/results.txt)

I'll also need to set up an AWS user. These credentials must be stored somewhere:
- **NXF_accessKey**
- **NXF_secretKey**

Create a new user to get the secret key:

    aws iam create-access-key --user-name ${NXF_username} > ${NXF_username}_credentials.txt

The user must have access to EC2, EFS, s3, etc. 
For example, administrators have all these permissions.
Check what groups are assigned to this user (probably none) and add to group "administrators".

    aws iam list-groups-for-user --user-name ${NXF_username} --output text
    aws iam add-user-to-group --group-name administrators --user-name ${NXF_username}


3b. Set up a cluster on AWS
---------------------------

Create a filesystem associated with this $username (one filesystem per user)
    ./nfvpc.sh setup_vpc
    ./nfvpc.sh setup_efs

Log into ECR (create a repository for $username if it doesn't exist)
    ./nfvpc.sh setup_ecr
    #319133706199.dkr.ecr.eu-west-1.amazonaws.com/nextflowuser_repo


3c. Docker and ECR
------------------
This `blast` pipeline will be run inside docker:

    docker build . -t nextflowuser/blast

The docker image must be tagged with the ECR repo:

    docker tag ${NXF_username}/blast:latest ${NXF_AWS_container_id}
    docker push ${NXF_AWS_container_id}




nxf_cloud.sh
============
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

