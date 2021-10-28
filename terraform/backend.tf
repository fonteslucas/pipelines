terraform {
  backend "s3" {
    key    = "pipeline/pipeline.tfstate"
    bucket = "myterraform-backend-tfstate"
    region = "us-east-1"
  }
}