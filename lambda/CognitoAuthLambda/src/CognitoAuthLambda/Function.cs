using Amazon.CognitoIdentityProvider;
using Amazon.CognitoIdentityProvider.Model;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using Amazon.Lambda.Serialization.SystemTextJson; // Update the namespace to use SystemTextJson
using System.Text.Json;

[assembly: LambdaSerializer(typeof(DefaultLambdaJsonSerializer))] // Update to use DefaultLambdaJsonSerializer

namespace CognitoAuthLambda
{

    public class Function
    {
        private static readonly HttpClient httpClient = new();
        private readonly AmazonCognitoIdentityProviderClient cognitoClient;
        private readonly string userPoolId;
        private readonly string clientId;
        private readonly string backendUrl;

        public Function()
        {
            cognitoClient = new AmazonCognitoIdentityProviderClient();
            userPoolId = Environment.GetEnvironmentVariable("USER_POOL_ID");
            clientId = Environment.GetEnvironmentVariable("CLIENT_ID");
            backendUrl = Environment.GetEnvironmentVariable("BACKEND_URL");
        }

        private async Task EnsureUserExistsWithPasswordAsync(string cpf, string password)
        {
            try
            {
                var createUserRequest = new AdminCreateUserRequest
                {
                    UserPoolId = userPoolId,
                    Username = cpf,
                    UserAttributes = new List<AttributeType>
                    {
                        new AttributeType { Name = "custom:cpf", Value = cpf }
                    },
                    MessageAction = MessageActionType.SUPPRESS, // Não envia convite
                    DesiredDeliveryMediums = new List<string>() // Nenhum canal de entrega
                };

                await cognitoClient.AdminCreateUserAsync(createUserRequest);
            }
            catch (UsernameExistsException)
            {
                // Usuário já existe, ignora
            }

            var setPasswordRequest = new AdminSetUserPasswordRequest
            {
                UserPoolId = userPoolId,
                Username = cpf,
                Password = password,
                Permanent = true
            };

            await cognitoClient.AdminSetUserPasswordAsync(setPasswordRequest);
        }

        public async Task<APIGatewayProxyResponse> FunctionHandler(APIGatewayProxyRequest request, ILambdaContext context) // Alterado para "FunctionHandler"
        {
            try
            {
                var authRequest = JsonSerializer.Deserialize<AuthRequest>(request.Body);

                if (string.IsNullOrEmpty(authRequest?.Cpf))
                {
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 400,
                        Body = "CPF é obrigatório"
                    };
                }

                Console.WriteLine(backendUrl);

                // Valida CPF no backend
                var response = await httpClient.GetAsync($"{backendUrl}/api/clientes/{authRequest.Cpf}");
                if (!response.IsSuccessStatusCode)
                {
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 401,
                        Body = "Cliente não encontrado"
                    };
                }

                string senhaFixa = "SenhaFixa123!"; // Defina sua senha fixa segura

                // Garante que o usuário exista com senha fixa
                await EnsureUserExistsWithPasswordAsync(authRequest.Cpf, senhaFixa);

                // Autentica com USER_PASSWORD_AUTH usando CPF e senha fixa
                var authParams = new Dictionary<string, string>
                {
                    { "USERNAME", authRequest.Cpf },
                    { "PASSWORD", senhaFixa }
                };

                var initiateAuthRequest = new InitiateAuthRequest
                {
                    AuthFlow = AuthFlowType.USER_PASSWORD_AUTH,
                    ClientId = clientId,
                    AuthParameters = authParams
                };

                var authResult = await cognitoClient.InitiateAuthAsync(initiateAuthRequest);
                var tokens = authResult.AuthenticationResult;

                var authResponse = new AuthResponse
                {
                    AccessToken = tokens.AccessToken,
                    IdToken = tokens.IdToken,
                    RefreshToken = tokens.RefreshToken
                };

                return new APIGatewayProxyResponse
                {
                    StatusCode = 200,
                    Body = JsonSerializer.Serialize(authResponse),
                    Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
                };
            }
            catch (Exception ex)
            {
                context.Logger.LogError($"Erro na autenticação: {ex.Message}");
                return new APIGatewayProxyResponse
                {
                    StatusCode = 500,
                    Body = "Erro interno no servidor"
                };
            }
        }
    }

    public class AuthRequest
    {
        public string Cpf { get; set; }
    }

    public class AuthResponse
    {
        public string AccessToken { get; set; }
        public string IdToken { get; set; }
        public string RefreshToken { get; set; }
    }
}
