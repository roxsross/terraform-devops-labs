# MiniStack = emulador local. Todo apunta al endpoint local.
# Las credenciales "test" son ficticias: MiniStack no valida credenciales reales.
provider "aws" {
  region = var.aws_region

  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigatewayv2 = var.ministack_endpoint
    dynamodb     = var.ministack_endpoint
    iam          = var.ministack_endpoint
    lambda       = var.ministack_endpoint
    sts          = var.ministack_endpoint
  }

  default_tags {
    tags = {
      Project     = "terraform-devops-labs"
      Environment = "ministack"
      ManagedBy   = "terraform"
    }
  }
}
