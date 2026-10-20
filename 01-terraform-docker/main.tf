# Descargamos/administramos la imagen.
resource "docker_image" "nginx" {
  name         = var.image_name
  keep_locally = false
}

# Creamos el contenedor utilizando la imagen anterior.
resource "docker_container" "web" {
  name  = var.container_name
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = var.external_port
  }
}
