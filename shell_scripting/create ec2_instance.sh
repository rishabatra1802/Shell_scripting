#!/bin/bash
#shebang statement for bash


set -euo pipefail
# Enable strict error handling

# Check if aws CLI is available; return 0 if installed, 1 otherwise
check_awscli() {
    if command -v aws &>/dev/null; then
        return 0
    else
        return 1
    fi
}

install_awscli() {
    local auto_accept=${1:-false}
    echo "AWS CLI not found."

    if [[ "$auto_accept" != true ]]; then
        read -r -p "Install AWS CLI v2 now? [y/N]: " answer || true
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            echo "Please install the AWS CLI and re-run the script." >&2
            return 1
        fi
    fi

    uname_s=$(uname -s || true)

    if [[ "$uname_s" == "Linux" ]]; then
        echo "Attempting to install AWS CLI v2 for Linux..."
        tmpdir=$(mktemp -d)
        pushd "$tmpdir" >/dev/null
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" || {
            echo "Failed to download AWS CLI installer." >&2; popd >/dev/null; rm -rf "$tmpdir"; return 1
        }
        if command -v unzip &>/dev/null; then
            unzip -q awscliv2.zip
        elif command -v apt-get &>/dev/null; then
            sudo apt-get update -y && sudo apt-get install -y unzip
            unzip -q awscliv2.zip
        else
            echo "Cannot unzip archive: 'unzip' not found. Please install 'unzip' or install AWS CLI manually." >&2
            popd >/dev/null; rm -rf "$tmpdir"; return 1
        fi
        sudo ./aws/install || { echo "Installer failed" >&2; popd >/dev/null; rm -rf "$tmpdir"; return 1; }
        popd >/dev/null
        rm -rf "$tmpdir"

    elif [[ "$uname_s" == "Darwin" ]]; then
        echo "Attempting to install AWS CLI via Homebrew..."
        if command -v brew &>/dev/null; then
            brew update && brew install awscli || { echo "brew install failed" >&2; return 1; }
        else
            echo "Homebrew is not installed. Please install Homebrew or AWS CLI manually." >&2
            return 1
        fi
    else
        echo "Automatic installation for OS '$uname_s' is not supported by this script. Please install AWS CLI v2 manually: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
        return 1
    fi

    if ! check_awscli; then
        echo "AWS CLI installation appears to have failed or aws is not on PATH." >&2
        return 1
    fi

    echo "AWS CLI installed: $(aws --version 2>/dev/null)"
    return 0
}



wait_for_instance() {
    local instance_id="$1"
    echo "Waiting for instance $instance_id to be in running state..."

    while true; do
        state=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].State.Name' --output text)
        if [[ "$state" == "running" ]]; then
            echo "Instance $instance_id is now running."
            break
        fi
        sleep 10
    done
} #this will wait for your instance to run and check its state 

create_ec2_instance() {
    local ami_id="$1"
    local instance_type="$2"
    local key_name="$3"
    local subnet_id="$4"
    local security_group_ids="$5"
    local instance_name="$6"

    # Validate required parameters
    if [[ -z "$ami_id" || -z "$key_name" || -z "$subnet_id" ]]; then
        echo "AMI_ID, KEY_NAME and SUBNET_ID are required." >&2
        show_help
        exit 1
    fi

    # Prepare security group IDs as an array (allow space-separated string)
    read -r -a sg_array <<< "$security_group_ids"

    # Build the aws CLI arguments
    aws_args=(--image-id "$ami_id" --instance-type "$instance_type" --key-name "$key_name" --subnet-id "$subnet_id")

    if (( ${#sg_array[@]} )); then
        aws_args+=(--security-group-ids "${sg_array[@]}")
    fi

    aws_args+=(--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}]" --query 'Instances[0].InstanceId' --output text)

    # Run aws command
    echo "Running: aws ec2 run-instances ${aws_args[*]}"
    instance_id=$(aws ec2 run-instances "${aws_args[@]}" 2>/dev/null || true)

    if [[ -z "$instance_id" ]]; then
        echo "Failed to create EC2 instance. See AWS CLI output for details." >&2
        return 1
    fi

    echo "Instance $instance_id created successfully."
    wait_for_instance "$instance_id"
}

main() {
    check_awscli || install_awscli

    echo "Creating EC2 instance..."

    # Specify the parameters for creating the EC2 instance
    AMI_ID=""
    INSTANCE_TYPE="t2.micro"
    KEY_NAME=""
    SUBNET_ID=""
    SECURITY_GROUP_IDS=""  # Add your security group IDs separated by space
    INSTANCE_NAME="Shell-Script-EC2-Demo"

    # Call the function to create the EC2 instance
    create_ec2_instance "$AMI_ID" "$INSTANCE_TYPE" "$KEY_NAME" "$SUBNET_ID" "$SECURITY_GROUP_IDS" "$INSTANCE_NAME"

    echo "EC2 instance creation completed."
}

main "$@"
