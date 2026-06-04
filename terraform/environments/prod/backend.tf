terraform {
  backend "s3" {
    # The bucket name includes the AWS account ID, so it is supplied at init
    # time via partial configuration rather than hardcoded here:
    #
    #   terraform init -backend-config="bucket=petclinic-terraform-state-<account-id>"
    #
    # or, using the committed example as a template:
    #
    #   cp backend.hcl.example backend.hcl   # then fill in your account ID
    #   terraform init -backend-config=backend.hcl
    #
    # Run scripts/bootstrap-state.sh first to create the bucket and lock table;
    # it prints the exact init command with your account ID filled in.
    key            = "petclinic/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
