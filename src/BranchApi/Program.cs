var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseSwagger();
app.UseSwaggerUI();

// Get branch name from environment variable
var branchName = Environment.GetEnvironmentVariable("BRANCH_NAME") ?? "unknown";
var version = Environment.GetEnvironmentVariable("VERSION") ?? "1.0.0";

app.MapGet("/", () => new
{
    message = "Side-by-Side Deployment Demo API",
    branch = branchName,
    version = version,
    timestamp = DateTime.UtcNow
})
.WithName("GetRoot")
.WithOpenApi();

app.MapGet("/health", () => new
{
    status = "healthy",
    branch = branchName,
    version = version
})
.WithName("HealthCheck")
.WithOpenApi();

app.MapGet("/api/info", () => new
{
    branch = branchName,
    version = version,
    environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production",
    machineName = Environment.MachineName,
    timestamp = DateTime.UtcNow
})
.WithName("GetInfo")
.WithOpenApi();

app.Run();
