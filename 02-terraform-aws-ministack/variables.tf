variable "aws_region" {
  description = "Región usada por MiniStack"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo unico para los nombres de los recursos"
  type        = string
  default     = "tf-labs-demo01"
}

variable "ministack_endpoint" {
  description = "Endpoint local del emulador MiniStack"
  type        = string
  default     = "http://localhost:4566"
}
