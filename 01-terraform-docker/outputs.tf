output "url_web" {
  description = "URL de la aplicación"
  value       = "http://localhost:${var.external_port}"
}

output "container_name" {
  description = "Nombre final del contenedor"
  value       = docker_container.web.name
}
