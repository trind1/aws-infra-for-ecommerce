/*
CURRENT DEV STATUS:
This provider alias is only needed by the unused public CloudFront certificate
configuration. The current dev environment does not load this module.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      # Required only because this reusable module can request the optional
      # CloudFront viewer certificate in us-east-1.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
*/
