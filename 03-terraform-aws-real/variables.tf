variable "aws_region" {
  description = "Región donde se crean los servicios AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo unico para los nombres de los recursos"
  type        = string
  default     = "tf-labs-demo01"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,35}$", var.project_name))
    error_message = "Usar 3-36 caracteres: comenzar con letra minúscula, luego letras, números o guiones."
  }
}

# Dejar vacío para que Terraform cree el rol de la Lambda (requiere permiso iam:CreateRole).
# Si el usuario no puede crear roles (p. ej. en un entorno de práctica), indicar aquí el ARN
# de un rol existente para reutilizarlo. Ese rol debe permitir que lambda.amazonaws.com lo
# asuma y tener acceso a DynamoDB y a CloudWatch Logs.
variable "lambda_role_arn" {
  description = "ARN de un rol IAM existente para la Lambda. Vacío = crear uno nuevo."
  type        = string
  default     = ""
}
