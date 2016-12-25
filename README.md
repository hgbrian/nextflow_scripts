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

