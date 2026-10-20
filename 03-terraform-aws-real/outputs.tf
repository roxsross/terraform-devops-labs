output "api_url" {
  description = "URL pública de la API expuesta por API Gateway"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "api_id" {
  description = "Identificador de API Gateway"
  value       = aws_apigatewayv2_api.http_api.id
}

output "table_name" {
  value = aws_dynamodb_table.items.name
}

output "lambda_name" {
  value = aws_lambda_function.api.function_name
}
