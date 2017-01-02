#!/bin/bash

# ----------------------------------------------------------------------------------------
# This is a script that helps create a cluster on AWS and deploy nextflow pipelines to 
# that cluster.
#
#
# To use:
#
# 0. Set global env vars: NXF_username NXF_github_repo
# 1. Create an AWS VPC:  ./nxf_cloud.sh create_vpc
# 2. Create an EFS:      ./nxf_cloud.sh create_efs
#

required_env_vars="NXF_username
NXF_github_repo
NXF_AWS_subnet_id
NXF_AWS_efs_id
NXF_AWS_efs_mnt
NXF_AWS_container
NXF_AWS_accessKey
NXF_AWS_secretKey"

available_fns="get_cloud_info
create_vpc
shutdown_vpc
create_nextflow_cluster
shutdown_nextflow_cluster"


# ----------------------------------------------------------------------------------------
# initial setup
# Get information on which environment vars are set.
# Get information on whether a cluster exists/
# Get external IP.
#
get_config() {
    is_env_set=""
    is_env_not=""
    
    for env_var in $required_env_vars
    do
        # http://unix.stackexchange.com/questions/251893/get-environment-variable-by-variable-name
        if [ "${!env_var}" ]; then 
            is_env_set="${is_env_set} ${env_var}"
        else
            is_env_not="${is_env_not} ${env_var}"
        fi
    done
    # remove first space
    is_env_set="${is_env_set:1}"
    is_env_not="${is_env_not:1}"


    #
    # Check if this user has been set up on AWS. If not the user must be set up.
    #
    userinfo=$(aws iam get-user --user-name $username --profile $username)
    userexists=$(echo "$userinfo" |cut -f6)

    if [ "$userexists" != "$username" ]; then
      echo "no such user: $username/$userexists"
      echo "run 'aws configure --profile $username' to setup; exiting"
      exit
    fi

    #
    # Get my external ip address
    #
    external_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

    #
    # Check if a VPC and/or nextflow cloud exists already
    #
    vpcinfo=$(aws ec2 describe-vpcs --output text --profile "${username}")
    vpc_id=$(echo "${vpcinfo}" |cut -f7)
    if [ "$vpc_id" == '' ]; then vpc_id="No VPC available"; fi

    clusterinfo=$(nextflow cloud list)
    
    echo "================================"
    echo "| current config               |"
    echo "================================"
    echo "username:       ${username}"
    echo "github_repo:    ${github_repo}"
    echo "external_ip:    ${external_ip}"
    echo "vpc:            ${vpc_id:-[None]}"
    echo "cluster:       " ${clusterinfo} # remove newlines in output by removing quotes
    echo "envs_are_set:   ${is_env_set:-[None]}"
    echo "envs_not_set:   ${is_env_not:-[None]}"
    echo "functions:     " ${available_fns}
}


# ----------------------------------------------------------------------------------------
# aws setup
#

create_vpc() {
    echo "================================"
    echo "| setup vpc                    |"
    echo "================================"
    
    #
    # VPC
    #
    vpcinfo=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --profile $username)
    vpc_id=$(echo "$vpcinfo" |cut -f7)
    echo "vpc_id:       ${vpc_id:-[None]}"

    aws ec2 modify-vpc-attribute --vpc-id $vpc_id --enable-dns-hostnames --profile $username
    
    #
    # Subnet; the subnet_id needs to go into nextflow.config
    #
    subnetinfo=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.0.0/24 --profile $username)
    subnet_id=$(echo "$subnetinfo" |grep $vpc_id |cut -f9)
    echo "subnet_id:    ${subnet_id:-[None]}"
    
    aws ec2 modify-subnet-attribute --subnet-id $subnet_id --map-public-ip-on-launch --profile $username

    #
    # Security group. Use the default VPC security group and add rules to it to allow ssh
    # Creating a security group and attaching it did not work but would be better
    #
    sg_id=$(aws ec2 describe-security-groups --output text --profile $username |grep $vpc_id |cut -f3)
    echo "sg_id:        ${sg_id:-[None]}"
         
    aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol tcp --port 22 --cidr $external_ip/32 --profile $username
    aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol tcp --port 22 --source-group "$sg_id" --profile $username

    #
    # Internet gateway
    #
    igw_id=$(aws ec2 create-internet-gateway --profile $username |cut -f 2)
    echo "igw_id:       ${igw_id:-[None]}"
    aws ec2 attach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id --profile $username

    #
    # Route tables and route
    #
    rtb_id=$(aws ec2 describe-route-tables --output text --profile $username |grep $vpc_id |cut -f2)
    echo "rtb_id:       ${rtb_id:-[None]}"

    isroute=$(aws ec2 create-route --route-table-id $rtb_id --gateway-id $igw_id --destination-cidr-block 0.0.0.0/0 --profile $username)
    if [ "$isroute" != "True" ]; then 
        echo "aws ec2 create-route returned '$isroute' instead of True; exiting"
        exit
    fi
}

