output "function_name" {
  description = "The deployed OpenFaaS function name"
  value       = var.function_name
}

output "function_url" {
  description = "URL to invoke the function"
  value       = "https://openfaas.local.dev/function/${var.function_name}"
}
