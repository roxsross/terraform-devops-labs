variable "container_name" {
  description = "Nombre del contenedor"
  type        = string
  default     = "web-terraform"
}

variable "image_name" {
  description = "Imagen Docker que ejecutaremos"
  type        = string
  default     = "nginx:alpine"
}

variable "external_port" {
  description = "Puerto en nuestra computadora"
  type        = number
  default     = 8080

  validation {
    condition     = var.external_port >= 1024 && var.external_port <= 65535
    error_message = "El puerto debe estar entre 1024 y 65535."
  }
}