get_cloud_info() {
    echo "================================"
    echo "| get cloud info               |"
    echo "================================"

    vpcinfo=$(aws ec2 describe-vpcs --output text --profile $username)
    vpc_id=$(echo "$vpcinfo" | cut -f7)
    
    if [ "$vpc_id" != "" ]; then
        echo "vpc_id:       ${vpc_id:-[None]}"

        subnetinfo=$(aws ec2 describe-subnets --output text --profile $username)
        subnet_id=$(echo "${subnetinfo}" | grep $vpc_id | cut -f9)
        echo "subnet_id:    ${subnet_id:-[None]}"
        #echo "export NXF_AWS_subnet_id=${subnet_id}" >"${env_vars_file}"

        sginfo=$(aws ec2 describe-security-groups --output text --profile $username | grep $vpc_id)
        sg_id=$(echo "$sginfo" | cut -f3)
        echo "sg_id:        ${sg_id:-[None]}"

        eni_id=$(aws ec2 describe-network-interfaces --output text --profile $username | grep $vpc_id | cut -f5)
        echo "eni_id:       ${eni_id:-[None]}"

        rtb_id=$(aws ec2 describe-route-tables --output text --profile $username | grep $vpc_id | cut -f2)
        echo "rtb_id:       ${rtb_id:-[None]}"

        igw_id=$(aws ec2 describe-internet-gateways --profile $username |grep -B1 $vpc_id |head -1 | cut -f2)
        echo "igw_id:       ${igw_id:-[None]}"

        efs_id=$(aws efs describe-file-systems --profile $username | grep "^FILESYSTEMS" | head -1 | cut -f4)
        echo "efs_id:       ${efs_id:-[None]}"
        #echo "export NXF_AWS_efs_id=${efs_id}" >>"${env_vars_file}"

        ecr_url=$(aws ecr describe-repositories --profile $username | grep "^REPOSITORIES" | head -1 | cut -f6)
        echo "ecr_url:      ${ecr_url:-[None]}"
        #echo "export NXF_AWS_container=${ecr_url}" >>"${env_vars_file}"
        
        #echo "writing out nextflow.nxf_cloud2.config"
        cat nextflow.config | \
        awk '{while(match($0,"[$]{[^}]*}")) {var=substr($0,RSTART+2,RLENGTH -3);gsub("[$]{"var"}",ENVIRON[var])}}1' \
        > nextflow.env_vars.config

    else
        echo "No vpc exists; exiting"
        exit
    fi
}


# ----------------------------------------------------------------------------------------
# Shut down VPC, attempt to delete all traces from AWS
# This can go wrong if the EFS is till mounted.
# Variables in here come are initialized during get_cloud_info
#
shutdown_vpc() {
    echo "================================"
    echo "| shutdown vpc                 |"
    echo "================================"

    aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id --profile $username
    aws ec2 delete-internet-gateway --internet-gateway-id $igw_id --profile $username

    aws ec2 delete-network-interface --network-interface-id $eni_id --profile $username
    aws ec2 delete-route --route-table-id $rtb_id --destination-cidr-block 0.0.0.0/0 --profile $username
    aws ec2 delete-subnet --subnet-id $subnet_id --profile $username
    aws ec2 delete-vpc --vpc-id $vpc_id --profile $username
}

# ----------------------------------------------------------------------------------------
# Set up an EFS on AWS and mount it.
# EFS initially uses no space, and grows as you add files to it.
#
setup_efs() {
    echo "================================"
    echo "| setup efs                    |"
    echo "================================"

    efsinfo=$(aws efs describe-file-systems --profile "${username}" | grep "${username_sha}" | grep "^FILESYSTEMS")

    if [ "${efsinfo}" == '' ]; then
        echo "No EFS exits. Creating EFS using id $username_sha:"
        efsinfo=$(aws efs create-file-system --creation-token $username_sha --profile $username)
        efs_id=$(echo "${efsinfo}" | cut -f3)
    else
        echo "EFS already exists: ${efsinfo}"
        efs_id=$(echo "${efsinfo}" | cut -f4)
    fi
    echo "efs_id:         ${efs_id}"

    echo "[WARNING] Not mounting fs??? nextflow does it"
    # I may not need to do this? (cut -f4 to get fsmt-id)
    #aws efs create-mount-target --file-system-id fs-6af50da3 --subnet-id subnet-9a4462ec --profile $username
}

