output "api_url" {
  description = "URL reportada por API Gateway; en MiniStack puede requerir una URL de invocación local"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "api_id" {
  description = "Identificador de API Gateway para construir la URL local si fuera necesaria"
  value       = aws_apigatewayv2_api.http_api.id
}

output "table_name" {
  value = aws_dynamodb_table.items.name
}

output "lambda_name" {
  value = aws_lambda_function.api.function_name
}
