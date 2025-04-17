provider "aws" {
  region = "us-east-1"
}

# Cria a API REST
resource "aws_api_gateway_rest_api" "api" {
  name        = "cluster-proxy-api"
  description = "API Gateway restrito aos métodos GET e POST específicos"
}

# Recurso raiz "/"
data "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  path        = "/"
}

# Recurso "api"
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "api"
}

# Recurso "clientes"
resource "aws_api_gateway_resource" "clientes" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "clientes"
}

# Recurso path parameter "{cpf}" para GET
resource "aws_api_gateway_resource" "cpf" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.clientes.id
  path_part   = "{cpf}"
}

# Método GET para /api/clientes/{cpf}
resource "aws_api_gateway_method" "get_cpf" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.cpf.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.cpf" = true
  }
}

resource "aws_api_gateway_integration" "get_cpf_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.cpf.id
  http_method             = aws_api_gateway_method.get_cpf.http_method
  integration_http_method = "GET"
  type                    = "HTTP_PROXY"
  uri                     = "http://a2f9cc2d72bf940869ff82256efadc28-2115621353.us-east-1.elb.amazonaws.com:8080/api/clientes/{cpf}"
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.path.cpf" = "method.request.path.cpf"
  }
}

# Método POST para /api/clientes
resource "aws_api_gateway_method" "post_clientes" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.clientes.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_clientes_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.clientes.id
  http_method             = aws_api_gateway_method.post_clientes.http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  uri                     = "http://a2f9cc2d72bf940869ff82256efadc28-2115621353.us-east-1.elb.amazonaws.com:8080/api/clientes"
  passthrough_behavior    = "WHEN_NO_MATCH"
}

# Deploy da API Gateway no stage "prod"
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.get_cpf_integration,
    aws_api_gateway_integration.post_clientes_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  triggers = {
    redeploy = timestamp()
  }
}

# Output da URL pública da API Gateway
output "api_gateway_invoke_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}