# ----------------------------------------------------------------------------------------
# Set up a container repo on AWS, if it doesn't already exist
#
setup_ecr() {
    echo "================================"
    echo "| setup ecr                    |"
    echo "================================"
    
    ecrinfo=$(aws ecr describe-repositories --profile "${username}" | grep "^REPOSITORIES")

    if [ "${ecrinfo}" == "" ]; then
        echo "No ECR ${repo_name} found, creating one"
        ecrinfo=$(aws ecr create-repository --repository-name "${repo_name}" --profile "${username}")
        ecr_url=$(echo "${ecrinfo}" | cut -f6)
    else
        if [ $(echo "${ecrinfo}" | cut -f5) != "${repo_name}" ]; then
            echo "Error in repo name? $(echo ${ecrinfo} | cut -f5) should be ${repo_name}"
        fi
        ecr_url=$(echo "${ecrinfo}" | cut -f6)
    fi
    echo "ecr_url:         ${ecr_url}"
    
    # This command provides a password for docker authentication
    docker_login_cmd=$(aws ecr get-login --profile "${username}")
    echo "Logging in to ECR using command: $(echo ${docker_login_cmd} | perl -pe 's/-p (.+?) (.+)/-p pwd $2/g')"
    $docker_login_cmd
}


# ----------------------------------------------------------------------------------------
# nextflow
#
create_nextflow_cluster() {
    echo "================================"
    echo "| create nextflow cluster      |"
    echo "================================"

    nfcinfo=$(nextflow cloud list)
    if [ "$nfcinfo" == "No cluster available" ]; then
        nextflow cloud create ${cluster_name}
    else
        echo "Cluster already exists; exiting"
        exit
    fi
}

shutdown_nextflow_cluster() {
    echo "================================"
    echo "| shut down nextflow cluster   |"
    echo "================================"

    nfcinfo=$(nextflow cloud list)
    if [ "$nfcinfo" == "No cluster available" ]; then
        echo "No cluster available; not shutting cluster down."
    else
        echo "first ssh in and unmount the efs drive"
        #nextflow cloud shutdown ${cluster_name}
    fi
}


run_on_cloud() {
    echo "================================"
    echo "| run on cloud                 |"
    echo "================================"
    echo "github_repo:          ${NXF_github_repo}"
    
    if [ "${is_env_not}" != "" ]; then echo "missing environment vars: ${is_env_not}; exiting" exit; fi

    aws_cloud_ip=$(aws ec2 describe-instances --profile $username | grep "^INSTANCES" | head -1 | cut -f13)

    ssh -i "/Users/briann/.ssh/ssh-key-${username}" "${username}@${aws_cloud_ip}" <<ENDSSH
echo "============================="
echo "| Preparing to run nextflow |"
echo "============================="

# remove export
export NXF_username="${NXF_username}"
export NXF_github_repo="${NXF_github_repo}"
export NXF_AWS_subnet_id="${NXF_AWS_subnet_id}"
export NXF_AWS_efs_id="${NXF_AWS_efs_id}"
export NXF_AWS_accessKey="${NXF_AWS_accessKey}"
export NXF_AWS_secretKey="${NXF_AWS_secretKey}"
export NXF_AWS_container="${NXF_AWS_container}"
export NXF_AWS_efs_mnt="${NXF_AWS_efs_mnt}"

docker pull "${NXF_AWS_container}"

# Why does this version not work? Puzzling.
#docker_login_cmd=\$(aws ecr get-login)
#echo "Logging in to ECR using command: \$(echo \${docker_login_cmd} | perl -pe 's/-p (.+?) (.+)/-p pwd $2/g')"
$(aws ecr get-login)

echo "=========================="
echo "| Syncing files          |"
echo "=========================="
if [ -d "\${NXF_ASSETS}/${NXF_github_repo}" ]; then
    cd "\${NXF_ASSETS}/${NXF_github_repo}"
    git pull
    cd -
fi

if [ "${static_path::5}" == "s3://" ]; then
    if [ ! -d "${NXF_AWS_efs_mnt}/${static_path:5}" ]; then
        aws s3 cp --recursive "${static_path}" "${NXF_AWS_efs_mnt}/${static_path:5}"
    fi
else
    echo "NotImplementedError: only s3 static_paths supported"
    exit
fi

echo "============================="
echo "| Running nextflow on cloud |"
echo "============================="
./nextflow run ${github_repo} -with-docker -profile aws -with-dag "${out_file}-dag.png" \
--db "${NXF_AWS_efs_mnt}/pdb/tiny" \
--out "${out_file}"
ENDSSH
}


