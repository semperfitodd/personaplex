terraform {
  backend "s3" {
    bucket = "bsc.sandbox.terraform.state"
    key    = "personaplex/terraform.tfstate"
    region = "us-east-2"
  }
}
