#!/bin/bash
# ----------------------------------------------------------------------------------------
# Globals (should match nextflow.config)
#
username=nextflowuser

# ----------------------------------------------------------------------------------------
# setup
#
initial_setup() {
    # use this id where the raw username is not appropriate?
    username_sha=$(echo $username | shasum | cut -c1-16)

    userinfo=$(aws iam get-user --user-name $username --profile $username)
    userexists=$(echo "$userinfo" |cut -f6)

    #
    # Check if this user has been set up on AWS. If not the user must be set up.
    #
    if [ "$userexists" != "$username" ]; then
      echo "no such user: $username/$userexists"
      echo "run 'aws configure --profile $username' to setup; exiting"
      exit
    fi

    external_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

    vpcinfo=$(aws ec2 describe-vpcs --output text --profile $username)
    vpc_id=$(echo "$vpcinfo" |cut -f7)
    if [ "$vpc_id" == '' ]; then vpc_id="No VPC available"; fi

    clusterinfo=$(nextflow cloud list)
    
    echo "================================"
    echo "| setup                        |"
    echo "================================"
    echo "username:     $username"
    echo "external_ip:  $external_ip"
    echo "vpc:          $vpc_id"
    echo "cluster:     " $clusterinfo # remove newlines in output by removing quotes
}


# ----------------------------------------------------------------------------------------
# aws setup
#

setup_vpc() {
    echo "================================"
    echo "| setup vpc                    |"
    echo "================================"
    
    #
    # VPC
    #
    vpcinfo=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --profile $username)
    vpc_id=$(echo "$vpcinfo" |cut -f7)
    echo "vpc_id:       $vpc_id"

    aws ec2 modify-vpc-attribute --vpc-id $vpc_id --enable-dns-hostnames --profile $username
    
    #
    # Subnet; the subnet_id needs to go into nextflow.config
    #
    subnetinfo=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.0.0/24 --profile $username)
    subnet_id=$(echo "$subnetinfo" |grep $vpc_id |cut -f9)
    echo "subnet_id:    $subnet_id    [COPY TO nextflow.config]"

    aws ec2 modify-subnet-attribute --subnet-id $subnet_id --map-public-ip-on-launch --profile $username

    #
    # Security group. Use the default VPC security group and add rules to it to allow ssh
    # Creating a security group and attaching it did not work but would be better
    #
    sg_id=$(aws ec2 describe-security-groups --output text --profile nextflowuser |grep $vpc_id |cut -f3)
    echo "sg_id:        $sg_id"
         
    aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol tcp --port 22 --cidr $external_ip/32 --profile $username
    aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol tcp --port 22 --source-group "$sg_id" --profile $username

    #
    # Internet gateway
    #
    igw_id=$(aws ec2 create-internet-gateway --profile $username |cut -f 2)
    echo "igw_id:       $igw_id"
    aws ec2 attach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id --profile $username

    #
    # Route tables and route
    #
    rtb_id=$(aws ec2 describe-route-tables --output text --profile $username |grep $vpc_id |cut -f2)
    echo "rtb_id:       $rtb_id"

    isroute=$(aws ec2 create-route --route-table-id $rtb_id --gateway-id $igw_id --destination-cidr-block 0.0.0.0/0 --profile $username)
    if [ "$isroute" != "True" ]; then 
        echo "aws ec2 create-route returned '$isroute' instead of True; exiting"
        exit
    fi
}

describe_vpc() {
    echo "================================"
    echo "| describe vpc                 |"
    echo "================================"

    vpcinfo=$(aws ec2 describe-vpcs --output text --profile $username)
    vpc_id=$(echo "$vpcinfo" | cut -f7)
    echo "vpc:          $vpcinfo"
    echo "vpc_id:       $vpc_id"
    
    echo "---------"
    
    if [ "$vpc_id" != "" ]; then
        subnetinfo=$(aws ec2 describe-subnets --output text --profile $username)
        subnet_id=$(echo "$subnetinfo" | grep $vpc_id | cut -f9)
        echo "subnet:       $subnetinfo"
        echo "subnet_id:    $subnet_id"
    
        echo "---------"
        sginfo=$(aws ec2 describe-security-groups --output text --profile $username | grep $vpc_id)
        sg_id=$(echo "$sginfo" | cut -f3)
        echo "sg_id:        $sg_id"

        eni_id=$(aws ec2 describe-network-interfaces --output text --profile $username | grep $vpc_id | cut -f5)
        echo "eni_id:       $eni_id"

        rtb_id=$(aws ec2 describe-route-tables --output text --profile $username | grep $vpc_id | cut -f2)
        echo "rtb_id:       $rtb_id"
    
        igw_id=$(aws ec2 describe-internet-gateways --profile $username |grep -B1 $vpc_id |head -1 | cut -f2)
        echo "igw_id:       $igw_id"


        efs_id=$(aws efs describe-file-systems --profile $username | grep "^FILESYSTEMS" | head -1 | cut -f4)
        echo "efs_id:       $efs_id"

        ecr_url=$(aws ecr describe-repositories --profile $username | grep "^REPOSITORIES" | head -1 | cut -f6)
        echo "ecr_url:      $ecr_url"
        
    else
        echo "No vpc exists; exiting"
        exit
    fi
}


