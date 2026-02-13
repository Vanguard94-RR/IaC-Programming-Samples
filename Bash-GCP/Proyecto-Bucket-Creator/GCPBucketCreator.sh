#!/bin/bash -
#File name      :bucketcreator.sh
#Description    :Script to create Bucket in specified project
#Author         :Manuel Cortes
#Date           :20231018
#Version        :v1.0.0
#Usage          :./bucketcreator.sh or bash bucketcreator.sh
#Notes          :
#Bash_version   :5.1.16(1)-release
#============================================================================

# Color definitions
WHITE='\033[1;37m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
LGREEN='\033[1;32m'
LGRAY='\033[0;37m'
LBLUE='\033[1;34m'
LRED='\033[1;31m'
NC='\033[0m'
BLINKO='\033[5m'
BLINKC='\033[0m'

#=============================================================================
# VALIDATIONS
#=============================================================================

# Check if gcloud authentication exists
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        echo -e "${LRED}ERROR: No active GCP authentication found${NC}"
        echo -e "${YELLOW}Run: gcloud auth login${NC}"
        exit 1
    fi
}

# Validate bucket name format (GCP requirements: 3-63 chars, lowercase, no underscores)
validate_bucket_name() {
    local bucket=$1
    
    if [[ ! $bucket =~ ^[a-z0-9][a-z0-9._-]*[a-z0-9]$ ]] || [[ ${#bucket} -lt 3 ]] || [[ ${#bucket} -gt 63 ]]; then
        echo -e "${LRED}ERROR: Invalid bucket name: $bucket${NC}"
        echo -e "${YELLOW}Requirements: 3-63 characters, lowercase, no underscores${NC}"
        return 1
    fi
    return 0
}

# Validate project ID is not empty
validate_project_id() {
    local project=$1
    
    if [[ -z "$project" ]]; then
        echo -e "${LRED}ERROR: Project ID cannot be empty${NC}"
        return 1
    fi
    return 0
}

# Validate bucket after creation
validate_bucket_creation() {
    local bucket=$1
    
    echo -e
    echo -e "${LCYAN}Validating bucket configuration...${NC}"
    echo -e
    
    # Check if bucket exists
    if ! gsutil ls "gs://$bucket" &> /dev/null; then
        echo -e "${LRED}✗ Bucket validation failed: bucket not found${NC}"
        return 1
    fi
    echo -e "${LGREEN}✓ Bucket exists${NC}"
    
    # Check if uniform bucket-level access is enabled
    if gsutil uniformbucketlevelaccess get "gs://$bucket" 2>/dev/null | grep -q "Enabled"; then
        echo -e "${LGREEN}✓ Uniform bucket-level access: Enabled${NC}"
    else
        echo -e "${LRED}✗ Uniform bucket-level access: Not enabled${NC}"
        return 1
    fi
    
    # Check public access prevention
    local pap_status=$(gcloud storage buckets describe "gs://$bucket" --format="value(public_access_prevention)" 2>/dev/null)
    if [[ "$pap_status" == "inherited" ]]; then
        echo -e "${LGREEN}✓ Public Access Prevention: Enabled${NC}"
    else
        echo -e "${YELLOW}⚠ Public Access Prevention: $pap_status${NC}"
    fi
    
    # Check storage class
    local storage_class=$(gcloud storage buckets describe "gs://$bucket" --format="value(default_storage_class)" 2>/dev/null)
    if [[ -n "$storage_class" ]]; then
        echo -e "${LGREEN}✓ Storage Class: $storage_class${NC}"
    else
        echo -e "${LRED}✗ Could not retrieve storage class${NC}"
    fi
    
    # Check location
    local location=$(gcloud storage buckets describe "gs://$bucket" --format="value(location)" 2>/dev/null)
    if [[ "$location" == "us-central1" ]]; then
        echo -e "${LGREEN}✓ Location: $location${NC}"
    else
        echo -e "${YELLOW}⚠ Location: $location${NC}"
    fi
    
    return 0
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

# Confirmar Proyecto con GCloud
echo -e
echo -e "${LGREEN} >>----GNP Cloud Infrastructure Team----<<${NC}"
echo -e "${LGREEN} >>-------Standard Bucket Creation------<<${NC}"
echo -e

# Run validations
check_auth

echo -e "${YELLOW}This is going to create a bucket with the following specs: ${NC}"
echo -e "${WHITE}Single Region: ${LGREEN}us-central1 ${NC}"
echo -e "${WHITE}Storage Class: ${LGREEN}Standard${NC}"
echo -e "${WHITE}Bucket Level Access: ${LGREEN}Uniform${NC}"
echo -e "${WHITE}Public Acces Prevention: ${LGREEN}True${NC}"

echo -e
read -r -p "Enter Your GCP Project ID (Default: my-project): " projectid
projectid=${projectid:-my-project}

# Validate project ID
if ! validate_project_id "$projectid"; then
    exit 1
fi

echo -e
read -r -p "Enter Your Bucket Name (Default: my-bucket): " bucket
bucket=${bucket:-my-bucket}

# Validate bucket name
if ! validate_bucket_name "$bucket"; then
    exit 1
fi

echo -e
read -r -p "Enter Storage Class (STANDARD/NEARLINE/COLDLINE, Default: STANDARD): " storage_class
storage_class=${storage_class:-STANDARD}

# Validate storage class
if [[ ! "$storage_class" =~ ^(STANDARD|NEARLINE|COLDLINE)$ ]]; then
    echo -e "${LRED}ERROR: Invalid storage class: $storage_class${NC}"
    echo -e "${YELLOW}Valid options: STANDARD, NEARLINE, COLDLINE${NC}"
    exit 1
fi

echo -e
gcloud config set project "$projectid"
echo -e
echo -e "${LCYAN}Creating Bucket...${NC}"
echo -e

# Create bucket with error handling
if gcloud storage buckets create gs://"$bucket" --default-storage-class="${storage_class,,}" --uniform-bucket-level-access --project="$projectid" --location="us-central1" --public-access-prevention; then
    echo -e
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${LGREEN} Bucket Created${NC}"
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${WHITE}Bucket Name:${NC} ${LCYAN}$bucket${NC}"
    echo -e "${WHITE}Project:${NC} ${LCYAN}$projectid${NC}"
    echo -e "${WHITE}Storage Class:${NC} ${LCYAN}$storage_class${NC}"
    echo -e "${WHITE}Location:${NC} ${LCYAN}us-central1${NC}"
    echo -e "${WHITE}Access Level:${NC} ${LCYAN}Uniform${NC}"
    echo -e "${WHITE}Public Access Prevention:${NC} ${LCYAN}Enabled${NC}"
    echo -e "${LGREEN}========================================${NC}"
    
    # Validate bucket configuration
    if validate_bucket_creation "$bucket"; then
        echo -e
        echo -e "${LGREEN}✓ All validations passed!${NC}"
    else
        echo -e
        echo -e "${LRED}✗ Some validations failed${NC}"
        exit 1
    fi
else
    echo -e
    echo -e "${LRED}✗ Failed to create bucket: $bucket${NC}"
    exit 1
fi
echo
