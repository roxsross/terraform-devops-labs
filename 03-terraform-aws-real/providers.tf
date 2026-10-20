# Proveedor AWS (nube real).
# NO usar credenciales reales en archivos Terraform.
# Autenticar vía variables de entorno, perfil de AWS CLI o rol IAM.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "terraform-devops-labs"
      Environment = "aws"
      ManagedBy   = "terraform"
    }
  }
}