# ----------------------------------------------------------------------------------------
# Running the code
#

usage() {
    printf "Available functions:"
    printf "\n${available_fns}\n"
}


if [ $# -eq 0 ]; then
    printf "\n[No arguments supplied]\n"
    usage
    exit 1
fi

arg=$1
shift

# http://linuxcommand.org/wss0130.php
while [ "$1" != "" ]; do
    case $1 in
        -u | --username )       shift
                                username=$1
                                ;;
        -g | --github_repo )    shift
                                github_repo=$1
                                ;;
        -s | --static_path )    shift
                                static_path=$1
                                ;;
        -o | --out_file )       shift
                                out_file=$1
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done


# ----------------------------------------------------------------------------------------
# Globals
# All these params/variables will need to be set to run `nextflow cloud`
#

if [ "${username}" == "" ] && [ "${NXF_username}" ];       then username="${NXF_username}"; fi
if [ "${github_repo}" == "" ] && [ "${NXF_github_repo}" ]; then username="${NXF_github_repo}"; fi
if [ "${static_path}" == "" ] && [ "${NXF_static_path}" ]; then static_path="${NXF_static_path}"; fi
if [ "${out_file}" == "" ] && [ "${NXF_out_file}" ];       then out_file="${NXF_out_file}"; fi

if [ "${username}" == "" ];    then echo "no NXF_username env var set; exiting"; exit 1; fi
if [ "${github_repo}" == "" ]; then echo "no NXF_github_repo env var set; exiting"; exit 1; fi
if [ "${static_path}" == "" ]; then echo "no static_path env var set; exiting"; exit 1; fi
if [ "${out_file}" == "" ];    then echo "no out_file env var set; exiting"; exit 1; fi

# AWS keys must also be set, broadly following nextflow.config
if [ "${NXF_AWS_accessKey}" ] || [ "${NXF_AWS_secretKey}" ]; then 
    AWS_accessKey="${NXF_AWS_accessKey}"
    AWS_secretKey="${NXF_AWS_secretKey}"
elif [ "${AWS_ACCESS_KEY_ID}" ] && [ "${AWS_SECRET_ACCESS_KEY}" ]; then
    AWS_accessKey="${AWS_ACCESS_KEY_ID}"
    AWS_secretKey="${AWS_SECRET_ACCESS_KEY}"
elif [ "${AWS_ACCESS_KEY}" ] && [ "${AWS_SECRET_KEY}" ]; then
    AWS_accessKey="${AWS_ACCESS_KEY}"
    AWS_secretKey="${AWS_SECRET_KEY}"
else
    printf "no AWS credentials set\nexiting"
    exit 1
fi

# ----------------------------------------------------------------------------------------
# Some derived globals
#
repo_name="${username}_repo"
cluster_name="${username}_cluster"
env_vars_file="env_vars.${username}.export"
username_sha=$(echo $username | shasum | cut -c1-16)


# ----------------------------------------------------------------------------------------
# Run code
#
get_config

if [ $arg == "create_vpc" ]; then
    create_vpc
    get_cloud_info
elif [ $arg == "setup_efs" ]; then
    setup_efs
    get_cloud_info
elif [ $arg == "setup_ecr" ]; then
    setup_ecr
    get_cloud_info
elif [ $arg == "shutdown_vpc" ]; then
    get_cloud_info
    shutdown_nextflow_cluster
    shutdown_vpc
elif [ $arg == "create_nextflow_cluster" ]; then
    create_nextflow_cluster
    get_cloud_info
elif [ $arg == "shutdown_nextflow_cluster" ]; then
    get_cloud_info
    shutdown_nextflow_cluster
elif [ $arg == "get_cloud_info" ]; then
    get_cloud_info
elif [ $arg == "run_on_cloud" ]; then
    run_on_cloud
else
    printf "\n[No allowed arguments supplied]\n"
    usage
    exit 1
fi