# ----------------------------------------------------------------------------------------
# shut down VPC, delete all traces
# variables come from describe_vpc
#
shutdown_vpc() {
    echo "================================"
    echo "| shutdown vpc                 |"
    echo "================================"

    aws ec2 delete-network-interface --network-interface-id $eni_id --profile $username
    # aws ec2 delete-security-group --group-id $sg_id --profile $username
    aws ec2 delete-route --route-table-id $rtb_id --destination-cidr-block 0.0.0.0/0 --profile $username
    aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id --profile $username
    aws ec2 delete-internet-gateway --internet-gateway-id $igw_id --profile $username
    aws ec2 delete-subnet --subnet-id $subnet_id --profile $username
    aws ec2 delete-vpc --vpc-id $vpc_id --profile $username
}


setup_efs() {
    echo "================================"
    echo "| setup efs                    |"
    echo "================================"

    efsinfo=$(aws efs describe-file-systems --profile $username | grep "^FILESYSTEMS")

    if [ "$efsinfo" == '' ]; then
        echo "Creating EFS using id $username_sha"
        efsinfo = $(aws efs create-file-system --creation-token $username_sha --profile $username)
        efs_id=$(echo "$efsinfo" | cut -f3)
    else
        efs_id=$(echo "$efsinfo" | cut -f4)
    fi
    echo "efs_id:       $efs_id"

    # I may not need to do this (cut -f4 to get fsmt-id)
    #aws efs create-mount-target --file-system-id fs-6af50da3 --subnet-id subnet-9a4462ec --profile nextflowuser
}

setup_ecr() {
    echo "================================"
    echo "| setup ecr                    |"
    echo "================================"
    
    reponame="${username}_repo"

    ecrinfo=$(aws ecr describe-repositories --profile $username | grep "^REPOSITORIES")
    #REPOSITORIES    1482947163.0    319133706199    arn:aws:ecr:eu-west-1:319133706199:repository/nextflowuser_repo nextflowuser_repo       319133706199.dkr.ecr.eu-west-1.amazonaws.com/nextflowuser_repo
    if [ "$ecrinfo" == '' ]; then
        echo "No ECR ($reponame) found, creating one"
        ecrinfo=$(aws ecr create-repository --repository-name $reponame --profile $username)
        ecr_url=$(echo "$ecrinfo" | cut -f6)
    else
        if [ $(echo "$ecrinfo" | cut -f5) != "$reponame" ]; then
            echo "Error in repo name? $(echo $ecrinfo | cut -f5) should be $reponame"
        fi
        ecr_url=$(echo "$ecrinfo" | cut -f6)
    fi
    echo "ecr_url:     $ecr_url"
    
    # This command provides a password for docker authentication
    docker_login_cmd=$(aws ecr get-login --profile $username)
    echo "Logging in to ECR using command: $(echo $docker_login_cmd | perl -pe 's/-p (.+?) (.+)/-p pwd $2/g')"
    $docker_login_cmd
}


# ----------------------------------------------------------------------------------------
# nextflow
#
create_nextflow_cluster() {
    nfcinfo=$(nextflow cloud list)
    if [ "$nfcinfo" == "No cluster available" ]; then
        nextflow cloud create ${username}_cluster
    else
        echo "Cluster already exists; exiting"
        exit
    fi
}
shutdown_nextflow_cluster() {
    nfcinfo=$(nextflow cloud list)
    if [ "$nfcinfo" == "No cluster available" ]; then
        echo "No cluster available; not shutting cluster down; exiting"
        exit
    else
        nextflow cloud shutdown ${username}_cluster
    fi
}



# ----------------------------------------------------------------------------------------
# Run
#

initial_setup

if [ $# -eq 0 ]; then
    echo "No arguments supplied, e.g.: setup_vpc; describe_vpc; shutdown_vpc; create_nextflow_cluster; shutdown_nextflow_cluster;"
    exit
fi

arg=$1
if [ $arg == "setup_vpc" ]; then
    setup_vpc
elif [ $arg == "setup_efs" ]; then
    setup_efs
elif [ $arg == "setup_ecr" ]; then
    setup_ecr
elif [ $arg == "shutdown_vpc" ]; then
    shutdown_nextflow_cluster
    describe_vpc
    shutdown_vpc
elif [ $arg == "create_nextflow_cluster" ]; then
    create_nextflow_cluster
elif [ $arg == "shutdown_nextflow_cluster" ]; then
    shutdown_nextflow_cluster
elif [ $arg == "describe_vpc" ]; then
    describe_vpc
fi
