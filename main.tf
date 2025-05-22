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

# Recurso "produtos"
resource "aws_api_gateway_resource" "produtos" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "produtos"
}

# Recurso "pedidos"
resource "aws_api_gateway_resource" "pedidos" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "pedidos"
}

# Recurso "pagamentos"
resource "aws_api_gateway_resource" "pagamentos" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "pagamentos"
}

# Recurso "producao"
resource "aws_api_gateway_resource" "producao" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "producao"
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
  uri                     = "${var.url_gerenciador}/api/clientes/{cpf}"
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
  uri                     = "${var.url_gerenciador}/api/clientes"
  passthrough_behavior    = "WHEN_NO_MATCH"
}

# Criar User Pool Cognito
resource "aws_cognito_user_pool" "user_pool" {
  name = "cliente-user-pool"

  auto_verified_attributes = ["email"]

  schema {
    name      = "cpf"
    attribute_data_type = "String"
    mutable   = false
  }

  lifecycle {
    ignore_changes = [schema]
  }
}

# Criar App Client Cognito
resource "aws_cognito_user_pool_client" "app_client" {
  name         = "cliente-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  generate_secret = false
}

resource "null_resource" "build_lambda" {
  provisioner "local-exec" {
    command = <<EOT
      dotnet publish ./lambda/CognitoAuthLambda/src/CognitoAuthLambda -c Release -r linux-x64 --self-contained false -o ./lambda/CognitoAuthLambda/publish
    EOT
    working_dir = "${path.module}"
  }

  triggers = {
    always_run = timestamp()
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/CognitoAuthLambda/publish"
  output_path = "${path.module}/lambda/CognitoAuthLambda/function.zip"

  depends_on = [null_resource.build_lambda]
}

# Criar Lambda
resource "aws_lambda_function" "auth_lambda" {
  function_name = "cliente-auth-lambda"
  role          = "arn:aws:iam::100527548163:role/LabRole"
  handler       = "CognitoAuthLambda::CognitoAuthLambda.Function::FunctionHandler" # Ajuste conforme seu projeto
  runtime       = "dotnet8"
  timeout       = 10
  
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.user_pool.id
      CLIENT_ID    = aws_cognito_user_pool_client.app_client.id
      REGION       = "us-east-1"
      BACKEND_URL  = var.url_gerenciador
    }
  }
}

# Permissão para API Gateway invocar Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Recurso "autenticar"
resource "aws_api_gateway_resource" "autenticar" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.clientes.id
  path_part   = "autenticar"
}

# Método POST para api/clientes/autenticar
resource "aws_api_gateway_method" "post_autenticar" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.autenticar.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integração Lambda Proxy
resource "aws_api_gateway_integration" "post_autenticar_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.autenticar.id
  http_method             = aws_api_gateway_method.post_autenticar.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth_lambda.invoke_arn
}

# Deploy da API Gateway no stage "prod"
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.get_cpf_integration,
    aws_api_gateway_integration.post_clientes_integration,
    aws_api_gateway_integration.post_autenticar_integration,
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