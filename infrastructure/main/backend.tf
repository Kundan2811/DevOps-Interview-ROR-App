# ==============================================================================
# Terraform Remote State Backend
# ==============================================================================
# This tells Terraform to store its state file in S3 (instead of locally on
# disk) and to use DynamoDB for locking so concurrent applies don't corrupt
# the state. The bucket and table were created once, manually, via the
# separate ../bootstrap configuration - see infrastructure/bootstrap/main.tf
# ==============================================================================

terraform {
  backend "s3" {
    bucket         = "ror-devops-assignment-tfstate-305718149866"
    key            = "main/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ror-devops-assignment-tfstate-locks"
    encrypt        = true
  }
}
